#!/usr/bin/env python3
"""plot_e4.py - gráficos de E4 a partir de results/e4_speedup.csv.

Genera en results/e4/graficas/:
  speedup.png      speedup medido vs. ideal (S = n), una curva por N
  eficiencia.png   eficiencia E = S/n por N
  fallos_l2.png    fallos de L2 por número de núcleos
Uso: python3 scripts/plot_e4.py   (desde la raíz del repo; necesita matplotlib)
"""
import csv
import os
import sys

import matplotlib.pyplot as plt

CSV_FILE = sys.argv[1] if len(sys.argv) > 1 else "results/e4_speedup.csv"
OUT_DIR = sys.argv[2] if len(sys.argv) > 2 else "results/e4/graficas"
os.makedirs(OUT_DIR, exist_ok=True)

with open(CSV_FILE, newline="") as f:
    data = list(csv.DictReader(f))
if not data:
    raise SystemExit("El CSV no contiene datos.")

series = {}
for r in data:
    key = (r["protocol"], int(r["N"]), r.get("l2_mode", "compartida"))
    series.setdefault(key, []).append(r)
for key in series:
    series[key].sort(key=lambda r: int(r["cores"]))

all_cores = sorted({int(r["cores"]) for r in data})


def etiqueta(key):
    proto, n, modo = key
    l2 = "L2 de 1 banco" if modo == "compartida" else "L2 con n bancos"
    return f"N = {n}, {l2}"


def estilo(key):
    return "o-" if key[2] == "compartida" else "s--"


def guardar(nombre):
    plt.tight_layout()
    plt.savefig(os.path.join(OUT_DIR, nombre), dpi=150)
    plt.close()
    print("Guardado:", os.path.join(OUT_DIR, nombre))


# Speedup vs. ideal
plt.figure(figsize=(6, 4.5))
plt.plot(all_cores, all_cores, "k--", label="Ideal (S = n)")
for key, rows in sorted(series.items()):
    c = [int(r["cores"]) for r in rows]
    s = [float(r["speedup"]) for r in rows]
    plt.plot(c, s, estilo(key), label=etiqueta(key))
plt.xlabel("Núcleos")
plt.ylabel("Speedup S(n) = T(1)/T(n)")
plt.title("E4: speedup de GEMM paralelo (O3 ancho 2, MESI)")
plt.xticks(all_cores)
plt.grid(alpha=0.3)
plt.legend()
guardar("speedup.png")

# Eficiencia
plt.figure(figsize=(6, 4.5))
plt.axhline(1.0, color="k", ls="--", label="Ideal (E = 1)")
for key, rows in sorted(series.items()):
    c = [int(r["cores"]) for r in rows]
    e = [float(r["efficiency"]) for r in rows]
    plt.plot(c, e, estilo(key), label=etiqueta(key))
plt.xlabel("Núcleos")
plt.ylabel("Eficiencia E = S/n")
plt.title("E4: eficiencia")
plt.xticks(all_cores)
plt.ylim(0, 1.2)
plt.grid(alpha=0.3)
plt.legend()
guardar("eficiencia.png")

# Fallos de L2
plt.figure(figsize=(6, 4.5))
for key, rows in sorted(series.items()):
    rows = [r for r in rows if r["L2_misses"] not in ("", None)]
    if not rows:
        continue
    c = [int(r["cores"]) for r in rows]
    m = [float(r["L2_misses"]) for r in rows]
    plt.plot(c, m, estilo(key), label=etiqueta(key))
plt.xlabel("Núcleos")
plt.ylabel("Fallos de L2 (ROI)")
plt.title("E4: fallos de L2")
plt.xticks(all_cores)
plt.grid(alpha=0.3)
plt.legend()
guardar("fallos_l2.png")
