# bend-vg

bend-vg builds the visibility graphs of [ts2vg](https://github.com/CarlosBergillos/ts2vg)
1.2.4 in [Bend2](https://github.com/bendlang/bend): natural and horizontal,
undirected or directed, limited penetrable or not, with any of ts2vg's edge
weights. It runs ts2vg's algorithms with the same operations in the same
order. The divide and conquer builds the two sides of each split in
parallel, and the penetrable graphs split their sweeps among threads.

## Use it

```sh
bend bend_vg.bend -o bend_vg
./bend_vg series.txt -t natural -w distance
```

The input is a text file with one value per line. The options are those of
ts2vg's command line, with the input first:

| Option | Values | Default |
| --- | --- | --- |
| `-t`, `--type` | `natural`, `horizontal` | `natural` |
| `-d`, `--directed` | `left_to_right`, `top_to_bottom` | undirected |
| `-w`, `--weighted` | `distance`, `sq_distance`, `v_distance`, `abs_v_distance`, `h_distance`, `abs_h_distance`, `slope`, `abs_slope`, `angle`, `abs_angle`, `num_penetrations` | unweighted |
| `-p`, `--penetrable_limit` | how many points an edge may cross | 0 |
| `-m`, `--outputmode` | `el` edge list, `ds` degree sequence, `dd` degree distribution, `dc` degree counts | `el` |
| `-o`, `--output` | a file | standard output |

`src/graph.bend` and `src/penetrable.bend` are the library: their `build`
takes the points and returns the edges, with ts2vg's `min_weight` and
`max_weight` as its `lo` and `hi`.

## Where it differs from ts2vg

- Bend2 has no float64, so bend-vg computes in F32. It rounds each value
  once from its text to F32, and its x is the index. On the same F32 values,
  its unweighted edges equal ts2vg's on every test series. The two can
  differ where three points are nearly collinear, since F32 slopes carry 24
  bits.
- Rounding a float64 series to F32 can tie values that differ in float64.
  For a series with a large offset, such as `1000 + 0.01 * noise`, subtract
  the offset before writing the file: neither graph changes under a shift.
- F32 overflows above about 3.4e38. A weight that overflows, such as the
  distance between values near 1e20, is infinite, and the default upper
  bound on weights then drops its edge, which ts2vg keeps.
- Edges come out in another order, and `-o` prints no summary.

## Speed

[docs/benchmark.md](docs/benchmark.md) times bend-vg against ts2vg. On one
thread, bend-vg beats ts2vg's Cython kernel on the natural graph of a
random walk of 1,000,000 points, and takes up to 6 times as long on the
horizontal graphs. The divide and conquer gives more threads little to do:
1.4 times from 1 to 64 threads at 1,000,000 points. The limited
penetrable natural graph splits well: at 50,000 points, 64 threads build
it 7 times faster than ts2vg.

## Check it

```sh
uv sync --locked
bend PROOF.bend
uv run pytest -n auto
```

`LAWS.bend` states how the divide and conquer cuts an interval around its
pivot, and that the parallel penetrable build gives the edges of one
sequential pass; `PROOF.bend` proves both. The tests build `bend_vg` natively and as
JavaScript, and compare both, bit for bit, with `tests/reference.py`, a
float32 copy of ts2vg's kernels. They also compare the native build with
ts2vg itself: the unweighted edges must be equal, and the weights within
1e-6 relative.
