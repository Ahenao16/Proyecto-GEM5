# Proyecto gem5: coherencia de caché (MESI vs MOESI) en ARM

Este repositorio incluye una imagen de Docker con gem5 ya compilado, de modo que quien lo use **no necesita compilar gem5** (la compilación completa tarda más de una hora y consume muchos GB de RAM).

## Qué contiene la imagen

| Elemento | Detalle |
|---|---|
| gem5 | v24.0.0.0, binarios `gem5.opt` |
| Build 1 | ARM + `MESI_Two_Level` |
| Build 2 | ARM + `MOESI_CMP_directory` |
| Compilador | `aarch64-linux-gnu-gcc` / `g++` (cross-compiler) |
| m5ops | headers y `libm5.a` para arm64 |
| Scripts de gem5 | `configs/` oficiales (incluye `deprecated/example/se.py`) |

Variables de entorno disponibles dentro del contenedor:

| Variable | Valor |
|---|---|
| `$GEM5_MESI` | binario ARM con MESI_Two_Level |
| `$GEM5_MOESI` | binario ARM con MOESI_CMP_directory |
| `$GEM5_CONFIGS` | scripts de configuración de gem5 |
| `$CC_ARM` | cross-compiler de C para aarch64 |
| `$M5_INC` / `$M5_LIB` | headers y librería de m5ops |

## Requisitos

- Linux con Docker instalado (`docker --version` debe funcionar).
- Unos 3 GB libres de disco para la imagen.
- Conexión a internet solo para el primer `pull`.
- Git, para clonar este repositorio.

## Paso a paso

### 1. Clonar el repositorio

```bash
git clone https://github.com/ahenao16/NOMBRE_DEL_REPO.git
cd NOMBRE_DEL_REPO
```

### 2. Descargar la imagen

```bash
docker pull ghcr.io/ahenao16/gem5-coherencia:1.0
```

Si el usuario no pertenece al grupo `docker`, debe anteponer `sudo` a todos los comandos de `docker`.

### 3. Entrar al contenedor

Desde la carpeta del proyecto:

```bash
docker run -it --rm --user $(id -u):$(id -g) \
    -v $(pwd):/gem5_container ghcr.io/ahenao16/gem5-coherencia:1.0
```

El aviso `I have no name!` que aparece al entrar es normal e inofensivo.

### 4. Comprobar que la imagen está sana

Dentro del contenedor:

```bash
ldd $GEM5_MESI | grep "not found"
ls $M5_INC/gem5/m5ops.h $M5_LIB/libm5.a
```

El primer comando **no debe imprimir nada**. El segundo debe mostrar los dos archivos.

### 5. Compilar un programa para ARM

```bash
$CC_ARM -O2 -static src/hola.c -o hola -I$M5_INC -L$M5_LIB -lm5
file hola
```

`file` debe indicar `ARM aarch64`. Se usa `-static` porque en modo SE el simulador no dispone de librerías dinámicas del guest.

Para C++ se usa `aarch64-linux-gnu-g++` en lugar de `$CC_ARM`.

> El binario resultante es para ARM y **solo se ejecuta dentro de gem5**, no directamente en el contenedor.

### 6. Simular con cada protocolo

```bash
mkdir -p results

$GEM5_MESI -d results/hola_mesi $GEM5_CONFIGS/deprecated/example/se.py \
    --ruby --num-cpus=2 --cpu-type=TimingSimpleCPU -c hola

$GEM5_MOESI -d results/hola_moesi $GEM5_CONFIGS/deprecated/example/se.py \
    --ruby --num-cpus=2 --cpu-type=TimingSimpleCPU -c hola
```

Cada ejecución debe mostrar la salida del programa y terminar con un mensaje del tipo
`Exiting @ tick ... because exiting with last active thread context`.

`se.py` muestra un aviso de que está deprecado. Es normal en gem5 v24.0 y no afecta al resultado.

### 7. Revisar los resultados

```bash
grep -E "simSeconds|simTicks|simInsts" results/hola_mesi/stats.txt
grep -E "simSeconds|simTicks|simInsts" results/hola_moesi/stats.txt
```

Como la carpeta del proyecto está montada, los resultados quedan en `results/` del equipo anfitrión, a nombre del usuario. Si el programa usa `m5_reset_stats` y `m5_dump_stats`, `stats.txt` contendrá un bloque por cada volcado.

Para salir del contenedor: `exit`.

## Estructura del repositorio

```
.
├── Dockerfile        # cómo se construyó la imagen
├── src/              # programas en C (hola.c, gemm_escalar.c, ...)
├── scripts/          # scripts auxiliares
├── results/          # resultados (solo se versionan los .txt)
├── report/           # informe
└── README.md
```

## Reconstruir la imagen (solo si hace falta)

> **Atención: este paso NO es necesario para usar el proyecto.**
> La imagen ya está construida y publicada; con el `docker pull` del paso 2 basta.
> Solo debe reconstruirse si se quiere **modificar la propia imagen** (otra versión de gem5, otro protocolo, otra ISA o paquetes adicionales).

En ese caso se necesitan unos 40 GB de disco libres y 16 GB de RAM o más:

```bash
docker build --build-arg JOBS=8 -t gem5-coherencia:1.0 .
```

La compilación tarda entre 2 y 3 horas.
