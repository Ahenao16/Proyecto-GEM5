# Proyecto GEM5

Este proyecto permite ejecutar simulaciones de gem5 utilizando una imagen Docker que contiene los binarios previamente compilados. De esta manera, no se requiere compilar gem5 ni instalar sus dependencias manualmente.

## 1. Requisitos

- Git
- Docker

## 2. Obtener el proyecto

Clonar el repositorio y entrar en la carpeta:
```bash
git clone git@github.com:Ahenao16/Proyecto-GEM5.git
cd Proyecto-GEM5
```

## 3. Descargar la imagen Docker

La imagen pública contiene gem5 ya compilado y el compilador cruzado para ARM64.

Descargarla con:

```bash
docker pull ghcr.io/ahenao16/proyecto-gem5:latest
```

No es necesario ejecutar `docker build`, porque la imagen ya está publicada.

Si Docker muestra un error de permisos al acceder a su servicio, probar los comandos con `sudo`.

## 4. Preparar el programa de prueba

El código fuente del programa de prueba se encuentra en `src/hola.c`.

Para ejecutarlo en gem5, debe compilarse para ARM64. Se puede hacer dentro del contenedor utilizando el compilador incluido en la imagen.

### Iniciar el contenedor

Desde la carpeta del proyecto:

```bash
docker run --rm -it \
  -v "$PWD:/proyecto-gem5" \
  -w /proyecto-gem5 \
  ghcr.io/ahenao16/proyecto-gem5:latest \
  bash
```

El contenedor tendrá acceso al proyecto en `/proyecto-gem5` y a los binarios de gem5 en `/gem5`.

### Compilar el programa

Dentro del contenedor, ejecutar:

```bash
aarch64-linux-gnu-gcc -static \
  /proyecto-gem5/src/hola.c \
  -o /proyecto-gem5/src/hola
```

Comprobar el ejecutable:

```bash
file /proyecto-gem5/src/hola
```

La salida debe indicar que es un ejecutable ARM/AArch64.

## 5. Ejecutar una simulación con MESI

Dentro del contenedor, ejecutar:

```bash
/gem5/build/ARM_MESI/gem5.opt \
  /gem5/configs/deprecated/example/se.py \
  --ruby \
  --cmd=/proyecto-gem5/src/hola
```

Si la simulación termina correctamente, debería aparecer:

```text
Hola desde gem5!
```

El argumento `--ruby` habilita el sistema de coherencia Ruby.

## 6. Ejecutar una simulación con MOESI CMP Directory

Para utilizar el protocolo MOESI CMP Directory, ejecutar:

```bash
/gem5/gem5_build/ARM_MOESI_CMP_directory/gem5.opt \
  /gem5/configs/deprecated/example/se.py \
  --ruby \
  --cmd=/proyecto-gem5/src/hola
```

Esta ejecución utiliza el binario de gem5 compilado para MOESI CMP Directory.

**Nota:** las rutas de los binarios dependen de cómo se construyó la imagen Docker. En esta imagen, MESI y MOESI utilizan las rutas indicadas arriba.

## 7. Modificar los parámetros de simulación

Se pueden modificar el número de núcleos, el ancho de emisión (`issueWidth`) y la longitud de los vectores SVE (`VL`) mediante los argumentos de gem5.

Por ejemplo, para ejecutar con dos núcleos, `issueWidth = 4` y `VL = 512` bits:

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

La correspondencia entre `VL` y `sve_vl_se` es:

| Longitud SVE | Valor de `sve_vl_se` |
|---:|---:|
| 128 bits | 1 |
| 256 bits | 2 |
| 512 bits | 4 |
| 1024 bits | 8 |

Al cambiar el número de núcleos, hay que ajustar las asignaciones de `issueWidth` y SVE para que correspondan a los núcleos configurados.

## 8. Consultar los resultados

gem5 genera estadísticas y archivos de configuración durante la simulación.

Por defecto, los resultados se guardan en el directorio de salida de gem5. Si se ejecuta desde `/proyecto-gem5`, pueden consultarse en:

```bash
ls m5out/
```

Para consultar estadísticas relevantes:

```bash
grep -E "simSeconds|simTicks|simInsts" m5out/stats.txt
```

Los archivos `stats.txt` y `config.ini` permiten consultar métricas y verificar la configuración utilizada.

## 9. Salir del contenedor

Para terminar la sesión:

```bash
exit
```

El código fuente permanece en el equipo local. La imagen descargada contiene gem5 y el compilador cruzado, por lo que no es necesario reconstruir gem5 para cada simulación.
