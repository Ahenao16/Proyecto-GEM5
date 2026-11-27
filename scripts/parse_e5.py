import csv
import os
import re
import sys

BLOCK_SEP = "---------- Begin Simulation Statistics"
NAME_RE = re.compile(r"^(?P<proto>[a-z0-9]+)_(?P<work>.+)_n(?P<cores>\d+)$")
COLUMNS = ["protocolo", "carga", "nucleos", "sim_ticks", "inv_events", "inv_msgs",
           "fwd_events", "msgs", "msg_bytes", "miss_lat_mean", "miss_samples"]


def first_block(path):
    """Devuelve {nombre: valor} del primer bloque de stats.txt y cuántos hay."""
    stats, blocks = {}, 0
    with open(path, errors="replace") as f:
        for line in f:
            if line.startswith(BLOCK_SEP):
                blocks += 1
                continue
            if blocks != 1 or line.startswith("-"):
                continue
            parts = line.split("#", 1)[0].split()
            if len(parts) >= 2:
                try:
                    stats[parts[0]] = float(parts[1])
                except ValueError:
                    pass
    # Si no hay marcadores de bloque, leer todo (versiones muy antiguas)
    if blocks == 0:
        with open(path, errors="replace") as f:
            for line in f:
                parts = line.split("#", 1)[0].split()
                if len(parts) >= 2:
                    try:
                        stats[parts[0]] = float(parts[1])
                    except ValueError:
                        pass
    return stats, blocks


def first(stats, *names):
    for n in names:
        if n in stats:
            return stats[n]
    return None


def miss_latency(stats):
    """Media ponderada por muestras de los histogramas de latencia de fallo.
    Usa los de cada secuenciador si existen; si no, el global."""
    pat = re.compile(r"miss_?latency_?hist(?:_?seqr)?::(mean|samples)$", re.I)
    por_seq, glob = {}, {}
    for name, val in stats.items():
        m = pat.search(name)
        if not m or "type" in name.lower():
            continue
        destino = por_seq if "sequencer" in name.lower() else glob
        base = name[:name.rfind("::")]
        destino.setdefault(base, {})[m.group(1)] = val
    grupo = por_seq or glob
    tot_s = sum(d.get("samples", 0) for d in grupo.values())
    if not grupo or tot_s == 0:
        return None, 0
    ponderada = sum(d.get("mean", 0) * d.get("samples", 0) for d in grupo.values())
    return ponderada / tot_s, tot_s


def extract(stats):
    inv_ev = fwd_ev = 0.0
    inv_found = fwd_found = False
    msgs = msg_b = 0.0
    inv_msgs = 0.0
    net_found = False
    net_pat = re.compile(r"^system\.ruby\.network\.(msg_count|msg_byte)[.:]+(\w+)$")
    for name, val in stats.items():
        p = name.split(".")
        # Evento agregado (sin estado) del controlador L1: ...L1Cache_Controller.<Evento>
        if len(p) >= 2 and p[-2] == "L1Cache_Controller":
            if p[-1] == "Inv":
                inv_ev += val
                inv_found = True
            elif p[-1] in ("Fwd_GETX", "Fwd_GETS"):
                fwd_ev += val
                fwd_found = True
        m = net_pat.match(name)
        if m:
            net_found = True
            if m.group(1) == "msg_count":
                msgs += val
                if "inv" in m.group(2).lower():
                    inv_msgs += val
            else:
                msg_b += val
    lat, samples = miss_latency(stats)
    return {
        "sim_ticks": first(stats, "simTicks", "sim_ticks"),
        "inv_events": inv_ev if inv_found else None,
        "inv_msgs": inv_msgs if net_found else None,
        "fwd_events": fwd_ev if fwd_found else None,
        "msgs": msgs if net_found else None,
        "msg_bytes": msg_b if net_found else None,
        "miss_lat_mean": lat,
        "miss_samples": samples or None,
    }


def collect(root):
    rows = []
    for d in sorted(os.listdir(root)):
        path = os.path.join(root, d, "stats.txt")
        m = NAME_RE.match(d)
        if not (m and os.path.isfile(path)):
            continue
        stats, blocks = first_block(path)
        if blocks < 2:
            print(f"AVISO: {d}: solo {blocks} bloque(s); ¿se ejecutó m5_dump_stats()?",
                  file=sys.stderr)
        row = {"protocolo": m["proto"], "carga": m["work"], "nucleos": int(m["cores"])}
        row.update(extract(stats))
        rows.append(row)
    rows.sort(key=lambda r: (r["carga"], r["protocolo"], r["nucleos"]))
    return rows


def fmt(v):
    if v is None:
        return ""
    return f"{v:.2f}" if isinstance(v, float) and v != int(v) else str(int(v))


def table(rows):
    print(f"{'proto':6} {'carga':9} {'n':>2} {'ticks':>14} {'inv_ev':>9} {'inv_msg':>9} "
          f"{'fwd_ev':>9} {'msgs':>10} {'lat_fallo':>9}")
    for r in rows:
        print(f"{r['protocolo']:6} {r['carga']:9} {r['nucleos']:>2} {fmt(r['sim_ticks']):>14} "
              f"{fmt(r['inv_events']):>9} {fmt(r['inv_msgs']):>9} {fmt(r['fwd_events']):>9} "
              f"{fmt(r['msgs']):>10} {fmt(r['miss_lat_mean']):>9}")
    # Costo del falso compartido: nopad / pad
    idx = {(r["protocolo"], r["carga"], r["nucleos"]): r for r in rows}
    pares = sorted({(p, n) for (p, w, n) in idx if w == "fs_nopad" and (p, "fs_pad", n) in idx})
    if pares:
        print("\nCosto del falso compartido (nopad / pad):")
        print(f"{'proto':6} {'n':>2} {'tiempo':>8} {'inv_ev':>8} {'msgs':>8} {'lat_fallo':>10}")
        for p, n in pares:
            a, b = idx[(p, "fs_nopad", n)], idx[(p, "fs_pad", n)]
            def ratio(k):
                x, y = a[k], b[k]
                return f"{x / y:.2f}x" if x is not None and y else "n/d"
            print(f"{p:6} {n:>2} {ratio('sim_ticks'):>8} {ratio('inv_events'):>8} "
                  f"{ratio('msgs'):>8} {ratio('miss_lat_mean'):>10}")


def find(root, patron):
    pat = re.compile(patron, re.I)
    for d in sorted(os.listdir(root)):
        path = os.path.join(root, d, "stats.txt")
        if os.path.isfile(path):
            stats, _ = first_block(path)
            print(f"# {d}")
            for k, v in stats.items():
                if pat.search(k):
                    print(f"{k} {v:g}")
            return
    print("No hay stats.txt en", root, file=sys.stderr)


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        sys.exit(1)
    root = args[0]
    if "--find" in args:
        find(root, args[args.index("--find") + 1])
        return
    rows = collect(root)
    if not rows:
        print(f"No se encontraron corridas en {root}", file=sys.stderr)
        sys.exit(1)
    if "--table" in args:
        table(rows)
        return
    w = csv.DictWriter(sys.stdout, fieldnames=COLUMNS)
    w.writeheader()
    for r in rows:
        w.writerow({k: ("" if r.get(k) is None else
                        (int(r[k]) if isinstance(r[k], float) and r[k] == int(r[k])
                         else (round(r[k], 3) if isinstance(r[k], float) else r[k])))
                    for k in COLUMNS})


if __name__ == "__main__":
    main()