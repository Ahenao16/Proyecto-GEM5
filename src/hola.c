#include <stdio.h>
#include <gem5/m5ops.h>

int main() {
    printf("Hola mundo desde ARM en gem5!\n");

    // Ejemplo de uso de m5ops (opcional)
    m5_dump_stats(0, 0);

    return 0;
}