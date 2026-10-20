"""Measures the peak memory of one build, bend-visgraph's against ts2vg's,
on the series of bench/run.py.

    uv run python bench/memory.py [--sizes 1000000] [--limit 0] [--threads 1 64]

Each build runs in a process of its own, and its peak is the largest
resident set of `--repeats` runs, in MiB, as GNU time reports it.
bend-visgraph's process is `bench/bench.bend`, which reads the series from
a text file. Its baseline only reads the series and copies it, with
`bench/windows.bend copy` and one window. ts2vg's process loads the series
from a numpy file and builds. Its baseline loads the series and imports
ts2vg.
"""

import argparse
import os
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
BEND = os.environ.get("BEND", str(Path.home() / ".bend/bin/bend"))
SERIES = {
    "white_noise": lambda rng, n: rng.standard_normal(n),
    "random_walk": lambda rng, n: np.cumsum(rng.standard_normal(n)),
}

# Builds the graph in ts2vg and prints its edge count: argv is the series' numpy
# file, the graph, the limit, and `build`, `only_degrees` or `none`.
TS2VG = """
import sys
import numpy as np
from ts2vg import HorizontalVG, NaturalVG

path, kind, limit, how = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
y = np.load(path)
if how != "none":
    g = {"natural": NaturalVG, "horizontal": HorizontalVG}[kind](penetrable_limit=limit)
    g.build(y, only_degrees=how == "only_degrees")
    print(int(g.degrees.sum()) // 2)
else:
    print(0)
"""


def peak(cmd, rss):
    """The output of `cmd`, and the most memory it held, in MiB. GNU time
    runs it: a process forked from this one would count this one's memory,
    which exec keeps as its peak."""
    out = subprocess.run(["/usr/bin/time", "-f", "%M", "-o", str(rss), *cmd], stdout=subprocess.PIPE, text=True, check=True)
    return out.stdout, int(rss.read_text()) / 1024


def largest(cmd, rss, repeats):
    runs = [peak(cmd, rss) for _ in range(repeats)]
    return runs[0][0], max(mb for _, mb in runs)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sizes", type=int, nargs="+", default=[1_000_000])
    parser.add_argument("--threads", type=int, nargs="+", default=[1, 64])
    parser.add_argument("--repeats", type=int, default=3)
    parser.add_argument("--limit", type=int, default=0)
    args = parser.parse_args()

    (ROOT / "build").mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="memory-", dir=ROOT / "build") as tmp:
        work = Path(tmp)
        env = {**os.environ, "BEND_NO_TELEMETRY": "1"}
        for source, target in [("bench/bench.bend", "bench"), ("bench/windows.bend", "windows")]:
            subprocess.run([BEND, source, "-o", str(work / target)], cwd=ROOT, env=env, check=True)

        inputs = {}
        for name, make in SERIES.items():
            for n in args.sizes:
                ts = make(np.random.default_rng(0), n).astype(np.float32)
                text, npy = work / f"{name}_{n}.txt", work / f"{name}_{n}.npy"
                text.write_text("".join(np.format_float_positional(v, unique=True) + "\n" for v in ts))
                np.save(npy, ts.astype(np.float64))
                inputs[name, n] = text, npy

        bend_cols = " | ".join(f"bend-visgraph {t}T" for t in args.threads)
        print(f"| graph | series | n | edges (ts2vg / bend-visgraph if they differ) | ts2vg baseline | ts2vg build | ts2vg only_degrees | bend-visgraph baseline | {bend_cols} |")
        print("|" + " --- |" * (8 + len(args.threads)))
        for kind in ["natural", "horizontal"]:
            for name in SERIES:
                for n in args.sizes:
                    path, npy = inputs[name, n]
                    ts2vg = lambda how: largest([sys.executable, "-c", TS2VG, str(npy), kind, str(args.limit), how], work / "rss", args.repeats)
                    _, ts2vg_base = ts2vg("none")
                    edges, ts2vg_build = ts2vg("build")
                    degrees_edges, ts2vg_degrees = ts2vg("only_degrees")
                    assert edges == degrees_edges, (edges, degrees_edges)
                    edges = int(edges)
                    _, bend_base = largest([str(work / "windows"), str(path), kind, str(n), "copy", "--threads", "1"], work / "rss", args.repeats)
                    cells, counts = [], set()
                    for t in args.threads:
                        out, mb = largest([str(work / "bench"), str(path), kind, str(args.limit), "--threads", str(t)], work / "rss", args.repeats)
                        counts.add(int(out.split()[1]))
                        cells.append(f"{mb:.0f}")
                    assert len(counts) == 1, counts
                    ours = counts.pop()
                    shown = f"{edges:,}" if ours == edges else f"{edges:,} / {ours:,}"
                    print(f"| {kind} | {name} | {n:,} | {shown} | {ts2vg_base:.0f} | {ts2vg_build:.0f} | {ts2vg_degrees:.0f} | {bend_base:.0f} | " + " | ".join(cells) + " |", flush=True)


if __name__ == "__main__":
    main()
