# bend-vg's library: ts2vg's options and a series in, the edges of its
# visibility graph out. `build` here relies on no @unsafe def;
# src/parallel.bend's `build` takes the same arguments and runs on every
# thread.
import Base
import ./graph.bend as G
import ./penetrable.bend as P
import ./report.bend as Report

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

# What to read off the edges

# `f(acc, src, dst, w)` over every edge of `es`, in the order the rope
# holds them, from `acc`.
def fold(~A: Type, ~f: A -> U32 -> U32 -> F32 -> A, es: G.Edges, acc: A) -> A:
  match es:
    case G.ENil{}:
      acc
    case G.ECon{s, t, w, next}:
      fold(~A, ~f, next, f(acc, s, t, w))
    case G.EJoin{a, b}:
      fold(~A, ~f, b, fold(~A, ~f, a, acc))

# The degree of each of the `n` nodes of `es`, as ts2vg's `degrees`: the
# edges at the node, in either direction.
def degrees(es: G.Edges, +n: U32) -> Array<U32>:
  Report.degrees(es, Report.slots(n))

# The graph as compressed rows: the neighbors of node i are
# `targets[offsets[i]]` up to `targets[offsets[i + 1]]`, increasing, and
# the weights of their edges sit at the same positions. An undirected
# graph's edge appears in the rows of both its ends, a directed one's in
# its source's row.
type Adjacency is Type:
  Adjacency{offsets: Array<U32>, targets: Array<U32>, weights: Array<F32>}

# Each half edge (u, v), from u to v, goes into two passes of a counting
# sort: by v, then by u, so each row ends up in increasing order.

def is_undirected(d: G.Direction) -> Bool:
  match d:
    case G.Undirected{}:
      True{}
    case _:
      False{}

def bumped(r: Array<U32> & U32, +i: U32) -> Array<U32>:
  (a, +c) = r
  Array.set(U32, a, i, (c + 1 : U32))

type Counts is Type:
  Counts{outs: Array<U32>, ins: Array<U32>}

def count_half(present: Bool, +u: U32, +v: U32, c: Counts) -> Counts:
  match present:
    case True{}:
      Counts{outs, ins} = c
      Counts{bumped(Array.get(U32, outs, u), u), bumped(Array.get(U32, ins, v), v)}
    case False{}:
      c

def count_halves(es: G.Edges, +both: Bool, c: Counts) -> Counts:
  match es:
    case G.ENil{}:
      c
    case G.ECon{+s, +t, w, next}:
      count_halves(next, both, count_half(both, t, s, count_half(True{}, s, t, c)))
    case G.EJoin{a, b}:
      count_halves(b, both, count_halves(a, both, c))

# The counts of `n` nodes, in place, as where each node's run starts; slot
# `n` gets the total.
def starts(count: Nat, +i: U32, r: Array<U32> & U32, +acc: U32) -> Array<U32>:
  match count:
    case 0n:
      (a, c) = r
      Array.set(U32, a, i, acc)
    case 1n+k:
      (a, +c) = r
      +i2 = (i + 1 : U32)
      starts(k, i2, Array.get(U32, Array.set(U32, a, i, acc), i2), (acc + c : U32))

# The half edges, by target: source, target and weight at each position.
type Halves is Type:
  Halves{cur: Array<U32>, us: Array<U32>, vs: Array<U32>, ws: Array<F32>}

def put_half(+u: U32, +v: U32, +w: F32, r: Array<U32> & U32, us: Array<U32>, vs: Array<U32>, ws: Array<F32>) -> Halves:
  (cur, +p) = r
  Halves{Array.set(U32, cur, v, (p + 1 : U32)), Array.set(U32, us, p, u), Array.set(U32, vs, p, v), Array.set(F32, ws, p, w)}

def place_half(present: Bool, +u: U32, +v: U32, +w: F32, h: Halves) -> Halves:
  match present:
    case True{}:
      Halves{cur, us, vs, ws} = h
      put_half(u, v, w, Array.get(U32, cur, v), us, vs, ws)
    case False{}:
      h

def by_target(es: G.Edges, +both: Bool, h: Halves) -> Halves:
  match es:
    case G.ENil{}:
      h
    case G.ECon{+s, +t, +w, next}:
      by_target(next, both, place_half(both, t, s, w, place_half(True{}, s, t, w, h)))
    case G.EJoin{a, b}:
      by_target(b, both, by_target(a, both, h))

type Rows is Type:
  Rows{cur: Array<U32>, targets: Array<U32>, weights: Array<F32>}

def put_row(+u: U32, +v: U32, +w: F32, r: Array<U32> & U32, targets: Array<U32>, weights: Array<F32>) -> Rows:
  (cur, +p) = r
  Rows{Array.set(U32, cur, u, (p + 1 : U32)), Array.set(U32, targets, p, v), Array.set(F32, weights, p, w)}

# The half edges from position `p` on, in target order, into their
# sources' rows.
def by_source(count: Nat, +p: U32, ur: Array<U32> & U32, vr: Array<U32> & U32, wr: Array<F32> & F32, out: Rows) -> Rows:
  match count:
    case 0n:
      (us, u) = ur
      (vs, v) = vr
      (ws, w) = wr
      out
    case 1n+k:
      (us, +u) = ur
      (vs, +v) = vr
      (ws, +w) = wr
      Rows{cur, targets, weights} = out
      +p2 = (p + 1 : U32)
      by_source(k, p2, Array.get(U32, us, p2), Array.get(U32, vs, p2), Array.get(F32, ws, p2), put_row(u, v, w, Array.get(U32, cur, u), targets, weights))

def slots_for(+n: U32) -> Nat:
  Nat.add(1n, U32.log2(n))

def rows_done(offsets: Array<U32>, r: Rows) -> Adjacency:
  Rows{cur, targets, weights} = r
  Adjacency{offsets, targets, weights}

def rows_from(+h: U32, oc: Array<U32> & Array<U32>, hv: Halves) -> Adjacency:
  (offsets, cur) = oc
  Halves{tcur, us, vs, ws} = hv
  rows_done(offsets, by_source(U32.to_nat(h), 0, Array.get(U32, us, 0), Array.get(U32, vs, 0), Array.get(F32, ws, 0), Rows{cur, Array.new(U32, slots_for(h), 0), Array.new(F32, slots_for(h), 0.0)}))

def with_starts(es: G.Edges, +both: Bool, +h: U32, outs: Array<U32>, ins: Array<U32>) -> Adjacency:
  rows_from(h, Array.clone(U32, outs), by_target(es, both, Halves{ins, Array.new(U32, slots_for(h), 0), Array.new(U32, slots_for(h), 0), Array.new(F32, slots_for(h), 0.0)}))

def with_total(es: G.Edges, +both: Bool, r: Array<U32> & U32, ins: Array<U32>) -> Adjacency:
  (outs, +h) = r
  with_starts(es, both, h, outs, ins)

def tallied(es: G.Edges, +both: Bool, +n: U32, c: Counts) -> Adjacency:
  Counts{outs, ins} = c
  with_total(es, both, Array.get(U32, starts(U32.to_nat(n), 0, Array.get(U32, outs, 0), 0), n), starts(U32.to_nat(n), 0, Array.get(U32, ins, 0), 0))

# The rows of the `n` nodes of `es`, a graph whose edges point as `dir`
# says.
def adjacency(+dir: G.Direction, +es: G.Edges, +n: U32) -> Adjacency:
  tallied(es, is_undirected(dir), n, count_halves(es, is_undirected(dir), Counts{Array.new(U32, slots_for(n), 0), Array.new(U32, slots_for(n), 0)}))
