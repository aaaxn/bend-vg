# bend-vg

bend-vg builds the visibility graphs of [ts2vg](https://github.com/CarlosBergillos/ts2vg)
1.2.4 in [Bend2](https://github.com/bendlang/bend): natural and horizontal,
undirected or directed, limited penetrable or not, with any of ts2vg's edge
weights. Its sweeps do ts2vg's operations in the same order. It finds the
intervals of ts2vg's divide and conquer with a stack over each block of
points, in parallel, then runs the sweeps of all intervals in parallel.
The penetrable graphs split their sweeps among threads too.

## Requirements

- [Bend](https://bend-lang.com) 2.0.37, which installs with
  `curl -fsSL https://bend-lang.com/install.sh | sh`. A native build needs
  clang 14 or newer.
- For the tests and the benchmark: [uv](https://docs.astral.sh/uv/), and
  [Bun](https://bun.sh) to run the JavaScript build.

bend-vg is tested on Linux x86-64.

## Use it

```sh
bend bend_vg.bend -o bend_vg
./bend_vg series.txt -t natural -w distance
```

The input is a text file with one value per line. The options are those of
ts2vg's command line, with the input first, and `-x`, which takes the `xs`
of ts2vg's `build`:

| Option | Values | Default |
| --- | --- | --- |
| `-t`, `--type` | `natural`, `horizontal` | `natural` |
| `-d`, `--directed` | `left_to_right`, `top_to_bottom` | undirected |
| `-w`, `--weighted` | `distance`, `sq_distance`, `v_distance`, `abs_v_distance`, `h_distance`, `abs_h_distance`, `slope`, `abs_slope`, `angle`, `abs_angle`, `num_penetrations` | unweighted |
| `-p`, `--penetrable_limit` | how many points an edge may cross | 0 |
| `-m`, `--outputmode` | `el` edge list, `ds` degree sequence, `dd` degree distribution, `dc` degree counts | `el` |
| `-o`, `--output` | a file | standard output |
| `-x`, `--xs` | a file with the x of each value, one per line, increasing | the index |

## Use it from Bend

`src/vg.bend` is the library. `VG.build(o, s)` returns the edges of the
graph of the series `s` with ts2vg's options `o`:

- `VG.Options{graph, directed, weighted, min_weight, max_weight,
  penetrable_limit}` holds the options of ts2vg's graph classes, with
  `G.neg_inf()` and `G.inf()` as no bound; `VG.options(G.Natural{})` gives
  ts2vg's defaults.
- `VG.Series{n, ys, xs}` holds `n` values in an array, and their x as
  `G.Index{}` or `G.At{xs}`. `VG.series(values)` and `VG.series_at(xs,
  values)` make one from lists.

Three defs read the edges: `VG.fold(~A, ~f, es, acc)` folds the template
`f(acc, src, dst, w)` over them, `VG.degrees(es, n)` gives ts2vg's degrees
as an array, and `VG.adjacency(directed, es, n)` gives the graph as
compressed rows, each in increasing order. This program prints 4, the
number of edges:

```python
import Base
import ./src/graph.bend as G
import ./src/vg.bend as VG

def main() -> IO(Unit):
  do IO<Unit>:
    es : G.Edges = VG.build(VG.options(G.Natural{}), VG.series([3.0, 4.0, 2.0, 1.0]))
    IO.print(U32.show(VG.fold(~U32, ~(m => s => t => w => (m + 1 : U32)), es, 0)))
```

`VG.build` runs the natural and horizontal graphs on one thread, and splits
the penetrable ones among every thread. `src/parallel.bend`'s `build` and
`degrees` take the same arguments and run on every thread. Only
`src/parallel.bend` relies on Base's `@unsafe` `Array.fork`, so `bend
--check-only` passes on a program that does not import it, such as
`tests/one_thread.bend` and `tests/library.bend`.

## Where it differs from ts2vg

- Bend2 has no float64, so bend-vg computes in F32. It rounds each value
  once from its text to F32, and so each x of `-x`. On the same F32 values,
  its unweighted edges equal ts2vg's on every test series. The two can
  differ where three points are nearly collinear, since F32 slopes carry 24
  bits.
- F32 holds every index below 2^24 exactly, so without `-x` the command
  line refuses a series of more than 16,777,216 values. The library's
  `build` does not check.
- F32 x carries 24 bits too: Unix times in seconds, about 1.7e9, round to
  multiples of 128. Subtract the first x before writing the file: slopes
  and distances depend only on differences of x.
- Rounding a float64 series to F32 can tie values that differ in float64.
  For a series with a large offset, such as `1000 + 0.01 * noise`, subtract
  the offset before writing the file: neither graph changes under a shift.
- F32 overflows above about 3.4e38. A weight that overflows, such as the
  distance between values near 1e20, is infinite, and the default upper
  bound on weights then drops its edge, which ts2vg keeps.
- Edges come out in another order, and `-o` prints no summary.

## Speed

[docs/benchmark.md](docs/benchmark.md) times bend-vg against ts2vg. On one
thread, bend-vg builds every natural graph as fast as ts2vg's Cython kernel
or faster, and takes about twice as long on the horizontal graphs. With 64
threads, it builds the graphs of 1,000,000 points 17 to 76 times faster
than ts2vg's `build`. The limited penetrable natural graph takes a little
less time than ts2vg's kernel on one thread, and 64 threads build it 42
times faster at 50,000 points. `bench/compare.py` compares the edges with
ts2vg's: 24 of the 28 graphs there are equal edge for edge, and in the
other 4, every edge that only one tool has is in the graph.

## Check it

```sh
uv sync --locked
bend PROOF.bend
uv run pytest -n auto
```

`LAWS.bend` states that each level of the fork tree halves its chunks
without losing or repeating one, and that the parallel penetrable build
gives the edges of one sequential pass. `PROOF.bend` proves both. It still
prints SOME PROOFS FAIL, naming the 13 defs of `src/parallel.bend` that
rely on Base's `@unsafe` `Array.fork`: the tasks that share a forked array
read it, write cells no other task writes, or add to cells atomically.

The tests build `bend_vg`, `tests/one_thread.bend` and `tests/library.bend`
natively and as JavaScript, and compare them, bit for bit, with
`tests/reference.py`, a float32 copy of ts2vg's kernels. They also compare
the native build with ts2vg itself: the unweighted edges must be equal,
and the weights within 1e-6 relative. On series of 100,000 values, they
compare the JavaScript build with the native one.

## License

MIT, in [LICENSE](LICENSE). bend-vg ports ts2vg's graph kernels, and
`tests/reference.py` copies them in float32, so the license carries ts2vg's
copyright notice too.
