# bend-vg against ts2vg

`bench/run.py` times one build of each graph, unweighted and undirected,
on float32 series with a seed of 0. ts2vg's `build` makes the edge list
and the degrees, and `only_degrees` skips the list. bend-vg's time covers
the edges, a walk over them, and the degrees, from `bench/bench.bend`.
Each time is the best of 5 runs, in ms, with the series already in memory.

The machine is an AMD Ryzen Threadripper 7970X (32 cores, 64 threads),
with Bend 2.0.37 and ts2vg 1.2.4 on Python 3.12. Other jobs held a load of
about 4 during the runs.

## Natural and horizontal graphs

`uv run python bench/run.py`:

| graph | series | n | edges (ts2vg / bend-vg if they differ) | ts2vg build | ts2vg only_degrees | bend-vg 1T | bend-vg 8T | bend-vg 64T |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| natural | white_noise | 10,000 | 29,322 | 3 | 1 | 1 | 1 | 3 |
| natural | white_noise | 100,000 | 294,835 | 49 | 12 | 11 | 6 | 6 |
| natural | white_noise | 1,000,000 | 2,951,201 | 569 | 148 | 128 | 42 | 31 |
| natural | random_walk | 10,000 | 103,708 | 18 | 10 | 6 | 2 | 4 |
| natural | random_walk | 100,000 | 1,062,543 / 1,062,541 | 285 | 153 | 74 | 18 | 10 |
| natural | random_walk | 1,000,000 | 12,752,617 / 12,752,619 | 7408 | 5357 | 2149 | 320 | 107 |
| horizontal | white_noise | 10,000 | 19,979 | 2 | 0 | 1 | 1 | 3 |
| horizontal | white_noise | 100,000 | 199,974 | 24 | 5 | 9 | 5 | 6 |
| horizontal | white_noise | 1,000,000 | 1,999,970 | 333 | 56 | 107 | 40 | 30 |
| horizontal | random_walk | 10,000 | 19,843 | 3 | 2 | 4 | 1 | 3 |
| horizontal | random_walk | 100,000 | 199,323 | 58 | 38 | 69 | 14 | 7 |
| horizontal | random_walk | 1,000,000 | 1,997,907 | 1620 | 1336 | 2530 | 378 | 77 |

On one thread, bend-vg builds every natural graph as fast as ts2vg's
Cython kernel (`only_degrees`) or faster: 2.5 times faster on the random
walk of 1,000,000 points. It takes about twice as long as the kernel on the
horizontal graphs from 100,000 points, whose sweep does only a comparison
per point.

With 64 threads, bend-vg builds the graphs of 1,000,000 points 11 to 69
times faster than ts2vg's `build`: 31 ms against 569 for the natural graph
of white noise, and 107 ms against 7408 for that of the random walk. At
10,000 points, 64 threads take longer than 8.

## How the build splits

ts2vg's divide and conquer takes an interval's first highest point as its
pivot, sweeps the interval from it, and recurses on the two sides. Every
point is the pivot of one interval. The interval starts after the nearest
earlier point that the pivot does not beat, and ends before the nearest
later point that beats it. bend-vg finds these bounds for every point with
one pass over a stack. After that pass, no sweep waits on another.

bend-vg cuts the points into about 1,024 chunks of equal work, where the
work counts the points that the sweeps visit. A fork tree of 512 leaves
runs the chunks. The leaves read x and y from arrays that they share
through Base's `Array.fork`. Base marks `Array.fork` `@unsafe` because two
handles can write the same cells. The leaves only read.

The stack pass runs on one thread and takes 16 ms at 1,000,000 points,
about half of the white noise's 31 ms on 64 threads. It is the largest
serial part left. The sweeps scale up to the 32 cores, and the second
thread of each core adds little.

Bend's runtime first grows the fork tree on a few threads, then spreads
the tasks of defs that fork nothing over every thread. Work that a task
does before it forks runs while the tree grows. A first version swept in
the tree's last fork. It kept 8 of 64 threads busy, and its edges of the
random walk of 1,000,000 points took 337 ms instead of 133. So `leaf` forks nothing, and
`Report.degrees` walks the edges the same way, with atomic adds.

## The limited penetrable graphs

`uv run python bench/run.py --sizes 10000 50000 --limit 1` builds the
graphs whose edges may cross one point:

| graph | series | n | edges (ts2vg / bend-vg if they differ) | ts2vg build | ts2vg only_degrees | bend-vg 1T | bend-vg 8T | bend-vg 64T |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| natural | white_noise | 10,000 | 58,886 | 166 | 162 | 527 | 73 | 27 |
| natural | white_noise | 50,000 | 296,409 | 3943 | 3899 | 12954 | 1765 | 530 |
| natural | random_walk | 10,000 | 198,207 | 177 | 156 | 546 | 74 | 28 |
| natural | random_walk | 50,000 | 962,935 | 4188 | 4047 | 13145 | 1782 | 547 |
| horizontal | white_noise | 10,000 | 39,937 | 3 | 1 | 4 | 2 | 4 |
| horizontal | white_noise | 50,000 | 199,923 | 23 | 4 | 24 | 9 | 9 |
| horizontal | random_walk | 10,000 | 39,597 | 3 | 1 | 15 | 4 | 6 |
| horizontal | random_walk | 50,000 | 198,796 | 26 | 8 | 102 | 23 | 19 |

Every point of the natural graph sweeps all the points right of it, so
the work grows as n², and the sweeps are independent. bend-vg splits the
start points into 128 ranges of equal work. On one thread it takes 3
times as long as ts2vg; on 64 threads it runs 7 to 8 times faster than
ts2vg at 50,000 points. A horizontal sweep stops once `limit + 1` points
higher than its start block the view, so that graph has little work to
split, and ts2vg's `only_degrees` stays faster.

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
