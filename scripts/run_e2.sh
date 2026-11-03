#!/usr/bin/env bash
# run_e2.sh - E2: barrido del ancho del pipeline y tamaño del ROB en O3.
#
# Ejecutar DENTRO del contenedor, desde la raíz del repositorio:
#     ./scripts/run_e2.sh
#
# Variables opcionales:
#     SIZES="64 128"          tamaños N
#     WIDTHS="1 2 4 8"        ancho del pipeline
#     ROBS="32 64 192"        entradas del ROB
#     PROTOS="mesi moesi"     protocolos Ruby
#     JOBS=2                  corridas en paralelo
#     FORCE=1                 repetir aunque la corrida ya exista
#
# Prueba rápida:
#     SIZES=16 PROTOS=mesi JOBS=2 ./scripts/run_e2.sh
#
# Salida:
#     results/e2/<protocolo>_n<N>_w<W>_rob<R>/
#     results/e2.csv

set -u
cd "$(dirname "${BASH_SOURCE[0]}")/.."

for v in GEM5_MESI GEM5_MOESI GEM5_CONFIGS CC_ARM M5_INC M5_LIB; do
    if [[ -z "${!v:-}" ]]; then
        echo "Error: la variable $v no está definida. ¿Estás dentro del contenedor?" >&2
        exit 1
    fi
done

SIZES=${SIZES:-"64"}
WIDTHS=${WIDTHS:-"1 2 4 8"}
ROBS=${ROBS:-"32 64 192"}
PROTOS=${PROTOS:-"mesi moesi"}
JOBS=${JOBS:-4}
FORCE=${FORCE:-0}

OUT=results/e2
SE="$GEM5_CONFIGS/deprecated/example/se.py"

# Validar protocolos
proto_bin() {
    case "$1" in
        mesi)  echo "$GEM5_MESI" ;;
        moesi) echo "$GEM5_MOESI" ;;
        *)     echo "Protocolo desconocido: $1" >&2; return 1 ;;
    esac
}

for p in $PROTOS; do
    proto_bin "$p" >/dev/null || exit 1
done

# Validar parámetros
for w in $WIDTHS; do
    if ! [[ "$w" =~ ^[0-9]+$ ]] || (( w < 1 )); then
        echo "Ancho inválido: $w" >&2
        exit 1
    fi
done

for r in $ROBS; do
    if ! [[ "$r" =~ ^[0-9]+$ ]] || (( r < 1 )); then
        echo "Tamaño ROB inválido: $r" >&2
        exit 1
    fi
done

# Compilar GEMM escalar
echo "Compilando src/gemm_escalar.c ..."

"$CC_ARM" -O2 -fno-tree-vectorize -static \
    src/gemm_escalar.c -o gemm_escalar \
    -I"$M5_INC" -L"$M5_LIB" -lm5 \
    || { echo "Error de compilación" >&2; exit 1; }

mkdir -p "$OUT"

STATUS="$OUT/.status"
: > "$STATUS"

run_one() {
    local proto=$1
    local n=$2
    local width=$3
    local rob=$4
    local d="$OUT/${proto}_n${n}_w${width}_rob${rob}"

    # Evitar repetir corridas completadas
    if [[ $FORCE != 1 && -f "$d/run.log" ]] \
        && grep -q "Exiting @ tick" "$d/run.log" \
        && grep -q "Resultado correcto" "$d/run.log"; then

        echo "[ya existe] $d"
        echo "ok $d" >> "$STATUS"
        return 0
    fi

    mkdir -p "$d"

    echo "[corriendo] $d"

    "$(proto_bin "$proto")" -d "$d" "$SE" \
        --ruby \
        --cpu-type=O3CPU \
        -P "system.cpu[0].fetchWidth=$width" \
        -P "system.cpu[0].decodeWidth=$width" \
        -P "system.cpu[0].renameWidth=$width" \
        -P "system.cpu[0].issueWidth=$width" \
        -P "system.cpu[0].commitWidth=$width" \
        -P "system.cpu[0].numROBEntries=$rob" \
        -c gemm_escalar \
        -o "$n" \
        > "$d/run.log" 2>&1

    if grep -q "Resultado correcto" "$d/run.log" \
        && grep -q "Exiting @ tick" "$d/run.log"; then

        echo "[ok]        $d"
        echo "ok $d" >> "$STATUS"
    else
        echo "[FALLO]     $d (ver $d/run.log)"
        echo "fallo $d" >> "$STATUS"
    fi
}

# Barrido de configuraciones
for n in $SIZES; do
    for proto in $PROTOS; do
        for width in $WIDTHS; do
            for rob in $ROBS; do

                run_one "$proto" "$n" "$width" "$rob" &

                while (( $(jobs -rp | wc -l) >= JOBS )); do
                    wait -n || true
                done

            done
        done
    done
done

wait

# Generar CSV
echo
echo "Generando resumen..."

python3 scripts/parse_stats.py "$OUT" > results/e2.csv || exit 1

python3 scripts/parse_stats.py "$OUT" --table

# Verificar resultados
nfail=$(grep -c '^fallo' "$STATUS" || true)

echo

if (( nfail > 0 )); then
    echo "$nfail corrida(s) fallaron:"
    grep '^fallo' "$STATUS"
    exit 1
fi

echo "E2 completo: $(grep -c '^ok' "$STATUS") corridas."
echo "Resumen disponible en results/e2.csv"