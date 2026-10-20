"""bend_visgraph against the float32 reference (bit for bit) and against ts2vg."""

import fcntl
import functools
import os
import shutil
import subprocess
from pathlib import Path

import numpy as np
import pytest
from ts2vg import HorizontalVG, NaturalVG

import reference

ROOT = Path(__file__).resolve().parents[1]
BEND = os.environ.get("BEND", str(Path.home() / ".bend/bin/bend"))
BUN = shutil.which("bun") or str(Path.home() / ".bun/bin/bun")
GRAPHS = {"natural": NaturalVG, "horizontal": HorizontalVG}
DIRECTIONS = [None, "left_to_right", "top_to_bottom"]


def _series():
    rng = np.random.default_rng(0)
    t = np.arange(500)
    out = {
        "empty": [],
        "one": [1.0],
        "two": [2.0, 1.0],
        "sample": [3.0, 4.0, 2.0, 1.0],
        "sample_2": [0.25, 0.10, 1.50, -0.10, -0.30, 0.0, 0.20, 1.20, 1.85, -0.35],
        "flat": [1.0, 1.0, 1.0, 1.0],
        "nans": [np.nan, 2.0, np.nan, 1.0, 3.0, np.nan, 3.0, 0.5, np.nan],
        "noise_nans": np.where(np.arange(300) % 7 == 3, np.nan, np.random.default_rng(1).standard_normal(300)),
        "nan_runs": np.where(np.arange(400) // 50 % 3 == 1, np.nan, np.random.default_rng(2).standard_normal(400)),
        "all_nans": np.full(200, np.nan),
        "infs": [1.0, np.inf, 2.0, -np.inf, 0.5, 3.0, np.inf, -1.0, -np.inf, 2.5, 1.5, np.inf],
        "noise_infs": np.where(np.arange(300) % 11 == 5, np.inf, np.where(np.arange(300) % 13 == 7, -np.inf, np.random.default_rng(3).standard_normal(300))),
        "white_noise": np.random.default_rng(0).standard_normal(1000),
        "brownian": np.cumsum(np.random.default_rng(0).standard_normal(1000)),
        "linear_small": [9999 + k / 10 for k in range(11)],
        "linear_large": 99999999 + np.arange(0, 100, 0.1),
        "linear_large_negative": -99999999 - np.arange(0, 100, 0.1),
        "uniform": rng.random(500),
        "small_ints": rng.integers(0, 10, 500).astype(float),
        "sine_noise": np.sin(2 * np.pi * t / 50) + 0.05 * rng.standard_normal(500),
        "small_js": rng.standard_normal(150),
    }
    return {name: np.asarray(v, dtype=np.float32) for name, v in out.items()}


SERIES = _series()


@pytest.fixture(scope="session")
def builds(tmp_path_factory, worker_id):
    # One build per run, which every xdist worker shares: the first to take
    # the lock builds. Without xdist, the parent of the run's directory is
    # shared by every run, so the build goes in the run's own directory.
    root = tmp_path_factory.getbasetemp()
    out = (root if worker_id == "master" else root.parent) / "build"
    out.mkdir(exist_ok=True)
    env = {**os.environ, "BEND_NO_TELEMETRY": "1"}
    with open(out / "lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if not (out / "done").exists():
            for source, target in [("bend_visgraph.bend", "bend_visgraph"), ("tests/one_thread.bend", "one_thread"), ("tests/library.bend", "library")]:
                for suffix in ["", ".js"]:
                    subprocess.run([BEND, source, "-o", str(out / (target + suffix))], cwd=ROOT, env=env, check=True)
            for source, target in [("bench/bench.bend", "bench"), ("bench/windows.bend", "windows")]:
                subprocess.run([BEND, source, "-o", str(out / target)], cwd=ROOT, env=env, check=True)
            (out / "done").touch()
    return out


@pytest.fixture(scope="session")
def lanes(builds):
    return {"native": [str(builds / "bend_visgraph")], "js": [BUN, str(builds / "bend_visgraph.js")]}


@pytest.fixture(scope="session")
def one_thread(builds):
    return {"native": [str(builds / "one_thread")], "js": [BUN, str(builds / "one_thread.js")]}


@pytest.fixture(scope="session")
def library(builds):
    return {"native": [str(builds / "library")], "js": [BUN, str(builds / "library.js")]}


@pytest.fixture(scope="session")
def inputs(tmp_path_factory):
    out = tmp_path_factory.mktemp("series")
    paths = {}
    for name, ts in SERIES.items():
        paths[name] = out / f"{name}.txt"
        paths[name].write_text("".join(np.format_float_positional(v, unique=True) + "\n" for v in ts))
    return paths


def run(lane, path, *args):
    done = subprocess.run([*lane, str(path), *args], capture_output=True, text=True, timeout=600)
    assert done.returncode == 0, done.stderr
    return done.stdout


def bits(w):
    if np.isnan(np.float32(w)):
        return "nan"
    return int(np.array([np.float32(w)]).view(np.uint32)[0])


def parse_edges(text):
    edges = []
    for line in text.splitlines():
        s, t, *w = line.split()
        edges.append((int(s), int(t), bits(w[0]) if w else None))
    return sorted(edges)


def options(kind, directed, weighted):
    args = ["-t", kind]
    if directed:
        args += ["-d", directed]
    if weighted:
        args += ["-w", weighted]
    return args


@functools.cache
def reference_edges(series, kind, directed, weighted):
    return reference.build(SERIES[series], kind, directed, weighted)


def expected(series, kind, directed, weighted):
    edges = reference_edges(series, kind, directed, weighted)
    return sorted((s, t, bits(w) if weighted else None) for s, t, w in edges)


def degree_counts(edges, n):
    degrees = np.bincount(np.array([e[:2] for e in edges], dtype=int).reshape(-1), minlength=n)
    return degrees, *np.unique(degrees, return_counts=True)


CASES = [(s, k, d, w) for s in SERIES for k in GRAPHS for d in DIRECTIONS for w in reference.WEIGHTS]


@pytest.mark.parametrize(("series", "kind", "directed", "weighted"), CASES)
def test_edges_match_reference(lanes, inputs, series, kind, directed, weighted):
    want = expected(series, kind, directed, weighted)
    for lane in ["native", "js"]:
        got = parse_edges(run(lanes[lane], inputs[series], *options(kind, directed, weighted)))
        assert got == want, lane


@pytest.mark.parametrize(("series", "kind", "directed"), [(s, k, d) for s in SERIES for k in GRAPHS for d in DIRECTIONS])
def test_degrees_match_reference(lanes, inputs, series, kind, directed):
    ts = SERIES[series]
    degrees, ks, cs = degree_counts(reference_edges(series, kind, directed, None), len(ts))
    args = options(kind, directed, None)
    shares = [bits(np.float32(c) / np.float32(len(ts))) for c in cs]
    assert run(lanes["native"], inputs[series], *args, "-m", "ds").split() == [str(d) for d in degrees]
    assert run(lanes["native"], inputs[series], *args, "-m", "dc").split() == [str(v) for kc in zip(ks, cs) for v in kc]
    dd = run(lanes["native"], inputs[series], *args, "-m", "dd").split()
    assert [int(k) for k in dd[0::2]] == list(ks)
    assert [bits(p) for p in dd[1::2]] == shares


# Against ts2vg, which computes in float64 from the same float32 values.


@pytest.mark.parametrize(("series", "kind", "directed"), [(s, k, d) for s in SERIES for k in GRAPHS for d in DIRECTIONS])
def test_unweighted_edges_match_ts2vg(lanes, inputs, series, kind, directed):
    g = GRAPHS[kind](directed=directed).build(SERIES[series].astype(np.float64))
    got = parse_edges(run(lanes["native"], inputs[series], *options(kind, directed, None)))
    assert [(s, t) for s, t, _ in got] == sorted(map(tuple, g.edges))


@pytest.mark.parametrize(("series", "kind", "weighted"), [(s, k, w) for s in SERIES for k in GRAPHS for w in reference.WEIGHTS[1:]])
def test_weights_match_ts2vg(lanes, inputs, series, kind, weighted):
    g = GRAPHS[kind](weighted=weighted).build(SERIES[series].astype(np.float64))
    text = run(lanes["native"], inputs[series], *options(kind, None, weighted))
    got = sorted((int(s), int(t), float(w)) for s, t, w in (line.split() for line in text.splitlines()))
    want = sorted((s, t, w) for s, t, w in g.edges)
    assert [e[:2] for e in got] == [e[:2] for e in want]
    np.testing.assert_allclose([e[2] for e in got], [e[2] for e in want], rtol=1e-6, atol=0)


def test_rejects_too_many_values(lanes, tmp_path):
    path = tmp_path / "long.txt"
    path.write_text("1\n" * (2**24 + 1))
    # A constant series is the slowest to build: without the refusal, the
    # timeout fails the test instead of letting it run for hours.
    done = subprocess.run([*lanes["native"], str(path)], capture_output=True, text=True, timeout=120)
    assert done.returncode == 1
    assert "at most 16777216 values" in done.stderr


def test_rejects_weighted_degrees(lanes, inputs):
    done = subprocess.run([*lanes["native"], str(inputs["sample"]), "-w", "distance", "-m", "ds"], capture_output=True, text=True)
    assert done.returncode == 1
    assert "only_degrees" in done.stderr


PENETRABLE_WEIGHTS = [None, "distance", "slope", "angle", "num_penetrations"]
PENETRABLE_SERIES = [s for s in SERIES if len(SERIES[s]) <= 500]


@functools.cache
def penetrable_edges(series, kind, directed, weighted, limit):
    return reference.build_penetrable(SERIES[series], kind, directed, weighted, limit)


@pytest.mark.parametrize(
    ("series", "kind", "directed", "weighted", "limit"),
    [(s, k, d, w, p) for s in PENETRABLE_SERIES for k in GRAPHS for d in DIRECTIONS for w in PENETRABLE_WEIGHTS for p in [1, 3]],
)
def test_penetrable_edges_match_reference(lanes, inputs, series, kind, directed, weighted, limit):
    want = sorted((s, t, bits(w) if weighted else None) for s, t, w in penetrable_edges(series, kind, directed, weighted, limit))
    for lane in ["native", "js"]:
        got = parse_edges(run(lanes[lane], inputs[series], *options(kind, directed, weighted), "-p", str(limit)))
        assert got == want, lane


@pytest.mark.parametrize(("series", "kind", "limit"), [(s, k, p) for s in PENETRABLE_SERIES for k in GRAPHS for p in [1, 3]])
def test_penetrable_edges_match_ts2vg(lanes, inputs, series, kind, limit):
    g = GRAPHS[kind](penetrable_limit=limit, weighted="num_penetrations").build(SERIES[series].astype(np.float64))
    text = run(lanes["native"], inputs[series], *options(kind, None, "num_penetrations"), "-p", str(limit))
    got = sorted((int(s), int(t), float(w)) for s, t, w in (line.split() for line in text.splitlines()))
    assert got == sorted((s, t, w) for s, t, w in g.edges)


# Irregular x coordinates, as ts2vg's build(ts, xs).

XS_SERIES = ["sample_2", "flat", "nans", "noise_nans", "white_noise", "brownian", "small_ints", "sine_noise"]


def _xs(kind, n):
    rng = np.random.default_rng(len(kind) + n)
    if kind == "gaps":
        xs = np.cumsum(0.5 + rng.random(n))
    elif kind == "spread":
        xs = np.cumsum(0.05 + rng.exponential(3.0, n))
    else:
        xs = -500 + np.cumsum(0.25 + rng.random(n))
    return xs.astype(np.float32)


XS = {(s, k): _xs(k, len(SERIES[s])) for s in XS_SERIES for k in ["gaps", "spread", "negative"]}


@pytest.fixture(scope="session")
def xs_inputs(tmp_path_factory):
    out = tmp_path_factory.mktemp("xs")
    paths = {}
    for (series, kind), xs in XS.items():
        paths[series, kind] = out / f"{series}_{kind}.txt"
        paths[series, kind].write_text("".join(np.format_float_positional(v, unique=True) + "\n" for v in xs))
    return paths


@pytest.mark.parametrize(
    ("series", "xs", "kind", "directed", "weighted"),
    [(s, x, k, d, w) for s, x in XS for k in GRAPHS for d in DIRECTIONS for w in [None, "distance", "h_distance", "slope", "angle"]],
)
def test_xs_edges_match_reference(lanes, inputs, xs_inputs, series, xs, kind, directed, weighted):
    edges = reference.build(SERIES[series], kind, directed, weighted, xs=XS[series, xs])
    want = sorted((s, t, bits(w) if weighted else None) for s, t, w in edges)
    for lane in ["native", "js"]:
        got = parse_edges(run(lanes[lane], inputs[series], "-x", xs_inputs[series, xs], *options(kind, directed, weighted)))
        assert got == want, lane


@pytest.mark.parametrize(("series", "xs", "kind"), [(s, x, k) for s, x in XS for k in GRAPHS])
def test_xs_edges_match_ts2vg(lanes, inputs, xs_inputs, series, xs, kind):
    g = GRAPHS[kind]().build(SERIES[series].astype(np.float64), xs=XS[series, xs].astype(np.float64))
    got = parse_edges(run(lanes["native"], inputs[series], "-x", xs_inputs[series, xs], "-t", kind))
    assert [(s, t) for s, t, _ in got] == sorted(map(tuple, g.edges))


@pytest.mark.parametrize(
    ("series", "xs", "kind", "weighted", "limit"),
    [(s, x, k, w, p) for s, x in XS if len(SERIES[s]) <= 500 for k in GRAPHS for w in [None, "distance", "num_penetrations"] for p in [1, 3]],
)
def test_xs_penetrable_edges_match_reference(lanes, inputs, xs_inputs, series, xs, kind, weighted, limit):
    edges = reference.build_penetrable(SERIES[series], kind, None, weighted, limit, xs=XS[series, xs])
    want = sorted((s, t, bits(w) if weighted else None) for s, t, w in edges)
    for lane in ["native", "js"]:
        got = parse_edges(run(lanes[lane], inputs[series], "-x", xs_inputs[series, xs], *options(kind, None, weighted), "-p", str(limit)))
        assert got == want, lane


@pytest.mark.parametrize(("xs", "error"), [("1\n2\n3\n", "hold 3 values and the series 4"), ("1\n2\n2\n3\n", "must increase"), ("1\n3\n2\n4\n", "must increase"), ("1\n2\nx\n4\n", "line 3 of the x coordinates")])
def test_xs_rejects_bad_coordinates(lanes, inputs, tmp_path, xs, error):
    path = tmp_path / "xs.txt"
    path.write_text(xs)
    done = subprocess.run([*lanes["native"], str(inputs["sample"]), "-x", str(path)], capture_output=True, text=True)
    assert done.returncode == 1
    assert error in done.stderr


# The one-thread build, which a program can use without relying on @unsafe.


@pytest.mark.parametrize("driver", ["tests/one_thread.bend", "tests/library.bend"])
def test_safe_drivers_check_clean(driver):
    env = {**os.environ, "BEND_NO_TELEMETRY": "1"}
    done = subprocess.run([BEND, driver, "--check-only"], cwd=ROOT, env=env, capture_output=True, text=True)
    assert done.returncode == 0, done.stdout + done.stderr
    assert "ALL PROOFS CHECK" in done.stdout


@pytest.mark.parametrize(("series", "kind"), [(s, k) for s in SERIES for k in GRAPHS])
def test_one_thread_edges_match_reference(one_thread, inputs, series, kind):
    want = expected(series, kind, None, None)
    for lane in ["native", "js"]:
        assert parse_edges(run(one_thread[lane], inputs[series], kind)) == want, lane


@pytest.mark.parametrize("kind", GRAPHS)
def test_one_thread_penetrable_edges_match_reference(one_thread, inputs, kind):
    want = sorted((s, t, None) for s, t, _ in penetrable_edges("noise_nans", kind, None, None, 3))
    for lane in ["native", "js"]:
        assert parse_edges(run(one_thread[lane], inputs["noise_nans"], kind, "3")) == want, lane


@pytest.mark.parametrize(("kind", "limit"), [(k, p) for k in GRAPHS for p in [0, 2]])
def test_one_thread_xs_edges_match_reference(one_thread, inputs, xs_inputs, kind, limit):
    xs = XS["noise_nans", "spread"]
    if limit:
        edges = reference.build_penetrable(SERIES["noise_nans"], kind, None, None, limit, xs=xs)
    else:
        edges = reference.build(SERIES["noise_nans"], kind, xs=xs)
    want = sorted((s, t, None) for s, t, _ in edges)
    for lane in ["native", "js"]:
        assert parse_edges(run(one_thread[lane], inputs["noise_nans"], kind, str(limit), xs_inputs["noise_nans", "spread"])) == want, lane


# What the library reads off the edges: a fold, the degrees, the rows.


def rows(edges, n, directed):
    out = [[] for _ in range(n)]
    for s, t, w in edges:
        out[s].append((t, bits(w)))
        if not directed:
            out[t].append((s, bits(w)))
    return [sorted(r) for r in out]


@pytest.mark.parametrize(("series", "kind", "directed"), [(s, k, d) for s in SERIES for k in GRAPHS for d in DIRECTIONS])
def test_library_outputs_match_ts2vg(library, inputs, series, kind, directed):
    ts = SERIES[series]
    n = len(ts)
    g = GRAPHS[kind](directed=directed, weighted="distance").build(ts.astype(np.float64))
    want_rows = rows(reference_edges(series, kind, directed, "distance"), n, directed)
    for lane in ["native", "js"]:
        lines = dict(line.split(" ", 1) if " " in line else (line, "") for line in run(library[lane], inputs[series], kind, directed or "undirected").splitlines())
        m, ends = map(int, lines["f"].split())
        assert m == len(g.edges), lane
        assert ends == sum(e[0] + e[1] for e in g.edges) % 2**32, lane
        assert [int(d) for d in lines["d"].split()] == list(g.degrees), lane
        offsets = [int(o) for o in lines["o"].split()]
        targets = [int(t) for t in lines["t"].split()]
        weights = [bits(w) for w in lines["w"].split()]
        got_rows = [list(zip(targets[a:b], weights[a:b])) for a, b in zip(offsets, offsets[1:])]
        assert got_rows == want_rows, lane


# Bounds on the weights: ts2vg keeps an edge whose weight lies strictly
# between min_weight and max_weight. Each bound here is the weight of an
# edge, which the bounds must drop.

BOUND_SERIES = ["sample_2", "white_noise", "small_ints", "sine_noise", "noise_infs"]


def f32_text(v):
    return np.format_float_positional(np.float32(v), unique=True)


@pytest.mark.parametrize(("series", "kind", "directed"), [(s, k, d) for s in BOUND_SERIES for k in GRAPHS for d in DIRECTIONS])
def test_library_weight_bounds_match_reference(library, inputs, series, kind, directed):
    ts = SERIES[series]
    ws = sorted({w for _, _, w in reference_edges(series, kind, directed, "distance") if np.isfinite(w)})
    lo, hi = ws[len(ws) // 4], ws[3 * len(ws) // 4]
    edges = reference.build(ts, kind, directed, "distance", min_weight=lo, max_weight=hi)
    assert not any(w == lo or w == hi for _, _, w in edges)
    want_rows = rows(edges, len(ts), directed)
    for lane in ["native", "js"]:
        lines = dict(line.split(" ", 1) if " " in line else (line, "") for line in run(library[lane], inputs[series], kind, directed or "undirected", f32_text(lo), f32_text(hi)).splitlines())
        assert int(lines["f"].split()[0]) == len(edges), lane
        offsets = [int(o) for o in lines["o"].split()]
        targets = [int(t) for t in lines["t"].split()]
        weights = [bits(w) for w in lines["w"].split()]
        assert [list(zip(targets[a:b], weights[a:b])) for a, b in zip(offsets, offsets[1:])] == want_rows, lane


# The benchmark's driver measures only the graph it was asked for.


@pytest.mark.parametrize(
    ("args", "code", "error"),
    [
        (["linear"], 2, "natural or horizontal"),
        (["natural", "two"], 2, "LIMIT is a whole number"),
        (["natural", "-1"], 2, "LIMIT is a whole number"),
        (["natural", "0", "1\n2\nx\n4\n"], 1, "line 3 of the x coordinates"),
        (["natural", "0", "1\n2\n3\n"], 1, "hold 3 values and the series 4"),
        (["natural", "0", "1\n2\n2\n3\n"], 1, "must increase"),
        (["horizontal", "1", "1\n3\n2\n4\n"], 1, "must increase"),
    ],
)
def test_bench_rejects_bad_arguments(builds, inputs, tmp_path, args, code, error):
    if len(args) == 3:
        (tmp_path / "xs.txt").write_text(args[2])
        args = [*args[:2], str(tmp_path / "xs.txt")]
    done = subprocess.run([str(builds / "bench"), str(inputs["sample"]), *args], capture_output=True, text=True)
    assert done.returncode == code
    assert error in done.stderr


# The sum of every edge's ends and every degree, which is the sum of the ends
# plus twice the edges.
def checksum_of(graphs):
    return sum(s + t + 2 for edges in graphs for s, t, _ in edges) % 2**32


# The bench prints the points, the edges, and the checksum.
@pytest.mark.parametrize(("series", "kind", "limit", "xs"), [("sample_2", "natural", 0, None), ("noise_nans", "horizontal", 2, "spread")])
def test_bench_counts_match_reference(builds, inputs, xs_inputs, series, kind, limit, xs):
    x = None if xs is None else XS[series, xs]
    if limit:
        edges = reference.build_penetrable(SERIES[series], kind, None, None, limit, xs=x)
    else:
        edges = reference.build(SERIES[series], kind, xs=x)
    args = [kind, str(limit)] + ([] if xs is None else [str(xs_inputs[series, xs])])
    done = subprocess.run([str(builds / "bench"), str(inputs[series]), *args], capture_output=True, text=True)
    assert done.returncode == 0, done.stderr
    n, m, checksum = map(int, done.stdout.split()[:3])
    assert (n, m, checksum) == (len(SERIES[series]), len(edges), checksum_of([edges]))


# The reference graph of each window of W values.
@functools.cache
def window_graphs(series, kind, w):
    ts = SERIES[series]
    return [reference.build(ts[k * w:(k + 1) * w], kind) for k in range(len(ts) // w)]


# The windows driver prints the windows, the edges, and the same checksum over
# every window's graph.
@pytest.mark.parametrize("mode", ["one", "par", "split"])
@pytest.mark.parametrize(("series", "kind", "w"), [("white_noise", "natural", 7), ("brownian", "horizontal", 100), ("noise_nans", "natural", 300)])
def test_windows_counts_match_reference(builds, inputs, series, kind, w, mode):
    graphs = window_graphs(series, kind, w)
    done = subprocess.run([str(builds / "windows"), str(inputs[series]), kind, str(w), mode], capture_output=True, text=True)
    assert done.returncode == 0, done.stderr
    assert tuple(map(int, done.stdout.split()[:3])) == (len(graphs), sum(len(edges) for edges in graphs), checksum_of(graphs))


@pytest.mark.parametrize(
    ("args", "code", "error"),
    [
        (["natural", "0", "one"], 1, "W must be at least 1"),
        (["natural", "5", "one"], 1, "W must be at least 1"),
        (["linear", "2", "one"], 2, "usage"),
        (["natural", "2", "fast"], 2, "usage"),
        (["natural", "two", "one"], 2, "usage"),
    ],
)
def test_windows_rejects_bad_arguments(builds, inputs, args, code, error):
    done = subprocess.run([str(builds / "windows"), str(inputs["sample"]), *args], capture_output=True, text=True)
    assert done.returncode == code
    assert error in done.stderr


# Long series: the JS lane's stack overflows on a recursion about as deep as
# the series.

LONG = {
    "white_noise_long": np.random.default_rng(0).standard_normal(100_000).astype(np.float32),
    "random_walk_long": np.cumsum(np.random.default_rng(0).standard_normal(100_000)).astype(np.float32),
}
LONG_RUNS = [
    ("white_noise_long", ["-t", "natural"]),
    ("white_noise_long", ["-t", "horizontal", "-d", "top_to_bottom", "-w", "slope"]),
    ("white_noise_long", ["-t", "natural", "-p", "2"]),
    ("random_walk_long", ["-t", "natural", "-w", "distance"]),
    ("random_walk_long", ["-t", "horizontal"]),
    ("random_walk_long", ["-t", "horizontal", "-p", "2"]),
    ("random_walk_long", ["-t", "natural", "-m", "ds"]),
    ("random_walk_long", ["-t", "horizontal", "-m", "dd"]),
]


@pytest.fixture(scope="session")
def long_inputs(tmp_path_factory):
    out = tmp_path_factory.mktemp("long")
    for name, ts in LONG.items():
        (out / f"{name}.txt").write_text("".join(np.format_float_positional(v, unique=True) + "\n" for v in ts))
    return {name: out / f"{name}.txt" for name in LONG}


@pytest.mark.parametrize(("series", "args"), LONG_RUNS)
def test_js_lane_matches_native_on_long_series(lanes, long_inputs, series, args):
    native, js = (run(lanes[lane], long_inputs[series], *args) for lane in ["native", "js"])
    if "-m" in args:
        assert js.split() == native.split()
    else:
        assert parse_edges(js) == parse_edges(native)


@pytest.mark.parametrize(("series", "kind"), [(s, k) for s in LONG for k in GRAPHS])
def test_one_thread_matches_parallel_on_long_series(lanes, one_thread, long_inputs, series, kind):
    want = parse_edges(run(lanes["native"], long_inputs[series], "-t", kind))
    for lane in ["native", "js"]:
        assert parse_edges(run(one_thread[lane], long_inputs[series], kind)) == want, lane
