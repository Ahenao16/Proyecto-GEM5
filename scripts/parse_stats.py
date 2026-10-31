#!/usr/bin/env python3
"""
parse_stats.py - extrae las métricas de la ROI de las corridas de gem5 a CSV.

Uso:
    python3 scripts/parse_stats.py results/gemm_escalar > results/gemm_escalar.csv
    python3 scripts/parse_stats.py results/e2 results/e3 > todo.csv
    python3 scripts/parse_stats.py results/e5 --extra 'Inv' > e5.csv

Las carpetas de corrida se llaman <protocolo>_n<N>[_<etiqueta>] (p. ej. mesi_n128,
moesi_n64_o3); protocolo, N y etiqueta salen como columnas del CSV.

Cada argumento puede ser una carpeta (se busca stats.txt de forma recursiva)
o un stats.txt. Se toma SOLO el primer bloque "Begin Simulation Statistics",
que es el que escribe m5_dump_stats() al final de la ROI. El segundo bloque
lo escribe gem5 al terminar y contiene también check()/free(), así que se
descarta (opción --block para cambiarlo).

Solo usa la biblioteca estándar de Python 3.
"""
import argparse
import csv
import re
import sys
from pathlib import Path

BEGIN = "Begin Simulation Statistics"


def read_blocks(path):
    """Devuelve la lista de bloques; cada bloque es un dict nombre -> float."""
    blocks, cur = [], None
    with open(path, errors="replace") as f:
        for line in f:
            if BEGIN in line:
                cur = {}
                blocks.append(cur)
                continue
            if cur is None or not line.strip() or line.startswith("-"):
                continue
            tok = line.split()
            if len(tok) < 2:
                continue
            try:
                cur[tok[0]] = float(tok[1])   # "|" (histogramas) y "nan" se descartan abajo
            except ValueError:
                continue
    return blocks


def sum_re(stats, pattern):
    """Suma los stats cuyo nombre cumple la expresión regular. None si no hay."""
    rx = re.compile(pattern)
    vals = [v for k, v in stats.items() if rx.search(k) and v == v]  # v == v descarta nan
    return sum(vals) if vals else None


def metrics(stats, extras):
    m = {}
    m["simInsts"] = stats.get("simInsts")
    m["simTicks"] = stats.get("simTicks")

    # Ciclos: el tiempo lo marca el núcleo que más ciclos cuenta (system.cpu o system.cpuN)
    cyc = [v for k, v in stats.items()
           if re.fullmatch(r"system\.cpu\d*\.numCycles", k) and v > 0]
    m["cycles"] = max(cyc) if cyc else None
    m["active_cores"] = len(cyc) if cyc else None
    if m["simInsts"] and m["cycles"]:
        m["IPC"] = m["simInsts"] / m["cycles"]
        m["CPI"] = m["cycles"] / m["simInsts"]
    else:
        m["IPC"] = m["CPI"] = None

    # --- Ruby (E5 y corridas con --ruby) ---
    hits = stats.get("system.ruby.m_hitLatencyHistSeqr::samples")
    miss = stats.get("system.ruby.m_missLatencyHistSeqr::samples")
    m["L1_hits"], m["L1_misses"] = hits, miss
    m["L1_miss_rate"] = miss / (hits + miss) if hits is not None and miss is not None and hits + miss else None
    m["L1_miss_lat_mean"] = stats.get("system.ruby.m_missLatencyHistSeqr::mean")
    m["ruby_msgs_total"] = sum_re(stats, r"^system\.ruby\.network\.msg_count\.[A-Za-z_0-9]+$")

    # --- Cachés clásicas (--caches --l2cache), si existen ---
    ch = sum_re(stats, r"^system\.cpu\d*\.dcache\.overallHits::total$")
    cm = sum_re(stats, r"^system\.cpu\d*\.dcache\.overallMisses::total$")
    if m["L1_hits"] is None and ch is not None:
        m["L1_hits"], m["L1_misses"] = ch, cm
        m["L1_miss_rate"] = cm / (ch + cm) if cm is not None and ch + cm else None
    m["L2_misses"] = sum_re(stats, r"^system\.l2\.overallMisses::total$")

    for name in extras:
        m["extra:" + name] = sum_re(stats, name)
    return m


def natural_key(p):
    return [int(t) if t.isdigit() else t for t in re.split(r"(\d+)", str(p))]


def find_runs(paths):
    files = []
    for a in paths:
        p = Path(a)
        if p.is_file():
            files.append(p)
        else:
            files.extend(p.rglob("stats.txt"))
    return sorted(set(files), key=natural_key)


def fmt(c, v):
    """Formato para el CSV (sin separadores de miles)."""
    if v is None:
        return ""
    if isinstance(v, float) and c in ("IPC", "CPI", "L1_miss_rate", "L1_miss_lat_mean", "time_ms"):
        return f"{v:.6g}"
    if isinstance(v, float) and v.is_integer():
        return int(v)
    return v


def print_table(rows):
    """Tabla alineada y legible para la pantalla (no para el CSV)."""
    spec = [("run", "corrida", "<", lambda v: v),
            ("simInsts", "instrucciones", ">", lambda v: f"{int(v):,}"),
            ("cycles", "ciclos", ">", lambda v: f"{int(v):,}"),
            ("time_ms", "tiempo (ms)", ">", lambda v: f"{v:,.3f}"),
            ("IPC", "IPC", ">", lambda v: f"{v:.3f}"),
            ("L1_misses", "fallos L1", ">", lambda v: f"{int(v):,}"),
            ("L1_miss_lat_mean", "lat. fallo", ">", lambda v: f"{v:.1f}")]
    data = [[(f(r[k]) if r.get(k) is not None else "-") for k, _, _, f in spec] for r in rows]
    heads = [h for _, h, _, _ in spec]
    width = [max(len(heads[i]), *(len(d[i]) for d in data)) for i in range(len(spec))]
    line = lambda cells: "  ".join(format(c, a + str(width[i]))
                                  for i, (c, (_, _, a, _)) in enumerate(zip(cells, spec)))
    print(line(heads))
    print("  ".join("-" * w for w in width))
    for d in data:
        print(line(d))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("paths", nargs="+", help="carpetas con corridas o archivos stats.txt")
    ap.add_argument("--block", type=int, default=1, help="bloque a leer (1 = ROI, por defecto)")
    ap.add_argument("--extra", action="append", default=[], metavar="REGEX",
                    help="columna extra: suma de los stats cuyo nombre cumpla la regex (repetible)")
    ap.add_argument("--table", action="store_true",
                    help="en vez de CSV, imprime una tabla alineada con las métricas principales")
    args = ap.parse_args()

    cols = ["run", "protocol", "N", "tag", "simInsts", "simTicks", "time_ms", "cycles", "active_cores",
            "IPC", "CPI", "L1_hits", "L1_misses", "L1_miss_rate", "L1_miss_lat_mean", "L2_misses",
            "ruby_msgs_total"]
    cols += ["extra:" + e for e in args.extra]

    files = find_runs(args.paths)
    if not files:
        sys.exit("No se encontró ningún stats.txt en: " + " ".join(args.paths))

    rows = []
    for f in files:
        blocks = read_blocks(f)
        run = f.parent.name
        if len(blocks) < args.block:
            print(f"AVISO {f}: tiene {len(blocks)} bloque(s); no existe el bloque {args.block}.",
                  file=sys.stderr)
            continue
        if len(blocks) == 1:
            print(f"AVISO {f}: solo 1 bloque. Si el programa usa m5_reset_stats/m5_dump_stats, "
                  "la ROI no se delimitó y estas métricas incluyen todo el programa.", file=sys.stderr)
        row = metrics(blocks[args.block - 1], args.extra)
        # Nombre de carpeta: <protocolo>_n<N>[_<etiqueta>], p. ej. mesi_n128 o moesi_n64_o3
        mt = re.match(r"(?P<p>[A-Za-z]+)_n(?P<n>\d+)(?:_(?P<t>.+))?$", run)
        row["run"] = run
        row["protocol"] = mt.group("p") if mt else ""
        row["N"] = mt.group("n") if mt else ""
        row["tag"] = (mt.group("t") or "") if mt else ""
        row["time_ms"] = row["simTicks"] / 1e9 if row.get("simTicks") else None   # 1 tick = 1 ps
        rows.append(row)

    if args.table:
        print_table(rows)
        return
    w = csv.DictWriter(sys.stdout, fieldnames=cols, lineterminator="\n")
    w.writeheader()
    for row in rows:
        w.writerow({c: fmt(c, row.get(c)) for c in cols})


if __name__ == "__main__":
    main()