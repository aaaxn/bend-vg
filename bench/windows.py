"""Times the graphs of a series' windows, one graph per window, against a
loop of ts2vg's `build` over the same float32 windows.

    uv run python bench/windows.py [--length 1000000] [--windows 100 1000 10000] [--threads 8 64]

The series is cut into `length / W` windows of W values. bend-visgraph's
time is `bench/windows.bend`: `copy` only cuts the windows, `one` builds
them one after another on one thread, `par` one after another with
parallel.bend, and `split` with the windows split among the threads. Every
time is the best of `--repeats` runs, in ms, with the series already in
memory.
"""

import argparse
import os
import subprocess
import tempfile
import time
from pathlib import Path

import numpy as np
from ts2vg import HorizontalVG, NaturalVG

ROOT = Path(__file__).resolve().parents[1]
BEND = os.environ.get("BEND", str(Path.home() / ".bend/bin/bend"))
GRAPHS = {"natural": NaturalVG, "horizontal": HorizontalVG}
SERIES = {
    "white_noise": lambda rng, n: rng.standard_normal(n),
    "random_walk": lambda rng, n: np.cumsum(rng.standard_normal(n)),
}


def best_ms(f, repeats):
    times = []
    for _ in range(repeats):
        t = time.perf_counter()
        f()
        times.append((time.perf_counter() - t) * 1000)
    return min(times)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--length", type=int, default=1_000_000)
    parser.add_argument("--windows", type=int, nargs="+", default=[100, 1_000, 10_000])
    parser.add_argument("--threads", type=int, nargs="+", default=[8, 64])
    parser.add_argument("--repeats", type=int, default=5)
    args = parser.parse_args()

    (ROOT / "build").mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="windows-", dir=ROOT / "build") as tmp:
        work = Path(tmp)
        env = {**os.environ, "BEND_NO_TELEMETRY": "1"}
        subprocess.run([BEND, "bench/windows.bend", "-o", str(work / "windows")], cwd=ROOT, env=env, check=True)
        runs = [("copy", 1), ("one", 1)] + [(mode, t) for mode in ["par", "split"] for t in args.threads]

        inputs = {}
        for name, make in SERIES.items():
            ts = make(np.random.default_rng(0), args.length).astype(np.float32)
            path = work / f"{name}.txt"
            path.write_text("".join(np.format_float_positional(v, unique=True) + "\n" for v in ts))
            inputs[name] = path, ts.astype(np.float64)

        bend_cols = " | ".join(f"{mode} {t}T" for mode, t in runs)
        print(f"| graph | series | W | windows | edges (ts2vg / bend-visgraph if they differ) | ts2vg loop | {bend_cols} |")
        print("|" + " --- |" * (6 + len(runs)))
        for kind, graph in GRAPHS.items():
            for name, (path, y) in inputs.items():
                for w in args.windows:
                    count = args.length // w
                    loop = lambda: [graph().build(y[k * w:(k + 1) * w]) for k in range(count)]
                    edges = sum(len(g.edges) for g in loop())
                    ts2vg_ms = best_ms(loop, args.repeats)
                    cells, counts = [], set()
                    for mode, t in runs:
                        times = []
                        for _ in range(args.repeats):
                            out = subprocess.run([str(work / "windows"), str(path), kind, str(w), mode, "--threads", str(t)], capture_output=True, text=True, check=True)
                            got, m, checksum, ms = map(int, out.stdout.split())
                            assert got == count, out.stdout
                            if mode != "copy":
                                counts.add((m, checksum))
                            times.append(ms)
                        cells.append(f"{min(times)}")
                    assert len(counts) == 1, counts
                    ours = counts.pop()[0]
                    shown = f"{edges:,}" if ours == edges else f"{edges:,} / {ours:,}"
                    print(f"| {kind} | {name} | {w:,} | {count:,} | {shown} | {ts2vg_ms:.0f} | " + " | ".join(cells) + " |", flush=True)


if __name__ == "__main__":
    main()
