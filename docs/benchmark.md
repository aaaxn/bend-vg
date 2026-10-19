# bend-vg against ts2vg

`bench/run.py` times one build of each graph, unweighted and undirected,
on float32 series with a seed of 0. ts2vg's `build` makes the edge list
and the degrees, and `only_degrees` skips the list. bend-vg's time covers
the edges, a walk over them, and the degrees, from `bench/bench.bend`.
Each time is the best of 5 runs, in ms, with the series already in memory:
for ts2vg as a numpy array, for bend-vg as an `Array<F32>`.

The machine is an AMD Ryzen Threadripper 7970X (32 cores, 64 threads),
with Bend 2.0.37 and ts2vg 1.2.4 on Python 3.12. Other jobs held a load of
4 to 6 during the runs.

## Natural and horizontal graphs

`uv run python bench/run.py`:

| graph | series | n | edges (ts2vg / bend-vg if they differ) | ts2vg build | ts2vg only_degrees | bend-vg 1T | bend-vg 8T | bend-vg 64T |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| natural | white_noise | 10,000 | 29,322 | 3 | 1 | 1 | 1 | 3 |
| natural | white_noise | 100,000 | 294,835 | 49 | 13 | 13 | 5 | 5 |
| natural | white_noise | 1,000,000 | 2,951,201 | 580 | 156 | 139 | 36 | 22 |
| natural | random_walk | 10,000 | 103,708 | 19 | 10 | 6 | 3 | 4 |
| natural | random_walk | 100,000 | 1,062,543 / 1,062,541 | 302 | 157 | 80 | 19 | 10 |
| natural | random_walk | 1,000,000 | 12,752,617 / 12,752,619 | 7647 | 5597 | 2240 | 318 | 101 |
| horizontal | white_noise | 10,000 | 19,979 | 2 | 0 | 1 | 1 | 3 |
| horizontal | white_noise | 100,000 | 199,974 | 25 | 5 | 11 | 4 | 5 |
| horizontal | white_noise | 1,000,000 | 1,999,970 | 338 | 59 | 115 | 32 | 20 |
| horizontal | random_walk | 10,000 | 19,843 | 4 | 3 | 5 | 1 | 3 |
| horizontal | random_walk | 100,000 | 199,323 | 58 | 39 | 74 | 13 | 6 |
| horizontal | random_walk | 1,000,000 | 1,997,907 | 1681 | 1393 | 2576 | 360 | 72 |

On one thread, bend-vg builds every natural graph as fast as ts2vg's
Cython kernel (`only_degrees`) or faster: 2.5 times faster on the random
walk of 1,000,000 points. It takes about twice as long as the kernel on the
horizontal graphs from 100,000 points, whose sweep does only a comparison
per point.

With 64 threads, bend-vg builds the graphs of 1,000,000 points 17 to 76
times faster than ts2vg's `build`: 22 ms against 580 for the natural graph
of white noise, and 101 ms against 7647 for that of the random walk. At
10,000 points, 64 threads take longer than 8.

## How the build splits

ts2vg's divide and conquer takes an interval's first highest point as its
pivot, sweeps the interval from it, and recurses on the two sides. Every
point is the pivot of one interval. The interval starts after the nearest
earlier point that the pivot does not beat, and ends before the nearest
later point that beats it. bend-vg finds these bounds for every point with
a stack. After that, no sweep waits on another.

The stack runs on blocks of about 2,000 points in parallel, each block with
a stack of its own points. A point that pops its block's whole stack, and a
NaN that opens a block, need the points before the block. A merge walks the
blocks in order with the stack of all the earlier points and bounds those
points. White noise leaves a few of them in each block. A rising series
leaves every point to the merge, which then does the work of one stack on
one thread.

bend-vg then cuts the points into about 1,024 chunks of equal work, where
the work counts the points that the sweeps visit. A fork tree of 512
leaves runs the chunks. The blocks and the leaves share the arrays of y and
of the counts through Base's `Array.fork`, and x is the index. Base marks
`Array.fork` `@unsafe` because two handles can write the same cell. Here no
two tasks write the same cell. `src/graph.bend`'s `build` runs the same
code on one thread, as one block and one chunk, without `Array.fork`.

On 64 threads, at 1,000,000 points of white noise, the blocks and the
merge take 3 to 4 ms of the 22. Another 3 to 4 ms go to allocating the two
arrays of counts, on one thread. On one thread, the blocks cost about 5 ms
more than one stack over the whole series. The sweeps scale up to the 32
cores, and the second thread of each core adds little.

Bend's runtime first grows the fork tree on a few threads, then spreads
the tasks of defs that fork nothing over every thread. Work that a task
does before it forks runs while the tree grows. A first version swept in
the tree's last fork. It kept 8 of 64 threads busy, and its edges of the
random walk of 1,000,000 points took 337 ms instead of 133. So `leaf` and
`block_leaf` fork nothing, and `src/parallel.bend`'s `degrees` walks the
edges the same way, with atomic adds.

## The limited penetrable graphs

`uv run python bench/run.py --sizes 10000 50000 --limit 1` builds the
graphs whose edges may cross one point:

| graph | series | n | edges (ts2vg / bend-vg if they differ) | ts2vg build | ts2vg only_degrees | bend-vg 1T | bend-vg 8T | bend-vg 64T |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| natural | white_noise | 10,000 | 58,886 | 168 | 164 | 148 | 22 | 7 |
| natural | white_noise | 50,000 | 296,409 | 4164 | 4125 | 3575 | 473 | 98 |
| natural | random_walk | 10,000 | 198,207 | 188 | 168 | 149 | 24 | 9 |
| natural | random_walk | 50,000 | 962,935 | 4300 | 4139 | 3617 | 482 | 104 |
| horizontal | white_noise | 10,000 | 39,937 | 3 | 1 | 3 | 2 | 4 |
| horizontal | white_noise | 50,000 | 199,923 | 22 | 4 | 17 | 9 | 10 |
| horizontal | random_walk | 10,000 | 39,597 | 3 | 1 | 5 | 2 | 4 |
| horizontal | random_walk | 50,000 | 198,796 | 26 | 8 | 34 | 11 | 10 |

Every point of the natural graph sweeps all the points right of it, so
the work grows as n², and the sweeps are independent. bend-vg splits the
start points into 128 ranges of equal work. On one thread it takes about
13% less time than ts2vg's kernel; on 64 threads it runs 41 to 42 times
faster than ts2vg's `build` at 50,000 points. A point the sweep sees
replaces the lowest of the `limit + 1` highest slopes at the next step, so
a step after a point it does not see compiles to a loop that calls
nothing. Updating them at once made every step push a continuation, and
the sweep took 3.6 times as long. A horizontal sweep stops once
`limit + 1` points higher than its start block the view, so that graph has
little work to split, and ts2vg's `only_degrees` stays faster.

## Irregular x

`uv run python bench/run.py --sizes 100000 1000000 --xs` gives the points
x coordinates that grow by 0.5 to 1.5, as ts2vg's `build(ts, xs)` takes
them:

| graph | series | n | edges (ts2vg / bend-vg if they differ) | ts2vg build | ts2vg only_degrees | bend-vg 1T | bend-vg 8T | bend-vg 64T |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| natural | white_noise | 100,000 | 295,177 | 48 | 12 | 13 | 5 | 5 |
| natural | white_noise | 1,000,000 | 2,953,547 / 2,953,548 | 573 | 147 | 140 | 38 | 22 |
| natural | random_walk | 100,000 | 1,061,811 | 295 | 148 | 82 | 19 | 10 |
| natural | random_walk | 1,000,000 | 12,750,305 / 12,750,298 | 7541 | 5572 | 2395 | 341 | 107 |
| horizontal | white_noise | 100,000 | 199,974 | 25 | 5 | 11 | 5 | 6 |
| horizontal | white_noise | 1,000,000 | 1,999,970 | 335 | 61 | 112 | 32 | 19 |
| horizontal | random_walk | 100,000 | 199,323 | 59 | 40 | 72 | 13 | 7 |
| horizontal | random_walk | 1,000,000 | 1,997,907 | 1694 | 1412 | 2698 | 367 | 67 |

The sweeps then read each x from an array instead of computing it from the
index. That costs up to 7% on one thread, on the random walks of
1,000,000 points, and nothing measurable on 64 threads.

## Edges against ts2vg

`bench/compare.py` builds each graph above with ts2vg and with bend-vg's
command line, and compares the two edge sets. For each edge that only one
of them has, it decides with integers, from the float32 values, whether
the edge crosses more than `limit` points. 24 of the 28 graphs are equal
edge for edge. These differ:

| graph | series | n | ts2vg edges | bend-vg edges | only in ts2vg | only in bend-vg |
| --- | --- | --- | --- | --- | --- | --- |
| natural | random_walk | 100,000 | 1,062,543 | 1,062,541 | 2 | 0 |
| natural | random_walk | 1,000,000 | 12,752,617 | 12,752,619 | 11 | 13 |
| natural, irregular x | white_noise | 1,000,000 | 2,953,547 | 2,953,548 | 0 | 1 |
| natural, irregular x | random_walk | 1,000,000 | 12,750,305 | 12,750,298 | 22 | 15 |

Every edge in the last two columns is in the graph: where three points
are nearly collinear, each tool misses edges that the other finds. bend-vg rounds slopes to 24 bits; ts2vg rounds them to 53 bits
and also rejects a slope that exceeds the running maximum by less than its
tolerance, 1e-14 times the largest coordinate. On the 100,000-point walk,
bend-vg matches `tests/reference.py`, ts2vg's kernels in float32, edge for
edge.
