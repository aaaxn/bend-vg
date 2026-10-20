"""Compares bend-visgraph's edges with ts2vg's, edge for edge, on the series of
bench/run.py, and decides each edge they disagree on in exact arithmetic.

    uv run python bench/compare.py [--sizes 10000 100000 1000000] [--limit 0] [--xs]

bend-visgraph computes in float32 and ts2vg in float64, on the same float32
values. Where they disagree, integer arithmetic on those values says
whether the edge is in the graph: an edge crosses at most `limit` points
on or above the line between its ends (natural) or as high as its lower end
(horizontal).
"""

import argparse
import os
import subprocess
import tempfile
from fractions import Fraction
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


def irregular_xs(n):
    return np.cumsum(0.5 + np.random.default_rng(1).random(n)).astype(np.float32)


def write(path, values):
    path.write_text("".join(np.format_float_positional(v, unique=True) + "\n" for v in values))


def keys(pairs, n):
    pairs = np.asarray(pairs, dtype=np.int64).reshape(-1, 2)
    return np.unique(np.minimum(pairs[:, 0], pairs[:, 1]) * n + np.maximum(pairs[:, 0], pairs[:, 1]))


def exact(values):
    """Each float32 value times 2**160, an integer."""
    return [int(Fraction(float(v)) * 2**160) for v in values]


def in_graph(kind, xs, ys, i, j, limit):
    crossed = 0
    for k in range(i + 1, j):
        if kind == "natural":
            blocks = (ys[k] - ys[i]) * (xs[j] - xs[i]) >= (ys[j] - ys[i]) * (xs[k] - xs[i])
        else:
            blocks = ys[k] >= min(ys[i], ys[j])
        crossed += blocks
        if crossed > limit:
            return False
    return True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sizes", type=int, nargs="+", default=[10_000, 100_000, 1_000_000])
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--xs", action="store_true", help="x irregular, as in bench/run.py --xs")
    args = parser.parse_args()

    (ROOT / "build").mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="compare-", dir=ROOT / "build") as tmp:
        work = Path(tmp)
        env = {**os.environ, "BEND_NO_TELEMETRY": "1"}
        subprocess.run([BEND, "bend_vg.bend", "-o", str(work / "bend_vg")], cwd=ROOT, env=env, check=True)

        print("| graph | series | n | ts2vg edges | bend-visgraph edges | only in ts2vg (in the graph) | only in bend-visgraph (in the graph) |")
        print("|" + " --- |" * 7)
        for kind, graph in GRAPHS.items():
            for name, make in SERIES.items():
                for n in args.sizes:
                    ts = make(np.random.default_rng(0), n).astype(np.float32)
                    xs = irregular_xs(n) if args.xs else np.arange(n, dtype=np.float32)
                    path = work / f"{name}_{n}.txt"
                    write(path, ts)
                    cli = [str(work / "bend_vg"), str(path), "-t", kind, "-p", str(args.limit)]
                    if args.xs:
                        write(work / f"xs_{n}.txt", xs)
                        cli += ["-x", str(work / f"xs_{n}.txt")]
                    g = graph(penetrable_limit=args.limit).build(ts.astype(np.float64), xs=xs.astype(np.float64))
                    theirs = keys(g._edges_array, n)
                    out = subprocess.run(cli, capture_output=True, text=True, check=True).stdout
                    ours = keys(np.array(out.split(), dtype=np.int64), n)
                    only = {"ts2vg": np.setdiff1d(theirs, ours), "bend-visgraph": np.setdiff1d(ours, theirs)}
                    cells = []
                    if any(len(v) for v in only.values()):
                        ex, ey = exact(xs), exact(ts)
                    for side in ["ts2vg", "bend-visgraph"]:
                        held = sum(in_graph(kind, ex, ey, int(k // n), int(k % n), args.limit) for k in only[side])
                        cells.append(f"{len(only[side])} ({held})" if len(only[side]) else "0")
                    print(f"| {kind} | {name} | {n:,} | {len(theirs):,} | {len(ours):,} | " + " | ".join(cells) + " |", flush=True)


if __name__ == "__main__":
    main()
