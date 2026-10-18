# bend-vg against ts2vg

`bench/run.py` times one build of each graph, unweighted and undirected,
on float32 series with a seed of 0. ts2vg's `build` makes the edge list
and the degrees, and `only_degrees` skips the list. bend-vg's time covers
the edges, a walk over them, and the degrees, from `bench/bench.bend`.
Each time is the best of 5 runs, in ms, with the series already in memory.

The machine is an AMD Ryzen Threadripper 7970X (32 cores, 64 threads),
with Bend 2.0.37 and ts2vg 1.2.4 on Python 3.12. Other jobs held a load of
about 5 during the runs.

| graph | series | n | edges (ts2vg / bend-vg if they differ) | ts2vg build | ts2vg only_degrees | bend-vg 1T | bend-vg 8T | bend-vg 64T |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| natural | white_noise | 10,000 | 29,322 | 3 | 1 | 4 | 3 | 4 |
| natural | white_noise | 100,000 | 294,835 | 50 | 12 | 40 | 27 | 24 |
| natural | white_noise | 1,000,000 | 2,951,201 | 582 | 156 | 697 | 428 | 359 |
| natural | random_walk | 10,000 | 103,708 | 18 | 9 | 33 | 35 | 37 |
| natural | random_walk | 100,000 | 1,062,543 / 1,062,541 | 294 | 160 | 483 | 367 | 366 |
| natural | random_walk | 1,000,000 | 12,752,617 / 12,752,619 | 7579 | 5361 | 20153 | 17446 | 16673 |
| horizontal | white_noise | 10,000 | 19,979 | 1 | 0 | 3 | 3 | 4 |
| horizontal | white_noise | 100,000 | 199,974 | 24 | 5 | 33 | 34 | 22 |
| horizontal | white_noise | 1,000,000 | 1,999,970 | 354 | 61 | 605 | 386 | 336 |
| horizontal | random_walk | 10,000 | 19,843 | 3 | 2 | 30 | 31 | 34 |
| horizontal | random_walk | 100,000 | 199,323 | 55 | 36 | 433 | 314 | 337 |
| horizontal | random_walk | 1,000,000 | 1,997,907 | 1633 | 1381 | 18862 | 16518 | 15575 |

On one thread, bend-vg takes 4 to 14 times as long as ts2vg's Cython
kernel (`only_degrees`). It walks linked lists and allocates a node for each
point it moves, where the kernel reads an array; the gap is widest on the
horizontal graph, whose sweep does only a comparison per point. With 64
threads, bend-vg beats ts2vg's `build` only on white noise of 100,000
points or more, and there most of `build`'s time goes to Python tuples.

## Why more threads help little

The divide and conquer runs an interval's argmax and sweeps on one core:
each sweep is a scan whose running maximum moves only by more than the
tolerance, and that step is not associative. So the time is bounded below
by the heaviest chain of nested intervals. `bench/critical_path.py`
measures it on the same series, counting an interval of L points as L:

| series, n = 1,000,000 | work | critical path | best speedup on any number of cores | with cores split evenly at each fork, 64 cores |
| --- | --- | --- | --- | --- |
| white_noise | 26.3 n | 4.86 n | 5.42 | 3.38 |
| random_walk | 1325.8 n | 810.58 n | 1.64 | 1.01 |

Bend's scheduler splits the cores evenly at each fork and never moves a
task, and the pivot splits intervals unevenly, so bend-vg gets the even-split
column: 3.2 times on white noise and 1.2 on the random walk. A scheduler
that balanced the forks could reach the other column, and no more.

## Edges that differ

Every horizontal graph and the natural graphs of white noise equal
ts2vg's edge for edge. The natural graphs of the random walks differ in 2
edges of about 1.06 million at 100,000 points, and in 24 of about 12.75
million at 1,000,000. Exact rational arithmetic finds every differing edge
visible. At 100,000 points ts2vg finds both and bend-vg misses them; at
1,000,000 points bend-vg misses 11 that ts2vg finds, and ts2vg misses 13
that bend-vg finds. Neither is exact: bend-vg rounds slopes to 24 bits,
and ts2vg rounds them to 53 bits and also rejects a slope that exceeds the
running maximum by less than its tolerance, 1e-14 times the largest
coordinate. On the 100,000-point walk, bend-vg matches
`tests/reference.py` edge for edge.
