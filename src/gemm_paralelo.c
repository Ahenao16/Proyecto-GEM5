/*
 * gemm_paralelo.c - GEMM C = A x B en precisión simple, paralelizado por filas
 * con pthreads (E4 multiprocesador; también lo usa E5 coherencia).
 *
 * Uso:   gemm_paralelo N T
 *        N = tamaño de las matrices, T = número de hilos (= núcleos simulados)
 *
 * Reparto: bloques contiguos de filas. El hilo t calcula las filas
 * [t*N/T, (t+1)*N/T). Así cada hilo escribe su propio bloque de C y no hay
 * falso compartido salvo, como mucho, en una línea de caché por frontera.
 *
 * Región de interés (ROI): los hilos se crean ANTES de la ROI y esperan en una
 * barrera. El hilo principal (que también calcula, es el hilo 0) hace
 * m5_reset_stats y suelta la barrera; al terminar todos, otra barrera y
 * m5_dump_stats. Así la creación y el join de hilos quedan fuera de la medición.
 *
 * Compilar (dentro del contenedor):
 *   $CC_ARM -O2 -fno-tree-vectorize -static -pthread src/gemm_paralelo.c \
 *       -o gemm_paralelo -I$M5_INC -L$M5_LIB -lm5 -lm
 * Compilar nativo para probar (sin gem5):  gcc -O2 -DNO_M5 -pthread ... -lm
 */
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

typedef struct {
    int id;
    int T;
    int N;
    const float *A;
    const float *B;
    float *C;
} args_t;

static pthread_barrier_t inicio, fin;

/* Mismo bucle que gemm_escalar.c, pero solo para las filas [f0, f1). */
static void gemm_filas(const float *A, const float *B, float *C, int N,
                       int f0, int f1) {
    for (int i = f0; i < f1; i++) {
        for (int j = 0; j < N; j++) {
            float suma = 0.0f;
            for (int k = 0; k < N; k++) {
                suma += A[i * N + k] * B[k * N + j];
            }
            C[i * N + j] = suma;
        }
    }
}

static void *trabajador(void *p) {
    args_t *a = (args_t *)p;
    int f0 = (int)((long)a->id * a->N / a->T);
    int f1 = (int)((long)(a->id + 1) * a->N / a->T);

    pthread_barrier_wait(&inicio);          /* esperar el inicio de la ROI */
    gemm_filas(a->A, a->B, a->C, a->N, f0, f1);
    pthread_barrier_wait(&fin);             /* todos terminaron */
    return NULL;
}

static void init(float *A, float *B, int N) {
    for (int i = 0; i < N * N; i++) {
        A[i] = 1.0f + i;
        B[i] = 2.0f + i;
    }
}

static int check(const float *A, const float *B, const float *C, int N) {
    for (int i = 0; i < N; i++) {
        for (int j = 0; j < N; j++) {
            double esperado = 0.0;
            for (int k = 0; k < N; k++) {
                esperado += (double)A[i * N + k] * (double)B[k * N + j];
            }
            double diferencia = fabs((double)C[i * N + j] - esperado);
            double tolerancia = 1e-5 * (fabs(esperado) > 1.0 ? fabs(esperado) : 1.0);
            if (diferencia > tolerancia) {
                printf("Error en C[%d][%d]: obtenido=%f, esperado=%f\n",
                       i, j, C[i * N + j], esperado);
                return 1;
            }
        }
    }
    printf("Resultado correcto\n");
    return 0;
}

int main(int argc, char *argv[]) {
    int N = (argc > 1) ? atoi(argv[1]) : 16;
    int T = (argc > 2) ? atoi(argv[2]) : 1;

    if (N <= 0 || T <= 0 || T > N) {
        fprintf(stderr, "Uso: %s N T  (N > 0, 1 <= T <= N)\n", argv[0]);
        return 1;
    }

    float *A = malloc((size_t)N * N * sizeof(float));
    float *B = malloc((size_t)N * N * sizeof(float));
    float *C = malloc((size_t)N * N * sizeof(float));
    pthread_t *hilos = malloc((size_t)T * sizeof(pthread_t));
    args_t *args = malloc((size_t)T * sizeof(args_t));
    if (!A || !B || !C || !hilos || !args) {
        fprintf(stderr, "Error al reservar memoria\n");
        return 1;
    }

    init(A, B, N);
    pthread_barrier_init(&inicio, NULL, (unsigned)T);
    pthread_barrier_init(&fin, NULL, (unsigned)T);

    for (int t = 0; t < T; t++) {
        args[t] = (args_t){t, T, N, A, B, C};
    }
    /* Hilos 1..T-1; el hilo principal hace de hilo 0. */
    for (int t = 1; t < T; t++) {
        if (pthread_create(&hilos[t], NULL, trabajador, &args[t]) != 0) {
            fprintf(stderr, "Error creando el hilo %d\n", t);
            return 1;
        }
    }

    m5_reset_stats(0, 0);                   /* inicio ROI */
    trabajador(&args[0]);                   /* suelta 'inicio', calcula, espera 'fin' */
    m5_dump_stats(0, 0);                    /* fin ROI */

    for (int t = 1; t < T; t++) {
        pthread_join(hilos[t], NULL);
    }

    printf("N=%d hilos=%d\n", N, T);
    int resultado = check(A, B, C, N);

    pthread_barrier_destroy(&inicio);
    pthread_barrier_destroy(&fin);
    free(A); free(B); free(C); free(hilos); free(args);
    return resultado;
}
