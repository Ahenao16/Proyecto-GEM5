#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef NO_M5
#define m5_reset_stats(a, b) ((void)0)
#define m5_dump_stats(a, b)  ((void)0)
#else
#include <gem5/m5ops.h>
#endif

#define LINEA   64
#define MAX_HILOS 64
#define ITER_DEF  50000L

/* nopad: contadores contiguos (8 por línea). Alineado a línea para que el
 * resultado no dependa de dónde caiga el arreglo. */
static volatile long denso[MAX_HILOS] __attribute__((aligned(LINEA)));

/* pad: un contador por línea de caché. */
typedef struct {
    volatile long v;
    char relleno[LINEA - sizeof(long)];
} __attribute__((aligned(LINEA))) Contador;
static Contador separado[MAX_HILOS];

static int nhilos, usar_pad;
static long iters;
static pthread_barrier_t b_ini, b_fin;

static void trabajo(int id)
{
    volatile long *c = usar_pad ? &separado[id].v : &denso[id];
    for (long i = 0; i < iters; i++)
        *c = *c + 1;               /* volatile: fuerza load+store cada vuelta */
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
        fprintf(stderr, "Uso: %s <hilos> <nopad|pad> [iteraciones]\n", argv[0]);
        return 2;
    }
    nhilos = atoi(argv[1]);
    if (nhilos < 1 || nhilos > MAX_HILOS) {
        fprintf(stderr, "hilos fuera de rango (1..%d)\n", MAX_HILOS);
        return 2;
    }
    if (!strcmp(argv[2], "pad"))        usar_pad = 1;
    else if (!strcmp(argv[2], "nopad")) usar_pad = 0;
    else { fprintf(stderr, "modo debe ser nopad o pad\n"); return 2; }
    iters = (argc > 3) ? atol(argv[3]) : ITER_DEF;

    pthread_barrier_init(&b_ini, NULL, nhilos);
    pthread_barrier_init(&b_fin, NULL, nhilos);

    pthread_t th[MAX_HILOS];
    for (int i = 1; i < nhilos; i++)
        if (pthread_create(&th[i], NULL, hilo, (void *)(long)i)) {
            perror("pthread_create");
            return 1;
        }

    m5_reset_stats(0, 0);              /* inicio ROI */
    pthread_barrier_wait(&b_ini);      /* suelta a todos a la vez */
    trabajo(0);                        /* el hilo principal también trabaja (núcleo 0) */
    pthread_barrier_wait(&b_fin);
    m5_dump_stats(0, 0);               /* fin ROI */

    for (int i = 1; i < nhilos; i++) pthread_join(th[i], NULL);

    int ok = 1;                        /* verificación fuera de la ROI */
    for (int i = 0; i < nhilos; i++) {
        long v = usar_pad ? separado[i].v : denso[i];
        if (v != iters) { ok = 0; printf("hilo %d: %ld != %ld\n", i, v, iters); }
    }
    printf("false_sharing: hilos=%d modo=%s iter=%ld\n", nhilos, argv[2], iters);
    puts(ok ? "Resultado correcto" : "Resultado INCORRECTO");
    return ok ? 0 : 1;
}