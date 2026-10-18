"""Times bend-vg's build against ts2vg's on the same float32 series.

    uv run python bench/run.py [--sizes 10000 100000 1000000] [--threads 1 8 64] [--limit 0]

ts2vg's `build` makes the edge list and the degrees; `only_degrees` skips
the list. bend-vg's time is `bench/bench.bend`: the edges, a walk over them,
then the degrees. `--limit` above 0 times the limited penetrable graphs.
Every time is the best of `--repeats` runs, in ms, with
the series already in memory.
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
    parser.add_argument("--sizes", type=int, nargs="+", default=[10_000, 100_000, 1_000_000])
    parser.add_argument("--threads", type=int, nargs="+", default=[1, 8, 64])
    parser.add_argument("--repeats", type=int, default=5)
    parser.add_argument("--limit", type=int, default=0)
    args = parser.parse_args()

    (ROOT / "build").mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="bench-", dir=ROOT / "build") as tmp:
        work = Path(tmp)
        env = {**os.environ, "BEND_NO_TELEMETRY": "1"}
        subprocess.run([BEND, "bench/bench.bend", "-o", str(work / "bench")], cwd=ROOT, env=env, check=True)

        bend_cols = " | ".join(f"bend-vg {t}T" for t in args.threads)
        print(f"| graph | series | n | edges (ts2vg / bend-vg if they differ) | ts2vg build | ts2vg only_degrees | {bend_cols} |")
        print("|" + " --- |" * (6 + len(args.threads)))
        for kind, graph in GRAPHS.items():
            for name, make in SERIES.items():
                for n in args.sizes:
                    ts = make(np.random.default_rng(0), n).astype(np.float32)
                    path = work / f"{name}_{n}.txt"
                    path.write_text("".join(np.format_float_positional(v, unique=True) + "\n" for v in ts))
                    x = ts.astype(np.float64)
                    make_graph = lambda: graph(penetrable_limit=args.limit)
                    edges = len(make_graph().build(x).edges)
                    full = best_ms(lambda: make_graph().build(x), args.repeats)
                    degrees = best_ms(lambda: make_graph().build(x, only_degrees=True), args.repeats)
                    cells, counts = [], set()
                    for t in args.threads:
                        runs = []
                        for _ in range(args.repeats):
                            out = subprocess.run([str(work / "bench"), str(path), kind, str(args.limit), "--threads", str(t)], capture_output=True, text=True, check=True)
                            points, m, _, edges_ms, degrees_ms = out.stdout.split()
                            assert int(points) == n, out.stdout
                            counts.add(int(m))
                            runs.append(int(edges_ms) + int(degrees_ms))
                        cells.append(f"{min(runs)}")
                    assert len(counts) == 1, counts
                    ours = counts.pop()
                    shown = f"{edges:,}" if ours == edges else f"{edges:,} / {ours:,}"
                    print(f"| {kind} | {name} | {n:,} | {shown} | {full:.0f} | {degrees:.0f} | " + " | ".join(cells) + " |", flush=True)

if __name__ == "__main__":
    main()
