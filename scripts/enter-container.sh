#!/bin/bash
set -e

# =========================================================
# CONFIGURACIÓN
# =========================================================

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="proyecto-gem5"

# Detectar la carpeta del usuario incluso si se ejecuta con sudo.
if [[ -n "${GEM5_DIR:-}" ]]; then
    :
elif [[ -n "${SUDO_USER:-}" ]]; then
    USER_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
    GEM5_DIR="$USER_HOME/proyectos/gem5"
else
    GEM5_DIR="$HOME/proyectos/gem5"
fi

# =========================================================
# VERIFICACIONES
# =========================================================

if [[ ! -d "$GEM5_DIR" ]]; then
    echo "Error: no se encontró la carpeta de gem5."
    echo "Ruta buscada: $GEM5_DIR"
    echo
    echo "Puedes indicar su ubicación así:"
    echo "GEM5_DIR=/ruta/a/gem5 ./scripts/enter-container.sh"
    exit 1
fi

if [[ ! -x "$GEM5_DIR/build/ARM_MESI/gem5.opt" ]]; then
    echo "Error: no se encontró el ejecutable ARM_MESI/gem5.opt."
    echo "Comprueba que gem5 esté compilado."
    exit 1
fi

if [[ ! -x "$GEM5_DIR/build/ARM_MOESI_hammer/gem5.opt" ]]; then
    echo "Error: no se encontró el ejecutable ARM_MOESI_hammer/gem5.opt."
    echo "Comprueba que gem5 esté compilado."
    exit 1
fi

# =========================================================
# DOCKER
# =========================================================

if docker info >/dev/null 2>&1; then
    DOCKER=(docker)
elif command -v sudo >/dev/null 2>&1 && sudo docker info >/dev/null 2>&1; then
    DOCKER=(sudo docker)
else
    echo "Error: no se puede acceder a Docker."
    echo "Comprueba que Docker esté instalado y en ejecución."
    exit 1
fi

echo "Proyecto: $PROJECT_DIR"
echo "gem5:     $GEM5_DIR"
echo "Imagen:   $IMAGE"
echo
echo "Iniciando el contenedor..."

"${DOCKER[@]}" run --rm -it \
    -v "$GEM5_DIR:/gem5" \
    -v "$PROJECT_DIR:/proyecto-gem5" \
    -w /proyecto-gem5 \
    "$IMAGE" bash
