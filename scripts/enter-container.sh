#!/bin/bash
set -e

# =========================================================
# CONFIGURACIÓN
# =========================================================

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="ghcr.io/ahenao16/proyecto-gem5:latest"

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

# =========================================================
# DESCARGAR IMAGEN
# =========================================================

echo "Proyecto: $PROJECT_DIR"
echo "Imagen:   $IMAGE"
echo

"${DOCKER[@]}" pull "$IMAGE"

# =========================================================
# INICIAR CONTENEDOR
# =========================================================

echo
echo "Iniciando el contenedor..."

"${DOCKER[@]}" run --rm -it \
    -v "$PROJECT_DIR:/proyecto-gem5" \
    -w /proyecto-gem5 \
    "$IMAGE" bash
