import csv
import os
import matplotlib.pyplot as plt

CSV_FILE = "results/e3_speedup.csv"
OUTPUT_DIR = "results/e3/graficas"

os.makedirs(OUTPUT_DIR, exist_ok=True)

with open(CSV_FILE, newline="") as f:
    data = list(csv.DictReader(f))

if not data:
    raise SystemExit("El CSV no contiene datos.")

# Agrupar resultados por tamaño de matriz
sizes = sorted(set(int(row["N"]) for row in data))

for n in sizes:
    rows = sorted(
        [r for r in data if int(r["N"]) == n],
        key=lambda r: int(r["VL_bits"])
    )

    vl = [int(r["VL_bits"]) for r in rows]
    speedup = [float(r["speedup"]) for r in rows]

    scalar_inst = float(rows[0]["scalar_instructions"])
    sve_inst = [float(r["sve_instructions"]) for r in rows]

    scalar_cycles = float(rows[0]["scalar_cycles"])
    sve_cycles = [float(r["sve_cycles"]) for r in rows]

    # 1. Speedup vs longitud vectorial
    plt.figure()
    plt.plot(vl, speedup, marker="o", label=f"N={n}")
    plt.axhline(1, linestyle="--", label="Referencia escalar")
    plt.xlabel("Longitud vectorial SVE (bits)")
    plt.ylabel("Speedup")
    plt.title(f"Speedup vs longitud vectorial (N={n})")
    plt.xticks(vl)
    plt.grid(True)
    plt.legend()
    plt.tight_layout()
    plt.savefig(f"{OUTPUT_DIR}/speedup_N{n}.png", dpi=300)
    plt.close()

    # 2. Instrucciones ejecutadas
    plt.figure()
    plt.plot(vl, sve_inst, marker="o", label="SVE")
    plt.axhline(scalar_inst, linestyle="--", label="Escalar")
    plt.xlabel("Longitud vectorial SVE (bits)")
    plt.ylabel("Instrucciones ejecutadas")
    plt.title(f"Instrucciones ejecutadas (N={n})")
    plt.xticks(vl)
    plt.yscale("log")
    plt.grid(True)
    plt.legend()
    plt.tight_layout()
    plt.savefig(f"{OUTPUT_DIR}/instrucciones_N{n}.png", dpi=300)
    plt.close()

    # 3. Ciclos de ejecución
    plt.figure()
    plt.plot(vl, sve_cycles, marker="o", label="SVE")
    plt.axhline(scalar_cycles, linestyle="--", label="Escalar")
    plt.xlabel("Longitud vectorial SVE (bits)")
    plt.ylabel("Ciclos")
    plt.title(f"Ciclos de ejecución (N={n})")
    plt.xticks(vl)
    plt.yscale("log")
    plt.grid(True)
    plt.legend()
    plt.tight_layout()
    plt.savefig(f"{OUTPUT_DIR}/ciclos_N{n}.png", dpi=300)
    plt.close()

print("Graficas generadas correctamente:")
for filename in sorted(os.listdir(OUTPUT_DIR)):
    print(os.path.join(OUTPUT_DIR, filename))
