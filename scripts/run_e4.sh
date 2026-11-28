#!/usr/bin/env bash
# run_e4.sh - E4: multiprocesador. GEMM paralelo (pthreads, por filas) con
# 1, 2, 4 y 8 núcleos O3 de ancho 2. Calcula speedup, eficiencia y la
# fracción serial (Amdahl / Karp-Flatt).
#
# Ejecutar DENTRO del contenedor, desde la raíz del repositorio:
#     ./scripts/run_e4.sh
#
# Variables opcionales:
#     SIZES="64 128"      tamaños N
#     CORES="1 2 4 8"     núcleos simulados (= hilos)
#     PROTOS="mesi"       protocolos Ruby (mesi y/o moesi)
#     WIDTH=2             ancho del pipeline O3
#     L2BANKS=1           bancos de L2: 1 (L2 compartida de un banco, por defecto)
#                         o "cores" (tantos bancos como núcleos, para ver si
#                         la L2 es el cuello de botella)
#     JOBS=2              corridas en paralelo
#     FORCE=1             repetir aunque la corrida ya exista
#
# Prueba rápida:
#     SIZES=16 CORES="1 2" ./scripts/run_e4.sh
#
# Salida:
#     results/e4/<protocolo>_n<N>_c<núcleos>[_b<bancos L2>]/
#     results/e4.csv           métricas de cada corrida (ROI)
#     results/e4_speedup.csv   speedup, eficiencia y fracción serial

set -u
cd "$(dirname "${BASH_SOURCE[0]}")/.."

for v in GEM5_MESI GEM5_MOESI GEM5_CONFIGS CC_ARM M5_INC M5_LIB; do
    if [[ -z "${!v:-}" ]]; then
        echo "Error: la variable $v no está definida. ¿Estás dentro del contenedor?" >&2
        exit 1
    fi
done

SIZES=${SIZES:-"64 128"}
CORES=${CORES:-"1 2 4 8"}
PROTOS=${PROTOS:-"mesi"}
WIDTH=${WIDTH:-2}
L2BANKS=${L2BANKS:-1}
JOBS=${JOBS:-2}
FORCE=${FORCE:-0}

OUT=results/e4
SE="$GEM5_CONFIGS/deprecated/example/se.py"

proto_bin() {
    case "$1" in
        mesi)  echo "$GEM5_MESI" ;;
        moesi) echo "$GEM5_MOESI" ;;
        *)     echo "Protocolo desconocido: $1" >&2; return 1 ;;
    esac
}

for p in $PROTOS; do proto_bin "$p" >/dev/null || exit 1; done
for c in $CORES; do
    if ! [[ "$c" =~ ^[0-9]+$ ]] || (( c < 1 )); then
        echo "Número de núcleos inválido: $c" >&2; exit 1
    fi
done
if ! [[ "$L2BANKS" == cores || "$L2BANKS" =~ ^(1|2|4|8|16)$ ]]; then
    echo "L2BANKS inválido: $L2BANKS (use 1, 2, 4, 8, 16 o cores)" >&2; exit 1
fi
for n in $SIZES; do
    if ! [[ "$n" =~ ^[0-9]+$ ]] || (( n < 1 )); then
        echo "N inválido: $n" >&2; exit 1
    fi
done

# Compilar (mismas opciones que E1/E2: escalar, sin autovectorización)
echo "Compilando src/gemm_paralelo.c ..."
"$CC_ARM" -O2 -fno-tree-vectorize -static -pthread \
    src/gemm_paralelo.c -o gemm_paralelo \
    -I"$M5_INC" -L"$M5_LIB" -lm5 -lm \
    || { echo "Error de compilación" >&2; exit 1; }

mkdir -p "$OUT"
STATUS="$OUT/.status"
: > "$STATUS"

run_one() {
    local proto=$1 n=$2 c=$3
    local b=$L2BANKS
    [[ $b == cores ]] && b=$c
    local d="$OUT/${proto}_n${n}_c${c}"
    (( b > 1 )) && d="${d}_b${b}"

    if [[ $FORCE != 1 && -f "$d/run.log" ]] \
        && grep -q "Exiting @ tick" "$d/run.log" \
        && grep -q "Resultado correcto" "$d/run.log"; then
        echo "[ya existe] $d"
        echo "ok $d" >> "$STATUS"
        return 0
    fi

    mkdir -p "$d"
    echo "[corriendo] $d"

    # -n = núcleos simulados; el programa recibe "N hilos" con hilos = núcleos
    "$(proto_bin "$proto")" -d "$d" "$SE" \
        --ruby \
        -n "$c" \
        --num-l2caches="$b" \
        --cpu-type=O3CPU \
        -P "system.cpu[:].fetchWidth=$WIDTH" \
        -P "system.cpu[:].decodeWidth=$WIDTH" \
        -P "system.cpu[:].renameWidth=$WIDTH" \
        -P "system.cpu[:].issueWidth=$WIDTH" \
        -P "system.cpu[:].commitWidth=$WIDTH" \
        -c gemm_paralelo \
        -o "$n $c" \
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

for n in $SIZES; do
    for proto in $PROTOS; do
        for c in $CORES; do
            run_one "$proto" "$n" "$c" &
            while (( $(jobs -rp | wc -l) >= JOBS )); do wait -n || true; done
        done
    done
done
wait

echo
echo "Generando resumen..."
L2RX='^system\.ruby\.l2_cntrl[0-9]+\.L2cache\.m_demand_misses$'
python3 scripts/parse_stats.py "$OUT" --extra "$L2RX" > results/e4.csv || exit 1
python3 scripts/parse_stats.py "$OUT" --table

# Speedup S(n) = T(1)/T(n), eficiencia E = S/n y fracción serial estimada
# con Amdahl (métrica de Karp-Flatt): f = (n/S - 1) / (n - 1).
python3 - results/e4.csv results/e4_speedup.csv "$L2RX" <<'PY'
import csv, re, sys

src, dst, l2rx = sys.argv[1], sys.argv[2], sys.argv[3]
rows = list(csv.DictReader(open(src, newline="")))

def cfg(r):
    m = re.fullmatch(r"c(\d+)(?:_b(\d+))?", r["tag"])
    return (int(m.group(1)), int(m.group(2) or 1)) if m else (None, None)

out = []
for proto in sorted({r["protocol"] for r in rows}):
    for n in sorted({r["N"] for r in rows if r["protocol"] == proto}, key=int):
        grp = [r for r in rows if r["protocol"] == proto and r["N"] == n and cfg(r)[0]]
        base = next((r for r in grp if cfg(r) == (1, 1)), None)
        if base is None:
            print(f"AVISO: falta la corrida de 1 núcleo para {proto} N={n}")
            continue
        t1 = float(base["simTicks"])
        # Serie "compartida": L2 de 1 banco. Serie "bancos": bancos = núcleos.
        series = {"compartida": [r for r in grp if cfg(r)[1] == 1]}
        banked = [r for r in grp if cfg(r)[1] > 1]
        if banked:
            series["bancos"] = [base] + banked
        for modo, lista in series.items():
            for r in sorted(lista, key=lambda r: cfg(r)[0]):
                c, b = cfg(r)
                tn = float(r["simTicks"])
                s = t1 / tn
                f = (c / s - 1) / (c - 1) if c > 1 else ""
                out.append({
                    "protocol": proto, "N": int(n), "l2_mode": modo,
                    "cores": c, "l2_banks": b,
                    "time_ms": tn / 1e9,
                    "speedup": round(s, 4),
                    "efficiency": round(s / c, 4),
                    "serial_fraction": round(f, 4) if f != "" else "",
                    "L2_misses": r.get("extra:" + l2rx, ""),
                    "L1_misses": r["L1_misses"],
                    "L1_miss_lat_mean": r["L1_miss_lat_mean"],
                })

fields = ["protocol", "N", "l2_mode", "cores", "l2_banks", "time_ms", "speedup", "efficiency",
          "serial_fraction", "L2_misses", "L1_misses", "L1_miss_lat_mean"]
with open(dst, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=fields)
    w.writeheader()
    w.writerows(out)

print("\nSpeedup, eficiencia y fracción serial (Amdahl / Karp-Flatt):")
for r in out:
    fs = f"{r['serial_fraction']:.3f}" if r["serial_fraction"] != "" else "  -  "
    print(f"{r['protocol']:>5} N={r['N']:>3} L2={r['l2_mode']:<10} núcleos={r['cores']} bancos={r['l2_banks']} | "
          f"S={r['speedup']:.3f} | E={r['efficiency']:.3f} | f={fs} | "
          f"fallos L2={r['L2_misses']}")
PY

nfail=$(grep -c '^fallo' "$STATUS" || true)
echo
if (( nfail > 0 )); then
    echo "$nfail corrida(s) fallaron:"; grep '^fallo' "$STATUS"
    exit 1
fi
echo "E4 completo: $(grep -c '^ok' "$STATUS") corridas."
echo "Métricas: results/e4.csv   Speedup: results/e4_speedup.csv"
echo "Gráficos: python3 scripts/plot_e4.py   (necesita matplotlib, fuera del contenedor)"
