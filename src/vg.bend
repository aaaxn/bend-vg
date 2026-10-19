# bend-vg's library: ts2vg's options and a series in, the edges of its
# visibility graph out. `build` here relies on no @unsafe def;
# src/parallel.bend's `build` takes the same arguments and runs on every
# thread.
import Base
import ./graph.bend as G
import ./penetrable.bend as P

# The options of ts2vg's graph classes: the graph, how its edges point,
# their weight, the weights to keep (above `min_weight` and below
# `max_weight`), and how many points an edge may cross.
type Options is Data:
  Options{graph: G.Graph, directed: G.Direction, weighted: G.Weight, min_weight: F32, max_weight: F32, penetrable_limit: U32}

# ts2vg's defaults for the graph `g`: undirected, unweighted, every weight
# kept, no point crossed.
def options(g: G.Graph) -> Options:
  Options{g, G.Undirected{}, G.Unweighted{}, G.neg_inf(), G.inf(), 0}

# The `n` values `ys` of a time series, indexed from 0, and their x: the
# index, or `G.At{xs}` with the x of each value, increasing.
type Series is Type:
  Series{n: U32, ys: Array<F32>, xs: G.Xs}

def length(vs: List<&2, F32>, +n: U32) -> U32:
  match vs:
    case Nil{}:
      n
    case Con{v, rest}:
      length(rest, (n + 1 : U32))

def fill(vs: List<&2, F32>, +i: U32, a: Array<F32>) -> Array<F32>:
  match vs:
    case Nil{}:
      a
    case Con{v, rest}:
      fill(rest, (i + 1 : U32), Array.set(F32, a, i, v))

def column(+n: U32, vs: List<&2, F32>) -> Array<F32>:
  fill(vs, 0, Array.new(F32, Nat.add(1n, U32.log2(n)), 0.0))

def counted(+n: U32, ys: List<&2, F32>) -> Series:
  Series{n, column(n, ys), G.Index{}}

# The series of the values `ys`, each at its index.
def series(+ys: List<&2, F32>) -> Series:
  counted(length(ys, 0), ys)

def counted_at(+n: U32, xs: List<&2, F32>, ys: List<&2, F32>) -> Series:
  Series{n, column(n, ys), G.At{column(n, xs)}}

# The series of the values `ys` at `xs`, which must hold as many values,
# increasing.
def series_at(xs: List<&2, F32>, +ys: List<&2, F32>) -> Series:
  counted_at(length(ys, 0), xs, ys)

def chosen(visibility: Bool, +g: G.Graph, +dir: G.Direction, +k: G.Weight, +lo: F32, +hi: F32, +limit: U32, ys: Array<F32>, xs: G.Xs, +n: U32) -> G.Edges:
  match visibility:
    case True{}:
      G.build(g, dir, k, lo, hi, ys, xs, n)
    case False{}:
      P.build(g, dir, k, lo, hi, limit, ys, xs, n)

# The edges of the graph of `s` with the options `o`, as ts2vg's `build`
# makes them. The natural and horizontal graphs run on one thread, and the
# limited penetrable ones split their sweeps among every thread.
def build(o: Options, s: Series) -> G.Edges:
  Options{g, dir, k, lo, hi, +limit} = o
  Series{+n, ys, xs} = s
  chosen(U32.is_zero(limit), g, dir, k, lo, hi, limit, ys, xs, n)
