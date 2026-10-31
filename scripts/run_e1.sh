#!/usr/bin/env bash
# run_e1.sh - E1: línea base de un núcleo (GEMM escalar) con TimingSimple, Minor y O3.
#
# Ejecutar DENTRO del contenedor, desde la raíz del repositorio:
#     ./scripts/run_e1.sh
#
# Variables opcionales (todas con valor por defecto):
#     SIZES="64 128"          tamaños N
#     CPUS="timing minor o3"  modelos de CPU
#     PROTOS="mesi moesi"     protocolos de coherencia (Ruby)
#     JOBS=2                  corridas en paralelo
#     FORCE=1                 repetir aunque la corrida ya exista
# Prueba rápida:  SIZES=16 ./scripts/run_e1.sh
#
# Salida: results/e1/<protocolo>_n<N>_<cpu>/  y el resumen results/e1.csv
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/.."

for v in GEM5_MESI GEM5_MOESI GEM5_CONFIGS CC_ARM M5_INC M5_LIB; do
    if [[ -z "${!v:-}" ]]; then
        echo "Error: la variable $v no está definida. ¿Estás dentro del contenedor?" >&2
        exit 1
    fi
done

SIZES=${SIZES:-"64 128"}
CPUS=${CPUS:-"timing minor o3"}
PROTOS=${PROTOS:-"mesi moesi"}
JOBS=${JOBS:-2}
FORCE=${FORCE:-0}
OUT=results/e1
SE="$GEM5_CONFIGS/deprecated/example/se.py"

cpu_type() {
    case "$1" in
        timing) echo TimingSimpleCPU ;;
        minor)  echo MinorCPU ;;
        o3)     echo O3CPU ;;
        *)      echo "CPU desconocida: $1" >&2; return 1 ;;
    esac
}
proto_bin() {
    case "$1" in
        mesi)  echo "$GEM5_MESI" ;;
        moesi) echo "$GEM5_MOESI" ;;
        *)     echo "Protocolo desconocido: $1" >&2; return 1 ;;
    esac
}

# Validar las listas antes de empezar
for c in $CPUS;   do cpu_type "$c"   >/dev/null || exit 1; done
for p in $PROTOS; do proto_bin "$p"  >/dev/null || exit 1; done

# Compilar el benchmark (escalar de verdad: sin autovectorización)
echo "Compilando src/gemm_escalar.c ..."
"$CC_ARM" -O2 -fno-tree-vectorize -static src/gemm_escalar.c -o gemm_escalar \
    -I"$M5_INC" -L"$M5_LIB" -lm5 || { echo "Error de compilación" >&2; exit 1; }

mkdir -p "$OUT"
STATUS="$OUT/.status"
: > "$STATUS"

run_one() {
    local cpu=$1 proto=$2 n=$3
    local d="$OUT/${proto}_n${n}_${cpu}"
    if [[ $FORCE != 1 && -f "$d/run.log" ]] \
        && grep -q "Exiting @ tick" "$d/run.log" \
        && grep -q "Resultado correcto" "$d/run.log"; then
        echo "[ya existe] $d"
        echo "ok $d" >> "$STATUS"
        return 0
    fi
    mkdir -p "$d"
    echo "[corriendo] $d"
    "$(proto_bin "$proto")" -d "$d" "$SE" --ruby --cpu-type="$(cpu_type "$cpu")" \
        -c gemm_escalar -o "$n" > "$d/run.log" 2>&1
    if grep -q "Resultado correcto" "$d/run.log" && grep -q "Exiting @ tick" "$d/run.log"; then
        echo "[ok]        $d"
        echo "ok $d" >> "$STATUS"
    else
        echo "[FALLO]     $d  (ver $d/run.log)"
        echo "fallo $d" >> "$STATUS"
    fi
}

for n in $SIZES; do
  for cpu in $CPUS; do
    for proto in $PROTOS; do
        run_one "$cpu" "$proto" "$n" &
        while (( $(jobs -rp | wc -l) >= JOBS )); do wait -n || true; done
    done
  done
done
wait

echo
python3 scripts/parse_stats.py "$OUT" > results/e1.csv || exit 1
python3 scripts/parse_stats.py "$OUT" --table

nfail=$(grep -c '^fallo' "$STATUS" || true)
echo
if (( nfail > 0 )); then
    echo "$nfail corrida(s) fallaron:"; grep '^fallo' "$STATUS"
    exit 1
fi
echo "E1 completo: $(grep -c '^ok' "$STATUS") corridas, resumen en results/e1.csv"