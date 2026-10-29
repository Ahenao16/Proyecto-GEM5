# Proyecto GEM5

Este proyecto permite ejecutar simulaciones de gem5 mediante una imagen Docker que contiene los binarios previamente compilados. De esta manera, no es necesario compilar gem5 ni instalar manualmente sus dependencias en el equipo local.

## 1. Requisitos

- Git
- Docker

## 2. Obtener el proyecto

El repositorio se clona y se accede al directorio del proyecto mediante los siguientes comandos:

```bash
git clone git@github.com:Ahenao16/Proyecto-GEM5.git
cd Proyecto-GEM5
```

## 3. Descargar la imagen Docker

La imagen pública contiene gem5 compilado para ARM y el compilador cruzado para ARM64.

La imagen se descarga mediante:

```bash
docker pull ghcr.io/ahenao16/proyecto-gem5:latest
```

No es necesario ejecutar `docker build`, ya que la imagen se encuentra publicada.

Si Docker muestra un error de permisos al acceder a su servicio, los comandos correspondientes pueden ejecutarse con `sudo`.

## 4. Iniciar el contenedor

Desde el directorio del proyecto, el contenedor se inicia mediante el siguiente script:

```bash
chmod +x scripts/enter-container.sh
./scripts/enter-container.sh
```

El script descarga la imagen publicada e inicia el contenedor. Dentro de este, el proyecto está disponible en `/proyecto-gem5` y los binarios de gem5 en `/gem5`.

También es posible iniciar el contenedor manualmente:

```bash
docker run --rm -it \
  -v "$PWD:/proyecto-gem5" \
  -w /proyecto-gem5 \
  ghcr.io/ahenao16/proyecto-gem5:latest \
  bash
```

## 5. Preparar el programa de prueba

El código fuente del programa de prueba se encuentra en `src/hola.c`. Para ejecutarlo en gem5, debe compilarse para la arquitectura ARM64.

La compilación se realiza dentro del contenedor mediante:

```bash
aarch64-linux-gnu-gcc -static \
  /proyecto-gem5/src/hola.c \
  -o /proyecto-gem5/src/hola
```

El ejecutable generado puede verificarse con:

```bash
file /proyecto-gem5/src/hola
```

La salida debe indicar que se trata de un ejecutable ARM/AArch64.

## 6. Ejecutar una simulación con MESI

La simulación con el protocolo de coherencia MESI se ejecuta mediante:

```bash
/gem5/build/ARM_MESI/gem5.opt \
  /gem5/configs/deprecated/example/se.py \
  --ruby \
  --cpu-type=O3_ARM_v7a_3 \
  --cmd=/proyecto-gem5/src/hola
```

Si la simulación termina correctamente, el programa debe mostrar el siguiente mensaje:

```text
Hola desde gem5!
```

El argumento `--ruby` habilita el sistema de coherencia Ruby.

## 7. Ejecutar una simulación con MOESI CMP Directory

La simulación con el protocolo MOESI CMP Directory se ejecuta mediante:

```bash
/gem5/gem5_build/ARM_MOESI_CMP_directory/gem5.opt \
  /gem5/configs/deprecated/example/se.py \
  --ruby \
  --cpu-type=O3_ARM_v7a_3 \
  --cmd=/proyecto-gem5/src/hola
```

Esta ejecución utiliza el binario de gem5 compilado para MOESI CMP Directory.

## 8. Modificar los parámetros de simulación

Los parámetros de simulación pueden modificarse mediante los argumentos de gem5. Entre ellos se encuentran el número de núcleos, el ancho de emisión (`issueWidth`) y la longitud de los vectores SVE.

El siguiente ejemplo configura dos núcleos, un ancho de emisión de 4 y una longitud SVE de 512 bits:

```bash
/gem5/build/ARM_MESI/gem5.opt \
  /gem5/configs/deprecated/example/se.py \
  --ruby \
  --num-cpus=2 \
  --cpu-type=O3_ARM_v7a_3 \
  -P 'system.cpu[0].issueWidth = 4' \
  -P 'system.cpu[1].issueWidth = 4' \
  -P 'system.cpu[0].isa[0].sve_vl_se = 4' \
  -P 'system.cpu[1].isa[0].sve_vl_se = 4' \
  --cmd=/proyecto-gem5/src/hola
```

### Longitud de los vectores SVE

| Longitud SVE | Valor de `sve_vl_se` |
|---:|---:|
| 128 bits | 1 |
| 256 bits | 2 |
| 512 bits | 4 |
| 1024 bits | 8 |

Al modificar el número de núcleos, las asignaciones de `issueWidth` y SVE deben ajustarse para que correspondan a los núcleos configurados.

Estos parámetros permiten modificar la configuración de la simulación. Para evaluar el rendimiento de SVE, se requiere un programa que utilice instrucciones SVE; el programa `hola.c` se utiliza únicamente para verificar el funcionamiento básico.

## 9. Consultar los resultados

Por defecto, gem5 genera los archivos de salida en el directorio `m5out`, relativo al directorio de trabajo desde el que se ejecuta la simulación.

Si la simulación se ejecuta desde `/proyecto-gem5`, los resultados pueden consultarse mediante:

```bash
ls m5out/
```

Para consultar algunas estadísticas relevantes:

```bash
grep -E "simSeconds|simTicks|simInsts" m5out/stats.txt
```

Los archivos `stats.txt` y `config.ini` permiten consultar las estadísticas generadas y verificar la configuración utilizada durante la simulación.

## 10. Finalizar la sesión

La sesión del contenedor se finaliza mediante:

```bash
exit
```

El código fuente permanece en el equipo local. La imagen Docker contiene gem5 y el compilador cruzado, por lo que no es necesario reconstruir gem5 para cada simulación.

**Nota:** el script `se.py` está marcado como obsoleto en gem5 y podría eliminarse en futuras versiones. Se mantiene en este proyecto porque corresponde a la configuración utilizada actualmente.
