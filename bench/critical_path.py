"""How far ts2vg's divide and conquer can run in parallel on a series.

    uv run python bench/critical_path.py [n] [white_noise|random_walk]

An interval of L points costs L: its argmax and its two sweeps each walk
it once. The sweeps are scans whose running maximum moves only by more
than the tolerance, which is not associative, so an interval runs on one
core. The work is the sum over all intervals; the critical path is the
heaviest chain from the whole series down to one point. `even` splits the
cores evenly at every fork, as Bend's scheduler does; `ideal` is the best
any scheduler can do, work / max(work / P, critical path).
"""

import sys

import numpy as np


def cartesian_tree(ts):
    """Children of each point in the tree of first maxima, and the root."""
    n = len(ts)
    left = np.full(n, -1)
    right = np.full(n, -1)
    stack = []
    for i in range(n):
        last = -1
        while stack and ts[stack[-1]] < ts[i]:
            last = stack.pop()
        left[i] = last
        if stack:
            right[stack[-1]] = i
        stack.append(i)
    return left, right, stack[0]


def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 1_000_000
    kind = sys.argv[2] if len(sys.argv) > 2 else "white_noise"
    noise = np.random.default_rng(0).standard_normal(n)
    ts = (noise if kind == "white_noise" else np.cumsum(noise)).astype(np.float32)
    left, right, root = cartesian_tree(ts)

    order, stack = [], [root]
    while stack:
        v = stack.pop()
        order.append(v)
        stack.extend(c for c in (left[v], right[v]) if c >= 0)
    size = np.zeros(n, dtype=np.int64)
    work = np.zeros(n, dtype=np.int64)
    path = np.zeros(n, dtype=np.int64)
    for v in reversed(order):
        kids = [c for c in (left[v], right[v]) if c >= 0]
        size[v] = 1 + sum(size[c] for c in kids)
        work[v] = size[v] + sum(work[c] for c in kids)
        path[v] = size[v] + max((path[c] for c in kids), default=0)

    def even(v, cores):
        own = 0
        while True:
            kids = [c for c in (left[v], right[v]) if c >= 0]
            if cores == 1 or not kids:
                return own + work[v]
            if len(kids) == 2:
                return own + size[v] + max(even(kids[0], cores // 2), even(kids[1], cores - cores // 2))
            own += size[v]
            v = kids[0]

    total, span = work[root], path[root]
    print(f"{kind}, n = {n:,}: work {total / n:.1f} n, critical path {span / n:.2f} n")
    print("| cores | even split | ideal |")
    print("| --- | --- | --- |")
    for cores in [1, 2, 8, 64]:
        print(f"| {cores} | {total / even(root, cores):.2f} | {total / max(total / cores, span):.2f} |")


if __name__ == "__main__":
    main()
