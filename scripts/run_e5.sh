set -u
cd "$(dirname "${BASH_SOURCE[0]}")/.."

for v in GEM5_MESI GEM5_MOESI GEM5_CONFIGS CC_ARM M5_INC M5_LIB; do
    if [[ -z "${!v:-}" ]]; then
        echo "Error: la variable $v no está definida. ¿Estás dentro del contenedor?" >&2
        exit 1
    fi
done

CORES=${CORES:-"2 4 8"}
PROTOS=${PROTOS:-"mesi moesi"}
WORKLOADS=${WORKLOADS:-"fs_nopad fs_pad gemm"}
CPU=${CPU:-timing}
ITERS=${ITERS:-50000}
GEMM_N=${GEMM_N:-128}
JOBS=${JOBS:-2}
FORCE=${FORCE:-0}
OUT=results/e5
SE="$GEM5_CONFIGS/deprecated/example/se.py"

PARAMS="cpu=$CPU iters=$ITERS gemm_n=$GEMM_N"

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
# Binario y argumentos (-o) de cada carga: "<binario>|<args>"
workload_cmd() {   # $1=carga $2=núcleos
    case "$1" in
        fs_nopad) echo "false_sharing|$2 nopad $ITERS" ;;
        fs_pad)   echo "false_sharing|$2 pad $ITERS" ;;
        gemm)     echo "gemm_omp|$GEMM_N $2" ;;
        *)        echo "Carga desconocida: $1" >&2; return 1 ;;
    esac
}

# Validar las listas antes de empezar
cpu_type "$CPU" >/dev/null || exit 1
for p in $PROTOS;    do proto_bin "$p"         >/dev/null || exit 1; done
for w in $WORKLOADS; do workload_cmd "$w" 2    >/dev/null || exit 1; done
for c in $CORES; do
    [[ $c =~ ^[0-9]+$ ]] && (( c >= 1 )) || { echo "Núcleos inválidos: $c" >&2; exit 1; }
done

# Compilar los benchmarks (estáticos, AArch64)
echo "Compilando src/false_sharing.c ..."
"$CC_ARM" -O2 -static -pthread src/false_sharing.c -o false_sharing \
    -I"$M5_INC" -L"$M5_LIB" -lm5 || { echo "Error de compilación (false_sharing)" >&2; exit 1; }

if [[ " $WORKLOADS " == *" gemm "* ]]; then
    echo "Compilando src/gemm_omp.c ..."
    # OpenMP si está disponible; si no, se asume que usa pthreads.
    "$CC_ARM" -O2 -fno-tree-vectorize -static -fopenmp -pthread src/gemm_omp.c -o gemm_omp \
        -I"$M5_INC" -L"$M5_LIB" -lm5 -lm 2>/dev/null \
    || "$CC_ARM" -O2 -fno-tree-vectorize -static -pthread src/gemm_omp.c -o gemm_omp \
        -I"$M5_INC" -L"$M5_LIB" -lm5 -lm \
    || { echo "Error de compilación (gemm_omp)" >&2; exit 1; }
fi

mkdir -p "$OUT"
STATUS="$OUT/.status"
: > "$STATUS"

run_one() {
    local proto=$1 w=$2 n=$3
    local d="$OUT/${proto}_${w}_n${n}"
    # Reutilizar solo si terminó bien Y se hizo con los mismos parámetros
    if [[ $FORCE != 1 && -f "$d/run.log" ]] \
        && grep -q "Exiting @ tick" "$d/run.log" \
        && grep -q "Resultado correcto" "$d/run.log" \
        && [[ "$(cat "$d/params.txt" 2>/dev/null)" == "$PARAMS" ]]; then
        echo "[ya existe] $d"
        echo "ok $d" >> "$STATUS"
        return 0
    fi
    local spec bin args
    spec=$(workload_cmd "$w" "$n")
    bin=${spec%%|*}
    args=${spec#*|}
    mkdir -p "$d"
    echo "[corriendo] $d   ($bin -o \"$args\")"
    "$(proto_bin "$proto")" -d "$d" "$SE" --ruby -n "$n" --cpu-type="$(cpu_type "$CPU")" \
        -c "$bin" -o "$args" > "$d/run.log" 2>&1
    if grep -q "Resultado correcto" "$d/run.log" && grep -q "Exiting @ tick" "$d/run.log"; then
        echo "$PARAMS" > "$d/params.txt"
        echo "[ok]        $d"
        echo "ok $d" >> "$STATUS"
    else
        echo "[FALLO]     $d  (ver $d/run.log)"
        echo "fallo $d" >> "$STATUS"
    fi
}

for n in $CORES; do
  for w in $WORKLOADS; do
    for proto in $PROTOS; do
        run_one "$proto" "$w" "$n" &
        while (( $(jobs -rp | wc -l) >= JOBS )); do wait -n || true; done
    done
  done
done
wait

echo
python3 scripts/parse_e5.py "$OUT" > results/e5.csv || exit 1
python3 scripts/parse_e5.py "$OUT" --table

nfail=$(grep -c '^fallo' "$STATUS" || true)
echo
if (( nfail > 0 )); then
    echo "$nfail corrida(s) fallaron:"; grep '^fallo' "$STATUS"
    exit 1
fi
echo "E5 completo: $(grep -c '^ok' "$STATUS") corridas, resumen en results/e5.csv"