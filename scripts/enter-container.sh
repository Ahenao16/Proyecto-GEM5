#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GEM5_DIR="${SUDO_USER:+$(getent passwd "$SUDO_USER" | cut -d: -f6)}/proyectos/gem5"
GEM5_DIR="${GEM5_DIR:-$HOME/proyectos/gem5}"
IMAGE="ghcr.io/gem5/ubuntu-24.04_all-dependencies:v26-0"

if [ ! -d "$GEM5_DIR" ]; then
    echo "Error: no se encontró gem5 en $GEM5_DIR"
    exit 1
fi

docker run --rm -it -v "${GEM5_DIR}:/gem5" -v "${PROJECT_DIR}:/proyecto-gem5" -w /proyecto-gem5 "${IMAGE}" bash
