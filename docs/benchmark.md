# bend-visgraph against ts2vg

`bench/run.py` times one build of each graph, unweighted and undirected,
on float32 series with a seed of 0. ts2vg's `build` makes the edge list
and the degrees, and `only_degrees` skips the list. bend-visgraph's time covers
the edges, a walk over them, and the degrees, from `bench/bench.bend`.
Each time is the best of 5 runs, in ms, with the series already in memory:
for ts2vg as a numpy array, for bend-visgraph as an `Array<F32>`.

The machine is an AMD Ryzen Threadripper 7970X (32 cores, 64 threads),
with Bend 2.0.37 and ts2vg 1.2.4 on Python 3.12, and on Python 3.13 for
the sections on many short series, threads and memory. Other jobs held a
load of 2 to 10 during the runs.

## Natural and horizontal graphs

`uv run python bench/run.py`:

| graph | series | n | edges (ts2vg / bend-visgraph if they differ) | ts2vg build | ts2vg only_degrees | bend-visgraph 1T | bend-visgraph 8T | bend-visgraph 64T |
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

On one thread, bend-visgraph builds every natural graph as fast as ts2vg's
Cython kernel (`only_degrees`) or faster: 2.5 times faster on the random
walk of 1,000,000 points. It takes about twice as long as the kernel on the
horizontal graphs from 100,000 points, whose sweep does only a comparison
per point.

With 64 threads, bend-visgraph builds the graphs of 1,000,000 points 17 to 76
times faster than ts2vg's `build`: 22 ms against 580 for the natural graph
of white noise, and 101 ms against 7647 for that of the random walk. At
10,000 points, 64 threads take longer than 8.

## How the build splits

ts2vg's divide and conquer takes an interval's first highest point as its
pivot, sweeps the interval from it, and recurses on the two sides. Every
point is the pivot of one interval. The interval starts after the nearest
earlier point that the pivot does not beat, and ends before the nearest
later point that beats it. bend-visgraph finds these bounds for every point
with a stack. After that, no sweep waits on another.

The stack runs on blocks of about 2,000 points in parallel, each block with
a stack of its own points. A point that pops its block's whole stack, and a
NaN that opens a block, need the points before the block. A merge walks the
blocks in order with the stack of all the earlier points and bounds those
points. White noise leaves a few of them in each block. A rising series
leaves every point to the merge, which then does the work of one stack on
one thread.

bend-visgraph then cuts the points into about 1,024 chunks of equal work, where
the work counts the points that the sweeps visit. A fork tree of 512
leaves runs the chunks. The blocks and the leaves share the arrays of y and
of the counts through Base's `Array.fork`, and x is the index. Base marks
`Array.fork` `@unsafe` because two handles can write the same cell. Here no
two tasks write the same cell. `visgraph.bend`'s `visibility` runs the
same code on one thread, as one block and one chunk, without `Array.fork`.

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
`block_leaf` fork nothing, and `parallel.bend`'s `degrees` walks the
edges the same way, with atomic adds.

## The limited penetrable graphs

`uv run python bench/run.py --sizes 10000 50000 --limit 1` builds the
graphs whose edges may cross one point:

| graph | series | n | edges (ts2vg / bend-visgraph if they differ) | ts2vg build | ts2vg only_degrees | bend-visgraph 1T | bend-visgraph 8T | bend-visgraph 64T |
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
the work grows as n², and the sweeps are independent. bend-visgraph splits the
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

| graph | series | n | edges (ts2vg / bend-visgraph if they differ) | ts2vg build | ts2vg only_degrees | bend-visgraph 1T | bend-visgraph 8T | bend-visgraph 64T |
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

## Many short series

A sliding-window study builds a graph for each window of a long series.
`uv run python bench/windows.py` cuts the series of 1,000,000 values into
windows of W values and builds each window's graph and degrees. ts2vg's
time is a Python loop of `build` over the windows. bend-visgraph's time is
`bench/windows.bend`, which cuts the windows out of an `Array<F32>` and
builds their graphs in one of three ways:

- `one`: `visgraph.bend`'s `build`, one window after another, on one thread.
- `par`: `parallel.bend`'s `build`, one window after another.
- `split`: `visgraph.bend`'s `build`, with the windows split in halves 8
  times and each half on its own task.

`copy` only cuts the windows and sums their values.

| graph | series | W | windows | edges (ts2vg / bend-visgraph if they differ) | ts2vg loop | copy 1T | one 1T | par 8T | par 64T | split 8T | split 64T |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| natural | white_noise | 100 | 10,000 | 2,706,880 | 461 | 3 | 68 | 2359 | 4957 | 13 | 8 |
| natural | white_noise | 1,000 | 1,000 | 2,912,952 | 396 | 3 | 81 | 508 | 818 | 14 | 8 |
| natural | white_noise | 10,000 | 100 | 2,946,006 | 426 | 4 | 89 | 109 | 225 | 17 | 13 |
| natural | random_walk | 100 | 10,000 | 4,175,969 | 622 | 3 | 102 | 2691 | 5167 | 18 | 9 |
| natural | random_walk | 1,000 | 1,000 | 6,475,435 / 6,475,434 | 954 | 3 | 182 | 786 | 1118 | 29 | 12 |
| natural | random_walk | 10,000 | 100 | 8,769,225 / 8,769,223 | 1736 | 3 | 348 | 492 | 478 | 57 | 31 |
| horizontal | white_noise | 100 | 10,000 | 1,896,579 | 350 | 3 | 52 | 2442 | 4870 | 11 | 7 |
| horizontal | white_noise | 1,000 | 1,000 | 1,984,912 | 272 | 2 | 62 | 401 | 745 | 11 | 7 |
| horizontal | white_noise | 10,000 | 100 | 1,997,971 | 248 | 3 | 72 | 81 | 185 | 14 | 10 |
| horizontal | random_walk | 100 | 10,000 | 1,774,409 | 339 | 3 | 65 | 2446 | 4841 | 12 | 8 |
| horizontal | random_walk | 1,000 | 1,000 | 1,928,198 | 306 | 3 | 132 | 414 | 746 | 20 | 9 |
| horizontal | random_walk | 10,000 | 100 | 1,977,598 | 388 | 3 | 330 | 224 | 196 | 49 | 21 |

On one thread, bend-visgraph builds the windows 1.2 to 6.8 times faster
than ts2vg's loop, and the shorter the windows, the larger the gap. ts2vg
makes a graph object and a Python call for every window. At W = 100,
ts2vg takes 34 to 62 µs a window and bend-visgraph 5 to 10. Split among 64
threads, every set of windows takes 7 to 31 ms, 18 to 80 times less than
ts2vg's loop. Cutting the windows takes 2 to 4 ms of that.

`parallel.bend`'s `build` on each window is the slowest way. Each call
costs about 0.25 ms on 8 threads and 0.5 ms on 64, more than a window of
1,000 points takes on one thread. It beats one thread only on the
horizontal graphs of the random walk at W = 10,000. For many short series,
build each with `visgraph.bend`'s `build` and split the series among the
threads, as `bench/windows.bend`'s `tree` does.

## Threads

`uv run python bench/run.py --sizes 1000000 --threads 1 2 4 8 16 32 64`
builds the graphs of 1,000,000 points on 1 to 64 threads:

| graph | series | n | edges (ts2vg / bend-visgraph if they differ) | ts2vg build | ts2vg only_degrees | bend-visgraph 1T | bend-visgraph 2T | bend-visgraph 4T | bend-visgraph 8T | bend-visgraph 16T | bend-visgraph 32T | bend-visgraph 64T |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| natural | white_noise | 1,000,000 | 2,951,201 | 602 | 152 | 142 | 78 | 53 | 37 | 28 | 24 | 22 |
| natural | random_walk | 1,000,000 | 12,752,617 / 12,752,619 | 7669 | 5659 | 2216 | 1161 | 605 | 317 | 173 | 110 | 102 |
| horizontal | white_noise | 1,000,000 | 1,999,970 | 352 | 60 | 115 | 68 | 48 | 33 | 25 | 21 | 20 |
| horizontal | random_walk | 1,000,000 | 1,997,907 | 1705 | 1408 | 2551 | 1317 | 694 | 360 | 190 | 105 | 72 |

`uv run python bench/run.py --sizes 50000 --limit 1 --threads 1 2 4 8 16 32 64`
builds the graphs of 50,000 points whose edges may cross one point:

| graph | series | n | edges (ts2vg / bend-visgraph if they differ) | ts2vg build | ts2vg only_degrees | bend-visgraph 1T | bend-visgraph 2T | bend-visgraph 4T | bend-visgraph 8T | bend-visgraph 16T | bend-visgraph 32T | bend-visgraph 64T |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| natural | white_noise | 50,000 | 296,409 | 4156 | 4117 | 3613 | 1911 | 980 | 501 | 258 | 134 | 106 |
| natural | random_walk | 50,000 | 962,935 | 4221 | 4068 | 3654 | 1914 | 977 | 505 | 260 | 139 | 110 |
| horizontal | white_noise | 50,000 | 199,923 | 25 | 4 | 18 | 23 | 13 | 11 | 10 | 11 | 12 |
| horizontal | random_walk | 50,000 | 198,796 | 27 | 8 | 34 | 26 | 18 | 13 | 11 | 11 | 13 |

From one run to the next, the times at 1, 8 and 64 threads differ from
the tables above by up to 3% at 1,000,000 points and up to 8% on the
natural graphs of 50,000 points. The horizontal graphs of 50,000 points,
which take 9 to 13 ms there, differ by up to 3 ms. The time on one thread
divided by each time gives the speedup:

| graph | series | n | limit | 2T | 4T | 8T | 16T | 32T | 64T |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| natural | white_noise | 1,000,000 | 0 | 1.8 | 2.7 | 3.8 | 5.1 | 5.9 | 6.5 |
| natural | random_walk | 1,000,000 | 0 | 1.9 | 3.7 | 7.0 | 12.8 | 20.1 | 21.7 |
| horizontal | white_noise | 1,000,000 | 0 | 1.7 | 2.4 | 3.5 | 4.6 | 5.5 | 5.8 |
| horizontal | random_walk | 1,000,000 | 0 | 1.9 | 3.7 | 7.1 | 13.4 | 24.3 | 35.4 |
| natural | white_noise | 50,000 | 1 | 1.9 | 3.7 | 7.2 | 14.0 | 27.0 | 34.1 |
| natural | random_walk | 50,000 | 1 | 1.9 | 3.7 | 7.2 | 14.1 | 26.3 | 33.2 |
| horizontal | white_noise | 50,000 | 1 | 0.8 | 1.4 | 1.6 | 1.8 | 1.6 | 1.5 |
| horizontal | random_walk | 50,000 | 1 | 1.3 | 1.9 | 2.6 | 3.1 | 3.1 | 2.6 |

The graphs with the most work per point scale with the cores: those of
the random walk of 1,000,000 points, and the natural graphs whose edges may
cross one point. On 16 threads they run 12.8 to 14.1 times faster than on
one, and on 32, one thread per core, 20 to 27 times. The second thread of
each core adds 8% to the natural graph of the random walk, and 26% to 46%
to the other three.

The graphs of 1,000,000 points of white noise stop near 6 times. Their
sweeps are short, and of the 22 ms that the natural graph takes on 64
threads, 3 to 4 go to the stack's blocks and merge and 3 to 4 more to
allocating the arrays of counts on one thread, as the section on how the
build splits finds. The horizontal graphs whose edges may cross one point
take 18 to 34 ms on one thread and gain nothing past 16 threads.

## Memory

`uv run python bench/memory.py` runs each build in a process of its own
and reports the process's peak resident set, the largest of 3 runs, in
MiB. bend-visgraph's process is `bench/bench.bend`, which reads the series
from a text file. Its baseline reads and parses the same file and copies
the series, with `bench/windows.bend copy` and a single window. ts2vg's
process loads the series from a numpy file and builds. Its baseline loads
the series and imports ts2vg.

| graph | series | n | edges (ts2vg / bend-visgraph if they differ) | ts2vg baseline | ts2vg build | ts2vg only_degrees | bend-visgraph baseline | bend-visgraph 1T | bend-visgraph 64T |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| natural | white_noise | 1,000,000 | 2,951,201 | 39 | 443 | 59 | 261 | 353 | 345 |
| natural | random_walk | 1,000,000 | 12,752,617 / 12,752,619 | 39 | 1718 | 58 | 232 | 624 | 616 |
| horizontal | white_noise | 1,000,000 | 1,999,970 | 39 | 319 | 59 | 260 | 324 | 317 |
| horizontal | random_walk | 1,000,000 | 1,997,907 | 39 | 318 | 58 | 232 | 296 | 289 |

`uv run python bench/memory.py --sizes 50000 --limit 1`:

| graph | series | n | edges (ts2vg / bend-visgraph if they differ) | ts2vg baseline | ts2vg build | ts2vg only_degrees | bend-visgraph baseline | bend-visgraph 1T | bend-visgraph 64T |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| natural | white_noise | 50,000 | 296,409 | 32 | 71 | 32 | 14 | 23 | 17 |
| natural | random_walk | 50,000 | 962,935 | 32 | 158 | 33 | 13 | 42 | 38 |
| horizontal | white_noise | 50,000 | 199,923 | 32 | 59 | 33 | 15 | 20 | 16 |
| horizontal | random_walk | 50,000 | 198,796 | 32 | 58 | 32 | 12 | 19 | 16 |

The natural and horizontal graphs of one series read the same input, so
the difference between their peaks is the memory of the extra edges. Each
extra edge takes 32 bytes in bend-visgraph and 137 in ts2vg, whose edge
list holds a Python tuple for each edge. Both series give these numbers.
On the random walk, the natural graph has 10,754,712 more edges than the
horizontal one, and it raises bend-visgraph's peak from 296 to 624 MiB
and ts2vg's from 318 to 1,718. On 64 threads, bend-visgraph's peak is no
higher than on one.

bend-visgraph's baseline is 232 to 261 MiB for 1,000,000 values, about
25 bytes per character of the text file, because a Bend `String` keeps
each character in a node of its own. The runtime reuses part of that
memory for the graph, so a build's peak is less than its baseline plus its
graph. At 1,000,000 points, ts2vg's peak is 0.98 to 2.8 times
bend-visgraph's, and at 50,000 points 2.9 to 3.8 times. ts2vg's
`only_degrees` keeps no edge list and peaks about 20 MiB above its
baseline at 1,000,000 points. bend-visgraph always builds the edges.

## Edges against ts2vg

`bench/compare.py` builds each graph of the first three tables with ts2vg
and with bend-visgraph's command line, and compares the two edge sets.
For each edge that only one of them has, it decides with integers, from
the float32 values, whether the edge crosses more than `limit` points. 24
of the 28 graphs are equal edge for edge. These differ:

| graph | series | n | ts2vg edges | bend-visgraph edges | only in ts2vg | only in bend-visgraph |
| --- | --- | --- | --- | --- | --- | --- |
| natural | random_walk | 100,000 | 1,062,543 | 1,062,541 | 2 | 0 |
| natural | random_walk | 1,000,000 | 12,752,617 | 12,752,619 | 11 | 13 |
| natural, irregular x | white_noise | 1,000,000 | 2,953,547 | 2,953,548 | 0 | 1 |
| natural, irregular x | random_walk | 1,000,000 | 12,750,305 | 12,750,298 | 22 | 15 |

Every edge in the last two columns is in the graph: where three points are
nearly collinear, each tool misses edges that the other finds. bend-visgraph
rounds slopes to 24 bits; ts2vg rounds them to 53 bits and also rejects a
slope that exceeds the running maximum by less than its tolerance, 1e-14
times the largest coordinate. On the 100,000-point walk, bend-visgraph
matches `tests/reference.py`, ts2vg's kernels in float32, edge for edge.
