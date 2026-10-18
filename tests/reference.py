"""ts2vg 1.2.4's graph kernels in float32: the same operations in the same order.

bend-vg must match this module bit for bit. Each function follows its Cython
twin in ts2vg/graph/; only the float type differs.
"""

import numpy as np

F = np.float32
ABS_TOL = F(1e-14)
REL_TOL = F(1e-14)
NAN = F(np.nan)

WEIGHTS = [
    None,
    "distance",
    "sq_distance",
    "v_distance",
    "abs_v_distance",
    "h_distance",
    "abs_h_distance",
    "slope",
    "abs_slope",
    "angle",
    "abs_angle",
    "num_penetrations",
]


def atan(s):
    """atan rounded once to float32. numpy's float32 arctan is not correctly
    rounded: it is one ulp off at the slope 0.32499999, which Bend gets right."""
    return F(np.arctan(np.float64(s)))


def weight(kind, x_a, x_b, y_a, y_b, slope):
    if kind is None or kind == "num_penetrations":
        return F(0)
    if kind == "distance":
        return np.sqrt(((x_b - x_a) * (x_b - x_a)) + ((y_b - y_a) * (y_b - y_a)))
    if kind == "sq_distance":
        return ((x_b - x_a) * (x_b - x_a)) + ((y_b - y_a) * (y_b - y_a))
    if kind == "v_distance":
        return y_b - y_a
    if kind == "abs_v_distance":
        return abs(y_b - y_a)
    if kind == "h_distance":
        return x_b - x_a
    if kind == "abs_h_distance":
        return abs(x_b - x_a)
    if np.isnan(slope):
        slope = (y_b - y_a) / (x_b - x_a)
    if kind == "slope":
        return slope
    if kind == "abs_slope":
        return abs(slope)
    if kind == "angle":
        return atan(slope)
    if kind == "abs_angle":
        return atan(abs(slope))
    raise ValueError(kind)


def _tol(x_a, x_b, y_a, y_b):
    return max(ABS_TOL, REL_TOL * max(abs(x_a), abs(x_b), abs(y_a), abs(y_b)))


def build(ts, kind="natural", directed=None, weighted=None, min_weight=-np.inf, max_weight=np.inf):
    """Edges (src, dst, w) of the graph of the float32 series `ts`, x = index."""
    ts = np.asarray(ts, dtype=F)
    n = len(ts)
    xs = np.arange(n, dtype=F)
    lo, hi = F(min_weight), F(max_weight)
    edges = []

    def add_edge(i1, i2, x1, x2, y1, y2, slope):
        w = weight(weighted, x1, x2, y1, y2, slope)
        if w <= lo or w >= hi:
            return
        edges.append((i1, i2, w))

    queue = [(0, n)]
    with np.errstate(all="ignore"):
        while queue:
            left, right = queue.pop(0)
            if left + 1 >= right:
                continue
            i = left + int(np.argmax(ts[left:right]))
            x_a, y_a = xs[i], ts[i]
            best = F(-np.inf)
            for d in range(1, i - left + 1):
                x_b, y_b = xs[i - d], ts[i - d]
                if kind == "natural":
                    slope = (y_b - y_a) / -(x_b - x_a)
                    seen = (slope - best) > _tol(x_a, x_b, y_a, y_b)
                    key, passed = slope, -slope
                else:
                    seen = y_b > best
                    key, passed = y_b, NAN
                if seen:
                    if directed == "top_to_bottom":
                        add_edge(i, i - d, x_a, x_b, y_a, y_b, passed)
                    else:
                        add_edge(i - d, i, x_b, x_a, y_b, y_a, passed)
                    best = key
            best = F(-np.inf)
            for d in range(1, right - i):
                x_b, y_b = xs[i + d], ts[i + d]
                if kind == "natural":
                    slope = (y_b - y_a) / (x_b - x_a)
                    seen = (slope - best) > _tol(x_a, x_b, y_a, y_b)
                    key, passed = slope, slope
                else:
                    seen = y_b > best
                    key, passed = y_b, NAN
                if seen:
                    add_edge(i, i + d, x_a, x_b, y_a, y_b, passed)
                    best = key
            queue.append((left, i))
            queue.append((i + 1, right))
    return edges
