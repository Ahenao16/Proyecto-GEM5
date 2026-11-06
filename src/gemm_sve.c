
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <math.h>

#include <arm_sve.h>
#include <gem5/m5ops.h>

/* =========================================================
 * GEMM VECTORIAL SVE
 * C = A x B
 * ========================================================= */

void gemm(const float *A, const float *B, float *C, int N) {

    // Número de elementos float que caben en el vector SVE
    const int VL = svcntw();

    //Averigua dinámicamente cuántos elementos de tipo float (32 bits) caben en un registro vectorial del procesador

    for (int i = 0; i < N; i++) {

        // Procesar la fila i de C por bloques vectoriales
        for (int j = 0; j < N; j += VL) {

            // Esta máscara indica qué carriles del vector están activos
            svbool_t pg = svwhilelt_b32((uint64_t)j, (uint64_t)N);
            //Sirve para ver con cuales carriles trabajar y cuales ignorar, ya que si N no es múltiplo de VL, los carriles sobrantes no deben ser procesados.
            // Acumulador vectorial
            svfloat32_t suma = svdup_f32(0.0f);

            for (int k = 0; k < N; k++) {

                // Valor escalar de A
                float a = A[i * N + k];

                // Replicar A en todos los carriles
                svfloat32_t va = svdup_f32(a);

                // Cargar elementos consecutivos de B
                svfloat32_t vb = svld1_f32(pg, &B[k * N + j]);

                // suma = suma + (A * B)
                suma = svmla_f32_m(pg, suma, va, vb); //Fused Multiply-Add
            }

            // Guardar resultados vectoriales en C
            svst1_f32(pg, &C[i * N + j], suma);
        }
    }
}

/* =========================================================
 * INICIALIZACIÓN DE MATRICES
 * ========================================================= */

void init(float *A, float *B, int N) {

    for (int i = 0; i < N * N; i++) {
        A[i] = 1.0 + i;
        B[i] = 2.0 + i;
    }
}

/* =========================================================
 * VERIFICACIÓN DE RESULTADOS
 * ========================================================= */

int check(const float *A, const float *B, const float *C, int N) {
    for (int i = 0; i < N; i++) {
        for (int j = 0; j < N; j++) {

            double esperado = 0.0;

            for (int k = 0; k < N; k++) {
                esperado += (double)A[i * N + k] *
                            (double)B[k * N + j];
            }

            double diferencia = fabs((double)C[i * N + j] - esperado);

            double tolerancia = 1e-5 *
                (fabs(esperado) > 1.0 ? fabs(esperado) : 1.0);

            if (diferencia > tolerancia) {
                printf("Error en C[%d][%d]: obtenido=%f, esperado=%f\n",
                       i, j, C[i * N + j], esperado);
                printf("Diferencia=%e, tolerancia=%e\n",
                       diferencia, tolerancia);
                return 1;
            }
        }
    }

    printf("Resultado correcto\n");
    return 0;
}

/* =========================================================
 * FUNCIÓN PRINCIPAL
 * ========================================================= */

int main(int argc, char *argv[]) {

    int N = 4;

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

    // Inicio de la región de interés
    m5_reset_stats(0, 0);

    gemm(A, B, C, N);

    // Final de la región de interés
    m5_dump_stats(0, 0);

    int resultado = check(A, B, C, N);

    free(A);
    free(B);
    free(C);

    return resultado;
}
