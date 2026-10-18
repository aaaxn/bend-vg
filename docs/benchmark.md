# bend-vg against ts2vg

`bench/run.py` times one build of each graph, unweighted and undirected,
on float32 series with a seed of 0. ts2vg's `build` makes the edge list
and the degrees, and `only_degrees` skips the list. bend-vg's time covers
the edges, a walk over them, and the degrees, from `bench/bench.bend`.
Each time is the best of 5 runs, in ms, with the series already in memory.

The machine is an AMD Ryzen Threadripper 7970X (32 cores, 64 threads),
with Bend 2.0.37 and ts2vg 1.2.4 on Python 3.12. Other jobs held a load of
2 to 9 during the runs.

## The divide and conquer

`uv run python bench/run.py`:

| graph | series | n | edges (ts2vg / bend-vg if they differ) | ts2vg build | ts2vg only_degrees | bend-vg 1T | bend-vg 8T | bend-vg 64T |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| natural | white_noise | 10,000 | 29,322 | 3 | 1 | 2 | 2 | 4 |
| natural | white_noise | 100,000 | 294,835 | 50 | 13 | 21 | 17 | 17 |
| natural | white_noise | 1,000,000 | 2,951,201 | 564 | 141 | 379 | 275 | 277 |
| natural | random_walk | 10,000 | 103,708 | 18 | 9 | 10 | 10 | 12 |
| natural | random_walk | 100,000 | 1,062,543 / 1,062,541 | 292 | 155 | 150 | 123 | 122 |
| natural | random_walk | 1,000,000 | 12,752,617 / 12,752,619 | 7305 | 5365 | 4438 | 3172 | 3219 |
| horizontal | white_noise | 10,000 | 19,979 | 2 | 0 | 2 | 1 | 4 |
| horizontal | white_noise | 100,000 | 199,974 | 23 | 5 | 18 | 15 | 14 |
| horizontal | white_noise | 1,000,000 | 1,999,970 | 348 | 56 | 328 | 268 | 255 |
| horizontal | random_walk | 10,000 | 19,843 | 3 | 2 | 9 | 9 | 12 |
| horizontal | random_walk | 100,000 | 199,323 | 58 | 38 | 131 | 111 | 105 |
| horizontal | random_walk | 1,000,000 | 1,997,907 | 1650 | 1371 | 4834 | 3450 | 3838 |

On one thread, bend-vg matches ts2vg's Cython kernel (`only_degrees`) on
the natural graph of a random walk of 100,000 points, and beats it at
1,000,000: 4.4 s against 5.4 s. On the other rows it takes 1.1 to 6 times
as long. It walks linked lists and allocates a node for each point it moves,
where the kernel reads an array. The gap is widest on the horizontal graph,
whose sweep does only a comparison per point. The natural sweep does more
per point, and there bend-vg does less than ts2vg: it computes the
tolerance only for a slope above the running maximum, in F32, where ts2vg
computes it at every point, in float64.

With 64 threads, bend-vg builds the natural graph of 1,000,000 points in
about half the time of ts2vg's `build`, and the horizontal graph of white
noise in about three quarters. The random walk's horizontal graph stays
slower than ts2vg's.

## Why more threads help little

The divide and conquer runs an interval's argmax and sweeps on one core:
each sweep is a scan whose running maximum moves only by more than the
tolerance, and that step is not associative. So the time is bounded below
by the heaviest chain of nested intervals. `bench/critical_path.py`
measures it on the same series. It counts an interval of L points as L,
and runs an interval's sweeps before its children start, as bend-vg does:

| series, n = 1,000,000 | work | critical path | best speedup on any number of cores | with cores split evenly at each fork, 64 cores |
| --- | --- | --- | --- | --- |
| white_noise | 26.3 n | 4.86 n | 5.42 | 3.38 |
| random_walk | 1325.8 n | 810.58 n | 1.64 | 1.01 |

Bend's scheduler splits the cores evenly at each fork and never moves a
task, and the pivot splits intervals unevenly, so bend-vg can reach at
most the even-split column. From 1 to 64 threads it gets 1.4 times on
both natural graphs of 1,000,000 points, edges and degrees together. The
random walk's 1.4 beats the model's 1.01, so the model's cost of L per
interval only approximates bend-vg's. A scheduler that balanced the forks
could reach the best-speedup column. Running an interval's sweeps
alongside its children, which need only its pivot, would raise both
bounds.

## The limited penetrable graphs

`uv run python bench/run.py --sizes 10000 50000 --limit 1` builds the
graphs whose edges may cross one point:

| graph | series | n | edges (ts2vg / bend-vg if they differ) | ts2vg build | ts2vg only_degrees | bend-vg 1T | bend-vg 8T | bend-vg 64T |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| natural | white_noise | 10,000 | 58,886 | 169 | 166 | 495 | 69 | 26 |
| natural | white_noise | 50,000 | 296,409 | 4018 | 4030 | 12690 | 1654 | 523 |
| natural | random_walk | 10,000 | 198,207 | 186 | 165 | 510 | 71 | 31 |
| natural | random_walk | 50,000 | 962,935 | 4313 | 4073 | 12348 | 1661 | 572 |
| horizontal | white_noise | 10,000 | 39,937 | 3 | 1 | 5 | 3 | 5 |
| horizontal | white_noise | 50,000 | 199,923 | 23 | 4 | 24 | 12 | 13 |
| horizontal | random_walk | 10,000 | 39,597 | 3 | 1 | 15 | 4 | 5 |
| horizontal | random_walk | 50,000 | 198,796 | 27 | 8 | 101 | 24 | 22 |

Every point of the natural graph sweeps all the points right of it, so
the work grows as n², and the sweeps are independent. bend-vg splits the
start points into 128 ranges of equal work. On one thread it takes 3
times as long as ts2vg; on 64 threads it runs 7 to 8 times faster than
ts2vg at 50,000 points. A horizontal sweep stops once `limit + 1` points
higher than its start block the view, so that graph has little work to
split, and ts2vg stays faster.

## Edges that differ

Every horizontal graph, every penetrable graph above, and the natural
graphs of white noise equal ts2vg's edge for edge. The natural graphs of
the random walks differ in 2 edges of about 1.06 million at 100,000
points, and in 24 of about 12.75 million at 1,000,000. Exact rational
arithmetic finds every differing edge visible. At 100,000 points ts2vg
finds both and bend-vg misses them; at 1,000,000 points bend-vg misses 11
that ts2vg finds, and ts2vg misses 13 that bend-vg finds. Neither is
exact: bend-vg rounds slopes to 24 bits, and ts2vg rounds them to 53 bits
and also rejects a slope that exceeds the running maximum by less than
its tolerance, 1e-14 times the largest coordinate. On the 100,000-point
walk, bend-vg matches `tests/reference.py` edge for edge.
