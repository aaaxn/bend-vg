"""bend_vg against the float32 reference (bit for bit) and against ts2vg."""

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
JS_MAX_POINTS = 1000
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
def lanes(tmp_path_factory):
    # One build for every xdist worker: the first to take the lock builds.
    out = tmp_path_factory.getbasetemp().parent / "build"
    out.mkdir(exist_ok=True)
    env = {**os.environ, "BEND_NO_TELEMETRY": "1"}
    with open(out / "lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if not (out / "done").exists():
            for target in ["bend_vg", "bend_vg.js"]:
                subprocess.run([BEND, "bend_vg.bend", "-o", str(out / target)], cwd=ROOT, env=env, check=True)
            (out / "done").touch()
    return {"native": [str(out / "bend_vg")], "js": [BUN, str(out / "bend_vg.js")]}


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
    for lane in ["native", "js"] if len(SERIES[series]) <= JS_MAX_POINTS else ["native"]:
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
