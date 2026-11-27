
#include <math.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>

#ifdef NO_M5
#define m5_reset_stats(a, b) ((void)0)
#define m5_dump_stats(a, b)  ((void)0)
#else
#include <gem5/m5ops.h>
#endif

#define MAX_HILOS 64

static int N, nhilos;
static float *A, *B, *C, *R;
static pthread_barrier_t b_ini, b_fin;

/* Filas [ini, fin) de C = A x B (orden i-k-j, acceso secuencial a B y C) */
static void gemm_filas(const float *a, const float *b, float *c, int ini, int fin)
{
    for (int i = ini; i < fin; i++) {
        for (int j = 0; j < N; j++) c[i * N + j] = 0.0f;
        for (int k = 0; k < N; k++) {
            float aik = a[i * N + k];
            for (int j = 0; j < N; j++)
                c[i * N + j] += aik * b[k * N + j];
        }
    }
}

static void trabajo(int id)
{
    int ini = (int)((long)N * id / nhilos);
    int fin = (int)((long)N * (id + 1) / nhilos);
    gemm_filas(A, B, C, ini, fin);
}

static void *hilo(void *arg)
{
    int id = (int)(long)arg;
    pthread_barrier_wait(&b_ini);
    trabajo(id);
    pthread_barrier_wait(&b_fin);
    return NULL;
}

int main(int argc, char **argv)
{
    if (argc < 3) {
        fprintf(stderr, "Uso: %s <N> <hilos>\n", argv[0]);
        return 2;
    }
    N = atoi(argv[1]);
    nhilos = atoi(argv[2]);
    if (N < 1 || nhilos < 1 || nhilos > MAX_HILOS) {
        fprintf(stderr, "Argumentos fuera de rango\n");
        return 2;
    }

    size_t bytes = (size_t)N * N * sizeof(float);
    A = malloc(bytes); B = malloc(bytes); C = malloc(bytes); R = malloc(bytes);
    if (!A || !B || !C || !R) { fprintf(stderr, "sin memoria\n"); return 1; }
    for (int i = 0; i < N * N; i++) {
        A[i] = (float)((i % 7) + 1) * 0.5f;
        B[i] = (float)((i % 5) + 1) * 0.25f;
        C[i] = 0.0f;
    }

    pthread_barrier_init(&b_ini, NULL, nhilos);
    pthread_barrier_init(&b_fin, NULL, nhilos);
    pthread_t th[MAX_HILOS];
    for (int i = 1; i < nhilos; i++)
        if (pthread_create(&th[i], NULL, hilo, (void *)(long)i)) {
            perror("pthread_create");
            return 1;
        }

    m5_reset_stats(0, 0);              /* inicio ROI */
    pthread_barrier_wait(&b_ini);
    trabajo(0);
    pthread_barrier_wait(&b_fin);
    m5_dump_stats(0, 0);               /* fin ROI */

    for (int i = 1; i < nhilos; i++) pthread_join(th[i], NULL);

    /* Verificación fuera de la ROI: misma operación, secuencial */
    gemm_filas(A, B, R, 0, N);
    int ok = 1;
    for (int i = 0; i < N * N && ok; i++)
        if (fabsf(C[i] - R[i]) > 1e-3f * (fabsf(R[i]) + 1.0f)) ok = 0;

    printf("gemm_omp: N=%d hilos=%d\n", N, nhilos);
    puts(ok ? "Resultado correcto" : "Resultado INCORRECTO");
    return ok ? 0 : 1;
}