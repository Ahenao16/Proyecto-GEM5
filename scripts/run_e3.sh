#!/usr/bin/env bash
# E3: Comparacion GEMM escalar vs SVE
# Ejecutar desde cualquier directorio dentro del contenedor.

set -u
cd "$(dirname "${BASH_SOURCE[0]}")/.."

for v in GEM5_MESI GEM5_CONFIGS CC_ARM M5_INC M5_LIB; do
    if [[ -z "${!v:-}" ]]; then
        echo "Error: variable $v no definida."
        exit 1
    fi
done

SIZES=${SIZES:-"64 128"}
VLS=${VLS:-"128 256 512 1024"}
FORCE=${FORCE:-0}

OUT=results/e3
SE="$GEM5_CONFIGS/deprecated/example/se.py"
STATUS="$OUT/.status"

mkdir -p "$OUT"
: > "$STATUS"

# Validar tamaños y longitudes vectoriales
for n in $SIZES; do
    if ! [[ "$n" =~ ^[0-9]+$ ]] || (( n < 1 )); then
        echo "N invalido: $n"
        exit 1
    fi
done

for vl in $VLS; do
    if ! [[ "$vl" =~ ^(128|256|512|1024)$ ]]; then
        echo "VL invalido: $vl"
        exit 1
    fi
done

# Compilar version escalar sin autovectorizacion.
# Se usa O3 para que la comparacion con SVE tenga
# el mismo nivel de optimizacion.
echo "Compilando GEMM escalar..."

"$CC_ARM" -O3 -fno-tree-vectorize -static \
    src/gemm_escalar.c -o gemm_escalar \
    -I"$M5_INC" -L"$M5_LIB" -lm5 \
    || { echo "Error compilando GEMM escalar."; exit 1; }

# Compilar version SVE y guardar reporte del compilador.
echo "Compilando GEMM SVE..."

"$CC_ARM" -O3 -march=armv8-a+sve -fopt-info-vec \
    -static src/gemm_sve.c -o gemm_sve \
    -I"$M5_INC" -L"$M5_LIB" -lm5 \
    > "$OUT/compilacion_sve.log" 2>&1 \
    || { echo "Error compilando GEMM SVE."; exit 1; }

echo "Compilacion terminada."
echo "Reporte: $OUT/compilacion_sve.log"

# Ejecutar una configuracion.
run_one() {
    local n=$1
    local tipo=$2
    local vl=${3:-0}
    local tag
    local d

    if [[ "$tipo" == "scalar" ]]; then
        tag="scalar"
    else
        tag="sve_vl${vl}"
    fi

    d="$OUT/mesi_n${n}_${tag}"

    # No repetir ejecuciones completadas, salvo FORCE=1.
    if [[ "$FORCE" != 1 && -f "$d/run.log" && -f "$d/stats.txt" ]] \
        && grep -q "Resultado correcto" "$d/run.log" \
        && grep -q "Exiting @ tick" "$d/run.log"; then
        echo "[ya existe] $d"
        echo "ok $d" >> "$STATUS"
        return 0
    fi

    mkdir -p "$d"
    echo "[corriendo] N=$n, tipo=$tipo, VL=$vl"

    if [[ "$tipo" == "scalar" ]]; then
        if "$GEM5_MESI" -d "$d" "$SE" \
            --ruby \
            --cpu-type=O3CPU \
            -c gemm_escalar \
            -o "$n" \
            > "$d/run.log" 2>&1; then
            :
        else
            echo "[FALLO] $d: gem5 devolvio error"
            echo "fallo $d" >> "$STATUS"
            return 1
        fi
    else
        local vl_se=$((vl / 128))

        if "$GEM5_MESI" -d "$d" "$SE" \
            --ruby \
            --cpu-type=O3CPU \
            --param "system.cpu[:].isa[:].sve_vl_se=$vl_se" \
            -c gemm_sve \
            -o "$n" \
            > "$d/run.log" 2>&1; then
            :
        else
            echo "[FALLO] $d: gem5 devolvio error"
            echo "fallo $d" >> "$STATUS"
            return 1
        fi
    fi

    if grep -q "Resultado correcto" "$d/run.log" \
        && grep -q "Exiting @ tick" "$d/run.log" \
        && [[ -f "$d/stats.txt" ]]; then
        echo "[OK] $d"
        echo "ok $d" >> "$STATUS"
    else
        echo "[FALLO] $d (revisar run.log)"
        echo "fallo $d" >> "$STATUS"
        return 1
    fi
}

# Ejecutar escalar y luego las cuatro longitudes SVE.
for n in $SIZES; do
    run_one "$n" scalar || true

    for vl in $VLS; do
        run_one "$n" sve "$vl" || true
    done
done

# Comprobar si hubo fallos.
nfail=$(grep -c '^fallo' "$STATUS" || true)

if (( nfail > 0 )); then
    echo
    echo "$nfail ejecucion(es) fallaron:"
    grep '^fallo' "$STATUS"
    echo "Revisar los run.log correspondientes."
    exit 1
fi

# Extraer las metricas de la ROI.
echo
echo "Generando CSV..."

python3 scripts/parse_stats.py "$OUT" > "$OUT.csv" || exit 1
python3 scripts/parse_stats.py "$OUT" --table

# Calcular speedup e instrucciones relativas a la version escalar.
python3 - "$OUT.csv" "$OUT"_speedup.csv <<'PY'
import csv
import sys

source, destination = sys.argv[1], sys.argv[2]

with open(source, newline="") as f:
    rows = list(csv.DictReader(f))

results = []

for n in sorted({r["N"] for r in rows if r["N"]}, key=int):
    scalar = next(
        (r for r in rows if r["N"] == n and r["tag"] == "scalar"),
        None
    )

    if scalar is None:
        continue

    try:
        scalar_cycles = float(scalar["cycles"])
        scalar_insts = float(scalar["simInsts"])
    except (ValueError, TypeError):
        continue

    for r in rows:
        if r["N"] != n or not r["tag"].startswith("sve_vl"):
            continue

        try:
            sve_cycles = float(r["cycles"])
            sve_insts = float(r["simInsts"])
            vl = int(r["tag"].replace("sve_vl", ""))
        except (ValueError, TypeError):
            continue

        if sve_cycles <= 0 or sve_insts <= 0:
            continue

        results.append({
            "N": n,
            "VL_bits": vl,
            "scalar_instructions": int(scalar_insts),
            "sve_instructions": int(sve_insts),
            "scalar_cycles": int(scalar_cycles),
            "sve_cycles": int(sve_cycles),
            "speedup": scalar_cycles / sve_cycles,
            "instruction_reduction_percent":
                (1 - sve_insts / scalar_insts) * 100
        })

fields = [
    "N", "VL_bits",
    "scalar_instructions", "sve_instructions",
    "scalar_cycles", "sve_cycles",
    "speedup", "instruction_reduction_percent"
]

with open(destination, "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=fields)
    writer.writeheader()
    writer.writerows(results)

print("\nComparacion escalar vs SVE:")
for r in results:
    print(
        f"N={r['N']:>3} | VL={r['VL_bits']:>4} bits | "
        f"Speedup={r['speedup']:.3f}x | "
        f"Reduccion instrucciones="
        f"{r['instruction_reduction_percent']:.2f}%"
    )

if not results:
    print("AVISO: no se pudieron calcular comparaciones.")
PY

echo
echo "E3 completo."
echo "Metricas: $OUT.csv"
echo "Speedup:  ${OUT}_speedup.csv"
EOF