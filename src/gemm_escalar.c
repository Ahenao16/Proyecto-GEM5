#include <stdio.h>
#include <stdlib.h>
#include <gem5/m5ops.h>

void gemm(const float *A, const float *B, float *C, int N) {
    for (int i = 0; i < N; i++) {
        for (int j = 0; j < N; j++) {
            float suma = 0.0;

            for (int k = 0; k < N; k++) {
                suma += A[i * N + k] * B[k * N + j];
            }

            C[i * N + j] = suma;
        }
    }
}

void init(float *A, float *B, int N) {
    for (int i = 0; i < N * N; i++) {
        A[i] = 1.0+i;
        B[i] = 2.0+i;
    }
}

int check(const float *A, const float *B, const float *C, int N) {
    for (int i = 0; i < N; i++) {
        for (int j = 0; j < N; j++) {
            float esperado = 0.0f;

            for (int k = 0; k < N; k++) {
                esperado += A[i * N + k] * B[k * N + j];
            }

            if (fabsf(C[i * N + j] - esperado) > 1e-4f) {
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
    int N = 4; //N por si no se especifica

    if (argc > 1) {
        N = atoi(argv[1]);
    }

    if (N <= 0) {
        fprintf(stderr, "N debe ser positivo\n");
        return 1;
    }

    float *A = malloc((size_t)N * N * sizeof(float));
    float *B = malloc((size_t)N * N * sizeof(float));
    float *C = malloc((size_t)N * N * sizeof(float));

    if (A == NULL || B == NULL || C == NULL) {
        fprintf(stderr, "Error al reservar memoria\n");
        free(A);
        free(B);
        free(C);
        return 1;
    }

    init(A, B, N);

    m5_reset_stats(0, 0);
    gemm(A, B, C, N);
    m5_dump_stats(0, 0);

    int resultado = check(A, B, C, N);

    free(A);
    free(B);
    free(C);

    return resultado;
}