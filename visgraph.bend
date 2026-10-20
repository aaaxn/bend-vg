# bend-visgraph's library: ts2vg's options and a series in, the graph out,
# with no def that relies on @unsafe. Its graphs are ts2vg 1.2.4's, in F32.
# parallel.bend builds the same graphs on every thread, and relies on Base's
# @unsafe Array.fork; a program that does not import it passes
# `bend --check-only`.
#
#   import bend-visgraph@2.0.0.0/visgraph.bend as VG
#
# Its interface is the types at the top, inf and neg_inf, and the defs under
# "The library" at the bottom; every other def serves them.
import Base

type Visibility is Data:
  Natural{}
  Horizontal{}

type Direction is Data:
  Undirected{}
  LeftToRight{}
  TopToBottom{}

type Weight is Data:
  Unweighted{}
  Distance{}
  SqDistance{}
  VDistance{}
  AbsVDistance{}
  HDistance{}
  AbsHDistance{}
  Slope{}
  AbsSlope{}
  Angle{}
  AbsAngle{}
  NumPenetrations{}

# The x coordinate of each value: its index, or the value at the same
# index of an array.
type Xs is Type:
  Index{}
  At{xs: Array<F32>}

# The edges, as a rope: ECon adds an edge and EJoin joins two ropes, so the
# two halves of a split join in one step.
type Edges is Data:
  ENil{}
  ECon{src: U32, dst: U32, w: F32, next: Edges}
  EJoin{a: Edges, b: Edges}

# The options of ts2vg's graph classes: the graph, how its edges point,
# their weight, the weights to keep (above `min_weight` and below
# `max_weight`; neg_inf() and inf() keep every weight), and how many points
# an edge may cross.
type Options is Data:
  Options{visibility: Visibility, directed: Direction, weighted: Weight, min_weight: F32, max_weight: F32, penetrable_limit: U32}

# The `n` values `ys` of a time series, indexed from 0, and their x: the
# index, or `At{xs}` with the x of each value, increasing.
type Series is Type:
  Series{n: U32, ys: Array<F32>, xs: Xs}

# A built graph: its `n` nodes, how its edges point, and its edges.
type Graph is Data:
  Graph{n: U32, directed: Direction, edges: Edges}

# The graph as compressed rows: the neighbors of node i are
# `targets[offsets[i]]` up to `targets[offsets[i + 1]]`, increasing, and
# the weights of their edges sit at the same positions. An undirected
# graph's edge appears in the rows of both its ends, a directed one's in
# its source's row.
type Adjacency is Type:
  Adjacency{offsets: Array<U32>, targets: Array<U32>, weights: Array<F32>}

# F32 constants, from divisions by zero: the JS lane builds an F32 from its
# bits with two typed arrays, too slow for a sweep that passes NaN at every
# point it visits.

def nan() -> F32:
  F32.div(0.0, 0.0)

def inf() -> F32:
  F32.div(1.0, 0.0)

def neg_inf() -> F32:
  F32.div(F32.neg(1.0), 0.0)

def is_nan(+a: F32) -> Bool:
  F32.is_ne(a, a)

def pick(c: Bool, a: F32, b: F32) -> F32:
  match c:
    case True{}:
      a
    case False{}:
      b

def pick_u32(c: Bool, a: U32, b: U32) -> U32:
  match c:
    case True{}:
      a
    case False{}:
      b

# Weights: ts2vg's _weight_* functions. `s` is the slope the sweep measured,
# or NaN when it measured none.

def sq_distance(+x1: F32, +x2: F32, +y1: F32, +y2: F32) -> F32:
  F32.add(F32.mul(F32.sub(x2, x1), F32.sub(x2, x1)), F32.mul(F32.sub(y2, y1), F32.sub(y2, y1)))

def known_slope(+s: F32, +x1: F32, +x2: F32, +y1: F32, +y2: F32) -> F32:
  pick(is_nan(s), F32.div(F32.sub(y2, y1), F32.sub(x2, x1)), s)

def weight(+k: Weight, +x1: F32, +x2: F32, +y1: F32, +y2: F32, +s: F32) -> F32:
  match k:
    case Unweighted{}:
      0.0
    case Distance{}:
      F32.sqrt(sq_distance(x1, x2, y1, y2))
    case SqDistance{}:
      sq_distance(x1, x2, y1, y2)
    case VDistance{}:
      F32.sub(y2, y1)
    case AbsVDistance{}:
      F32.abs(F32.sub(y2, y1))
    case HDistance{}:
      F32.sub(x2, x1)
    case AbsHDistance{}:
      F32.abs(F32.sub(x2, x1))
    case Slope{}:
      known_slope(s, x1, x2, y1, y2)
    case AbsSlope{}:
      F32.abs(known_slope(s, x1, x2, y1, y2))
    case Angle{}:
      F32.atan(known_slope(s, x1, x2, y1, y2))
    case AbsAngle{}:
      F32.atan(F32.abs(known_slope(s, x1, x2, y1, y2)))
    case NumPenetrations{}:
      0.0

# Edges: ts2vg's add_edge, which drops an edge whose weight is at most lo or
# at least hi.

def put(drop: Bool, i1: U32, i2: U32, w: F32, es: Edges) -> Edges:
  match drop:
    case True{}:
      es
    case False{}:
      ECon{i1, i2, w, es}

def add_edge(+k: Weight, +lo: F32, +hi: F32, i1: U32, i2: U32, +x1: F32, +x2: F32, +y1: F32, +y2: F32, +s: F32, es: Edges) -> Edges:
  +w = weight(k, x1, x2, y1, y2, s)
  put(F32.is_le(w, lo) || F32.is_ge(w, hi), i1, i2, w, es)

# A visible point right of the pivot a: the edge (a, b).
def add_right(seen: Bool, +k: Weight, +lo: F32, +hi: F32, ia: U32, ib: U32, xa: F32, xb: F32, ya: F32, yb: F32, s: F32, es: Edges) -> Edges:
  match seen:
    case True{}:
      add_edge(k, lo, hi, ia, ib, xa, xb, ya, yb, s, es)
    case False{}:
      es

# A visible point left of the pivot a: the edge (a, b) for top_to_bottom,
# else (b, a).
def add_left_dir(dir: Direction, +k: Weight, +lo: F32, +hi: F32, ia: U32, ib: U32, xa: F32, xb: F32, ya: F32, yb: F32, s: F32, es: Edges) -> Edges:
  match dir:
    case TopToBottom{}:
      add_edge(k, lo, hi, ia, ib, xa, xb, ya, yb, s, es)
    case _:
      add_edge(k, lo, hi, ib, ia, xb, xa, yb, ya, s, es)

def add_left(seen: Bool, +dir: Direction, +k: Weight, +lo: F32, +hi: F32, ia: U32, ib: U32, xa: F32, xb: F32, ya: F32, yb: F32, s: F32, es: Edges) -> Edges:
  match seen:
    case True{}:
      add_left_dir(dir, k, lo, hi, ia, ib, xa, xb, ya, yb, s, es)
    case False{}:
      es

# Sweeps from the pivot a over the points of one side, nearest first.

def abs_tol() -> F32:
  {0.00000000000001 : F32}

def rel_tol() -> F32:
  {0.00000000000001 : F32}

# max(|xa|, |ya|), which a sweep computes once.
def scale(+xa: F32, +ya: F32) -> F32:
  F32.max(F32.abs(xa), F32.abs(ya))

# ts2vg's tolerance for the points a and b.
# F32.max only picks one of its words, so grouping the four maxima this way
# gives ts2vg's word.
def tol(+scale_a: F32, +xb: F32, +yb: F32) -> F32:
  F32.max(abs_tol(), F32.mul(rel_tol(), F32.max(scale_a, F32.max(F32.abs(xb), F32.abs(yb)))))

def greater(+a: F32, +b: F32, +t: F32) -> Bool:
  F32.is_gt(F32.sub(a, b), t)

# greater(s, best, tol(scale_a, xb, yb)), with the tolerance computed only
# when s is above best: the tolerance is positive, so otherwise it fails
# anyway.
def clears(up: Bool, +s: F32, +best: F32, +scale_a: F32, +xb: F32, +yb: F32) -> Bool:
  match up:
    case True{}:
      greater(s, best, tol(scale_a, xb, yb))
    case False{}:
      False{}

# Divide and conquer: ts2vg's _compute_graph takes an interval's first
# highest point as its pivot, sweeps the interval's points left and right of
# it, and recurses on both sides. Every point is the pivot of one interval,
# so once each point knows how many points its interval holds on each side,
# the sweeps no longer depend on each other.

# The stack holds the points no later point has beaten yet. A point pops the
# entries it beats; the entry left on top bounds its interval on the left,
# and the point that pops an entry bounds that entry's interval on the right.
type Stack is Data:
  KNil{}
  KCon{i: U32, key: F32, next: Stack}

# What a later point must beat to pop y. An equal point beats nothing, so an
# interval's first highest point is its pivot. A NaN beats nothing either,
# and ts2vg's argmax takes it only as an interval's first point, so a NaN at
# i is the pivot of the right side of i - 1: it takes the key of the entry
# below it and leaves the stack with that entry.
def key(+y: F32, +below: F32) -> F32:
  pick(is_nan(y), below, y)

# The work only balances the split, so F32 rounding does no harm.
type Popped is Type:
  Popped{first: U32, below: F32, st: Stack, rights: Array<U32>, visits: F32}

def pops(rest: Stack, beat: Bool, +y: F32, +i: U32, +j: U32, +kj: F32, rights: Array<U32>, +visits: F32) -> Popped:
  match rest beat:
    case KCon{+j2, +k2, rest2} True{}:
      +r = (i - 1 - j : U32)
      pops(rest2, F32.is_gt(y, k2), y, i, j2, k2, Array.set(U32, rights, j, r), F32.add(visits, U32.to_f32(r)))
    case KNil{} True{}:
      +r = (i - 1 - j : U32)
      Popped{0, inf(), KNil{}, Array.set(U32, rights, j, r), F32.add(visits, U32.to_f32(r))}
    case _ False{}:
      Popped{(j + 1 : U32), kj, KCon{j, kj, rest}, rights, visits}

def flush(st: Stack, +n: U32, rights: Array<U32>, +visits: F32) -> Array<U32> & F32:
  match st:
    case KCon{+j, k, rest}:
      +r = (n - 1 - j : U32)
      flush(rest, n, Array.set(U32, rights, j, r), F32.add(visits, U32.to_f32(r)))
    case KNil{}:
      (rights, visits)

# lefts and rights count the points each point's left and right sweeps visit.
type Cols is Type:
  Cols{ys: Array<F32>, lefts: Array<U32>, rights: Array<U32>}

type Arrived is Type:
  OpensWithNaN{rights: Array<U32>, visits: F32}
  PopsAll{rights: Array<U32>, visits: F32}
  Bounded{first: U32, below: F32, st: Stack, rights: Array<U32>, visits: F32}

def lpops(rest: Stack, beat: Bool, +y: F32, +i: U32, +j: U32, +kj: F32, rights: Array<U32>, +visits: F32) -> Arrived:
  match rest beat:
    case KCon{+j2, +k2, rest2} True{}:
      +r = (i - 1 - j : U32)
      lpops(rest2, F32.is_gt(y, k2), y, i, j2, k2, Array.set(U32, rights, j, r), F32.add(visits, U32.to_f32(r)))
    case KNil{} True{}:
      +r = (i - 1 - j : U32)
      PopsAll{Array.set(U32, rights, j, r), F32.add(visits, U32.to_f32(r))}
    case _ False{}:
      Bounded{(j + 1 : U32), kj, KCon{j, kj, rest}, rights, visits}

def arrive(st: Stack, nan: Bool, +y: F32, +i: U32, rights: Array<U32>, +visits: F32) -> Arrived:
  match st nan:
    case KNil{} True{}:
      OpensWithNaN{rights, visits}
    case KNil{} False{}:
      PopsAll{rights, visits}
    case KCon{+j, +kj, rest} True{}:
      Bounded{(j + 1 : U32), kj, KCon{j, kj, rest}, rights, visits}
    case KCon{+j, +kj, rest} False{}:
      lpops(rest, F32.is_gt(y, kj), y, i, j, kj, rights, visits)

# Latest first.
type Unbounded is Data:
  UNil{}
  UCon{i: U32, y: F32, next: Unbounded}

# A block of points runs the stack on its own points. Its points that pop
# its whole stack, and the NaNs that open it, need the points before it.
type Block is Data:
  Block{start: U32, opening_nans: U32, unbounded: Unbounded, st: Stack, visits: F32}

type Local is Type:
  Local{b: Block, c: Cols}

def local(count: Nat, +i: U32, +y: F32, a: Arrived, yr: Array<F32> & F32, lefts: Array<U32>, +start: U32, +opening_nans: U32, unbounded: Unbounded) -> Local:
  match count a:
    case 1n+c OpensWithNaN{rights, +visits}:
      (ys, +y2) = yr
      +i2 = (i + 1 : U32)
      local(c, i2, y2, arrive(KNil{}, is_nan(y2), y2, i2, rights, F32.add(visits, 1.0)), Array.get(F32, ys, (i2 + 1 : U32)), Array.set(U32, lefts, i, 0), start, (opening_nans + 1 : U32), unbounded)
    case 1n+c PopsAll{rights, +visits}:
      (ys, +y2) = yr
      +i2 = (i + 1 : U32)
      local(c, i2, y2, arrive(KCon{i, y, KNil{}}, is_nan(y2), y2, i2, rights, visits), Array.get(F32, ys, (i2 + 1 : U32)), lefts, start, opening_nans, UCon{i, y, unbounded})
    case 1n+c Bounded{+first, +below, st, rights, +visits}:
      (ys, +y2) = yr
      +i2 = (i + 1 : U32)
      +l = (i - first : U32)
      local(c, i2, y2, arrive(KCon{i, key(y, below), st}, is_nan(y2), y2, i2, rights, F32.add(visits, U32.to_f32((l + 1 : U32)))), Array.get(F32, ys, (i2 + 1 : U32)), Array.set(U32, lefts, i, l), start, opening_nans, unbounded)
    case 0n OpensWithNaN{rights, +visits}:
      (ys, y2) = yr
      Local{Block{start, (opening_nans + 1 : U32), unbounded, KNil{}, F32.add(visits, 1.0)}, Cols{ys, Array.set(U32, lefts, i, 0), rights}}
    case 0n PopsAll{rights, +visits}:
      (ys, y2) = yr
      Local{Block{start, opening_nans, UCon{i, y, unbounded}, KCon{i, y, KNil{}}, visits}, Cols{ys, lefts, rights}}
    case 0n Bounded{+first, +below, st, rights, +visits}:
      (ys, y2) = yr
      +l = (i - first : U32)
      Local{Block{start, opening_nans, unbounded, KCon{i, key(y, below), st}, F32.add(visits, U32.to_f32((l + 1 : U32)))}, Cols{ys, Array.set(U32, lefts, i, l), rights}}

def block_pass(count: Nat, +s: U32, yr: Array<F32> & F32, lefts: Array<U32>, rights: Array<U32>) -> Local:
  match count:
    case 0n:
      (ys, y) = yr
      Local{Block{s, 0, UNil{}, KNil{}, 0.0}, Cols{ys, lefts, rights}}
    case 1n+c:
      (ys, +y) = yr
      local(c, s, y, arrive(KNil{}, is_nan(y), y, s, rights, 0.0), Array.get(F32, ys, (s + 1 : U32)), lefts, s, 0, UNil{})

type Merged is Type:
  Merged{st: Stack, lefts: Array<U32>, rights: Array<U32>, visits: F32}

def push_with_key(count: Nat, +i: U32, +k: F32, st: Stack) -> Stack:
  match count:
    case 0n:
      st
    case 1n+c:
      push_with_key(c, (i + 1 : U32), k, KCon{i, k, st})

def push_opening_nans(count: Nat, +i: U32, st: Stack) -> Stack:
  match st:
    case KCon{+j, +kj, rest}:
      push_with_key(count, i, kj, KCon{j, kj, rest})
    case KNil{}:
      push_with_key(count, i, inf(), KNil{})

def pops_from(st: Stack, +y: F32, +i: U32, rights: Array<U32>, +visits: F32) -> Popped:
  match st:
    case KCon{+j, +kj, rest}:
      pops(rest, F32.is_gt(y, kj), y, i, j, kj, rights, visits)
    case KNil{}:
      Popped{0, inf(), KNil{}, rights, visits}

def set_left(+i: U32, lefts: Array<U32>, p: Popped) -> Merged:
  Popped{+first, below, st, rights, +visits} = p
  +l = (i - first : U32)
  Merged{st, Array.set(U32, lefts, i, l), rights, F32.add(visits, U32.to_f32((l + 1 : U32)))}

def in_order(u: Unbounded, acc: Unbounded) -> Unbounded:
  match u:
    case UNil{}:
      acc
    case UCon{i, y, next}:
      in_order(next, UCon{i, y, acc})

def bound_unbounded(u: Unbounded, m: Merged) -> Merged:
  match u:
    case UNil{}:
      m
    case UCon{+i, +y, next}:
      Merged{st, lefts, rights, +visits} = m
      bound_unbounded(next, set_left(i, lefts, pops_from(st, y, i, rights, visits)))

def onto(st: Stack, acc: Stack) -> Stack:
  match st:
    case KNil{}:
      acc
    case KCon{j, k, rest}:
      onto(rest, KCon{j, k, acc})

def push_block_stack(st: Stack, m: Merged) -> Merged:
  Merged{g, lefts, rights, visits} = m
  Merged{onto(onto(st, KNil{}), g), lefts, rights, visits}

# The merge replays the stack over every point before the block. The points
# the block's own stack could not bound pop it in order; the others sit on
# the block's stack, which goes on top.
def merge_block(b: Block, m: Merged) -> Merged:
  Block{+start, +opening_nans, unbounded, st, +visits} = b
  Merged{g, lefts, rights, +v} = m
  push_block_stack(st, bound_unbounded(in_order(unbounded, UNil{}), Merged{push_opening_nans(U32.to_nat(opening_nans), start, g), lefts, rights, F32.add(v, visits)}))

# Bend matches only parameters, so a read's result must arrive as one: a
# sweep reads y and x at `ahead`, where the next sweep starts, and hands them
# over. The sweeps read x through `x_at`, so x as the index costs no read.
type Walked is Type:
  Walked{yr: Array<F32> & F32, xr: Array<F32> & F32, es: Edges}

def at_index(xs: Array<F32>, +j: U32) -> Array<F32> & F32:
  (xs, U32.to_f32(j))

def natural_right(~x_at: Array<F32> -> U32 -> Array<F32> & F32, count: Nat, +j: U32, yr: Array<F32> & F32, xr: Array<F32> & F32, +k: Weight, +lo: F32, +hi: F32, +ia: U32, +xa: F32, +ya: F32, +scale_a: F32, +best: F32, es: Edges, +ahead: U32) -> Walked:
  match count:
    case 0n:
      (ys, yb) = yr
      (xs, xb) = xr
      Walked{Array.get(F32, ys, ahead), Array.get(F32, xs, ahead), es}
    case 1n+c:
      (ys, +yb) = yr
      (xs, +xb) = xr
      +s = F32.div(F32.sub(yb, ya), F32.sub(xb, xa))
      +seen = clears(F32.is_gt(s, best), s, best, scale_a, xb, yb)
      +j2 = (j + 1 : U32)
      natural_right(~x_at, c, j2, Array.get(F32, ys, j2), x_at(xs, j2), k, lo, hi, ia, xa, ya, scale_a, pick(seen, s, best), add_right(seen, k, lo, hi, ia, j, xa, xb, ya, yb, s, es), ahead)

def natural_left(~x_at: Array<F32> -> U32 -> Array<F32> & F32, count: Nat, +j: U32, yr: Array<F32> & F32, xr: Array<F32> & F32, +dir: Direction, +k: Weight, +lo: F32, +hi: F32, +ia: U32, +xa: F32, +ya: F32, +scale_a: F32, +best: F32, es: Edges, +ahead: U32) -> Walked:
  match count:
    case 0n:
      (ys, yb) = yr
      (xs, xb) = xr
      Walked{Array.get(F32, ys, ahead), Array.get(F32, xs, ahead), es}
    case 1n+c:
      (ys, +yb) = yr
      (xs, +xb) = xr
      +s = F32.div(F32.sub(yb, ya), F32.neg(F32.sub(xb, xa)))
      +seen = clears(F32.is_gt(s, best), s, best, scale_a, xb, yb)
      +j2 = (j - 1 : U32)
      natural_left(~x_at, c, j2, Array.get(F32, ys, j2), x_at(xs, j2), dir, k, lo, hi, ia, xa, ya, scale_a, pick(seen, s, best), add_left(seen, dir, k, lo, hi, ia, j, xa, xb, ya, yb, F32.neg(s), es), ahead)

def horizontal_right(~x_at: Array<F32> -> U32 -> Array<F32> & F32, count: Nat, +j: U32, yr: Array<F32> & F32, xr: Array<F32> & F32, +k: Weight, +lo: F32, +hi: F32, +ia: U32, +xa: F32, +ya: F32, +best: F32, es: Edges, +ahead: U32) -> Walked:
  match count:
    case 0n:
      (ys, yb) = yr
      (xs, xb) = xr
      Walked{Array.get(F32, ys, ahead), Array.get(F32, xs, ahead), es}
    case 1n+c:
      (ys, +yb) = yr
      (xs, xb) = xr
      +seen = F32.is_gt(yb, best)
      +j2 = (j + 1 : U32)
      horizontal_right(~x_at, c, j2, Array.get(F32, ys, j2), x_at(xs, j2), k, lo, hi, ia, xa, ya, pick(seen, yb, best), add_right(seen, k, lo, hi, ia, j, xa, xb, ya, yb, nan(), es), ahead)

def horizontal_left(~x_at: Array<F32> -> U32 -> Array<F32> & F32, count: Nat, +j: U32, yr: Array<F32> & F32, xr: Array<F32> & F32, +dir: Direction, +k: Weight, +lo: F32, +hi: F32, +ia: U32, +xa: F32, +ya: F32, +best: F32, es: Edges, +ahead: U32) -> Walked:
  match count:
    case 0n:
      (ys, yb) = yr
      (xs, xb) = xr
      Walked{Array.get(F32, ys, ahead), Array.get(F32, xs, ahead), es}
    case 1n+c:
      (ys, +yb) = yr
      (xs, xb) = xr
      +seen = F32.is_gt(yb, best)
      +j2 = (j - 1 : U32)
      horizontal_left(~x_at, c, j2, Array.get(F32, ys, j2), x_at(xs, j2), dir, k, lo, hi, ia, xa, ya, pick(seen, yb, best), add_left(seen, dir, k, lo, hi, ia, j, xa, xb, ya, yb, nan(), es), ahead)

# Each sweep, with x as the index (`index`) or read from `xs`.
def right_sweep(g: Visibility, index: Bool, count: Nat, yr: Array<F32> & F32, xs: Array<F32>, +k: Weight, +lo: F32, +hi: F32, +ia: U32, +xa: F32, +ya: F32, es: Edges) -> Walked:
  match g index:
    case Natural{} True{}:
      natural_right(~(a => +j => at_index(a, j)), count, (ia + 1 : U32), yr, at_index(xs, (ia + 1 : U32)), k, lo, hi, ia, xa, ya, scale(xa, ya), neg_inf(), es, (ia - 1 : U32))
    case Natural{} False{}:
      natural_right(~(a => +j => Array.get(F32, a, j)), count, (ia + 1 : U32), yr, Array.get(F32, xs, (ia + 1 : U32)), k, lo, hi, ia, xa, ya, scale(xa, ya), neg_inf(), es, (ia - 1 : U32))
    case Horizontal{} True{}:
      horizontal_right(~(a => +j => at_index(a, j)), count, (ia + 1 : U32), yr, at_index(xs, (ia + 1 : U32)), k, lo, hi, ia, xa, ya, neg_inf(), es, (ia - 1 : U32))
    case Horizontal{} False{}:
      horizontal_right(~(a => +j => Array.get(F32, a, j)), count, (ia + 1 : U32), yr, Array.get(F32, xs, (ia + 1 : U32)), k, lo, hi, ia, xa, ya, neg_inf(), es, (ia - 1 : U32))

def left_sweep(g: Visibility, index: Bool, count: Nat, +dir: Direction, +k: Weight, +lo: F32, +hi: F32, +ia: U32, +xa: F32, +ya: F32, w: Walked) -> Walked:
  match g index:
    case Natural{} True{}:
      Walked{yr, xr, es} = w
      (xs, xv) = xr
      natural_left(~(a => +j => at_index(a, j)), count, (ia - 1 : U32), yr, at_index(xs, (ia - 1 : U32)), dir, k, lo, hi, ia, xa, ya, scale(xa, ya), neg_inf(), es, (ia + 1 : U32))
    case Natural{} False{}:
      Walked{yr, xr, es} = w
      (xs, xv) = xr
      natural_left(~(a => +j => Array.get(F32, a, j)), count, (ia - 1 : U32), yr, Array.get(F32, xs, (ia - 1 : U32)), dir, k, lo, hi, ia, xa, ya, scale(xa, ya), neg_inf(), es, (ia + 1 : U32))
    case Horizontal{} True{}:
      Walked{yr, xr, es} = w
      (xs, xv) = xr
      horizontal_left(~(a => +j => at_index(a, j)), count, (ia - 1 : U32), yr, at_index(xs, (ia - 1 : U32)), dir, k, lo, hi, ia, xa, ya, neg_inf(), es, (ia + 1 : U32))
    case Horizontal{} False{}:
      Walked{yr, xr, es} = w
      (xs, xv) = xr
      horizontal_left(~(a => +j => Array.get(F32, a, j)), count, (ia - 1 : U32), yr, Array.get(F32, xs, (ia - 1 : U32)), dir, k, lo, hi, ia, xa, ya, neg_inf(), es, (ia + 1 : U32))

type Out is Type:
  Out{cols: Cols, xs: Array<F32>, es: Edges}

def points(count: Nat, +i: U32, lr: Array<U32> & U32, rr: Array<U32> & U32, w: Walked, +index: Bool, +g: Visibility, +dir: Direction, +k: Weight, +lo: F32, +hi: F32) -> Out:
  match count:
    case 0n:
      (lefts, l) = lr
      (rights, r) = rr
      Walked{yr, xr, es} = w
      (ys, y) = yr
      (xs, x) = xr
      Out{Cols{ys, lefts, rights}, xs, es}
    case 1n+c:
      (lefts, +l) = lr
      (rights, +r) = rr
      Walked{yr, xr, es} = w
      (ys, +y) = yr
      (xs, +xv) = xr
      +x = pick(index, U32.to_f32(i), xv)
      +i2 = (i + 1 : U32)
      points(c, i2, Array.get(U32, lefts, i2), Array.get(U32, rights, i2), left_sweep(g, index, U32.to_nat(l), dir, k, lo, hi, i, x, y, right_sweep(g, index, U32.to_nat(r), Array.get(F32, ys, i2), xs, k, lo, hi, i, x, y, es)), index, g, dir, k, lo, hi)

def edges_of(o: Out) -> Edges:
  Out{cols, xs, es} = o
  es

def swept(+index: Bool, +g: Visibility, +dir: Direction, +k: Weight, +lo: F32, +hi: F32, +n: U32, ys: Array<F32>, xs: Array<F32>, lefts: Array<U32>, r: Array<U32> & F32) -> Edges:
  (rights, visits) = r
  edges_of(points(U32.to_nat(n), 0, Array.get(U32, lefts, 0), Array.get(U32, rights, 0), Walked{Array.get(F32, ys, 0), Array.get(F32, xs, 0), ENil{}}, index, g, dir, k, lo, hi))

def bounded(+index: Bool, +g: Visibility, +dir: Direction, +k: Weight, +lo: F32, +hi: F32, +n: U32, ys: Array<F32>, xs: Array<F32>, m: Merged) -> Edges:
  Merged{st, lefts, rights, +visits} = m
  swept(index, g, dir, k, lo, hi, n, ys, xs, lefts, flush(st, n, rights, visits))

def stacked(+index: Bool, +g: Visibility, +dir: Direction, +k: Weight, +lo: F32, +hi: F32, +n: U32, xs: Array<F32>, l: Local) -> Edges:
  Local{b, c} = l
  Cols{ys, lefts, rights} = c
  bounded(index, g, dir, k, lo, hi, n, ys, xs, merge_block(b, Merged{KNil{}, lefts, rights, 0.0}))

# An array with room for `n` slots, indexed from 0.
def slots(+n: U32) -> Array<U32>:
  Array.new(U32, Nat.add(1n, U32.log2(n)), 0)

# A stand-in for `xs` when x is the index, which no sweep reads.
def no_xs() -> Array<F32>:
  Array.new(F32, 0n, 0.0)

def built(+index: Bool, +g: Visibility, +dir: Direction, +k: Weight, +lo: F32, +hi: F32, ys: Array<F32>, xs: Array<F32>, +n: U32) -> Edges:
  stacked(index, g, dir, k, lo, hi, n, xs, block_pass(U32.to_nat(n), 0, Array.get(F32, ys, 0), slots(n), slots(n)))

# The graph of the `n` values `ys` at `xs`, on one thread, as one block.
# `lo` and `hi` bound the weights, as ts2vg's min_weight and max_weight;
# pass neg_inf() and inf() for no bound. The x of `Index{}` is the index as
# an F32, exact for up to 2^24 values; the x of `At{xs}` must increase.
# parallel.bend builds the same graph on every thread, and relies on
# Base's @unsafe Array.fork.
def visibility(+g: Visibility, +dir: Direction, +k: Weight, +lo: F32, +hi: F32, ys: Array<F32>, xs: Xs, +n: U32) -> Edges:
  match xs:
    case Index{}:
      built(True{}, g, dir, k, lo, hi, ys, no_xs(), n)
    case At{a}:
      built(False{}, g, dir, k, lo, hi, ys, a, n)

# Degrees: each edge adds one to the degree of both of its ends, as ts2vg's
# degrees_in + degrees_out.

def added(r: Array<U32> & U32) -> Array<U32>:
  (d, old) = r
  d

def atomic_bump(d: Array<U32>, +i: U32) -> Array<U32>:
  added(Array.atomic.add(d, i, 1))

# The degrees of the nodes of `es`, added into `d`; parallel.bend counts
# them on every thread.
def degrees.into(es: Edges, d: Array<U32>) -> Array<U32>:
  match es:
    case ENil{}:
      d
    case ECon{s, t, w, next}:
      degrees.into(next, atomic_bump(atomic_bump(d, s), t))
    case EJoin{a, b}:
      degrees.into(b, degrees.into(a, d))

# Limited penetrable visibility graphs, as ts2vg 1.2.4's _natural_penetrable
# and _horizontal_penetrable build them, in F32: every point sweeps the
# points right of it, and an edge may cross up to `limit` points. The sweeps
# are independent, so the points split into parallel ranges of equal work.

# The points, in a list the parallel ranges share.
type Pts is Data:
  PNil{}
  PCon{i: U32, x: F32, y: F32, next: Pts}

# The points of `ys` and `xs` from index `i` down to 0, onto `acc`; `yr`
# and `xr` hold y and x at `i`, and x is the index if `index` says so. The
# last read, at index -1, wraps around.
def penetrable.points(count: Nat, +i: U32, yr: Array<F32> & F32, xr: Array<F32> & F32, +index: Bool, acc: Pts) -> Pts:
  match count:
    case 0n:
      (ys, y) = yr
      (xs, x) = xr
      acc
    case 1n+c:
      (ys, +y) = yr
      (xs, +x) = xr
      +i2 = (i - 1 : U32)
      penetrable.points(c, i2, Array.get(F32, ys, i2), Array.get(F32, xs, i2), index, PCon{i, pick(index, U32.to_f32(i), x), y, acc})

# The `limit + 1` largest slopes (or heights) a sweep has accepted, as ts2vg's
# max_slopes; the sweep accepts a point above the smallest of them.
type Tops is Data:
  TNil{}
  TCon{v: F32, next: Tops}

# The position and value of the first smallest top.
type Low is Data:
  Low{k: Nat, v: F32}

def tops_new(n: Nat) -> Tops:
  match n:
    case 0n:
      TCon{neg_inf(), TNil{}}
    case 1n+p:
      TCon{neg_inf(), tops_new(p)}

def pick_low(c: Bool, a: Low, b: Low) -> Low:
  match c:
    case True{}:
      a
    case False{}:
      b

def low_from(ts: Tops, +k: Nat, +best: Low) -> Low:
  match ts:
    case TNil{}:
      best
    case TCon{+v, next}:
      Low{bk, +bv} = best
      low_from(next, 1n+k, pick_low(F32.is_lt(v, bv), Low{k, v}, Low{bk, bv}))

def lowest(ts: Tops) -> Low:
  low_from(ts, 0n, Low{0n, inf()})

def Low.v(+l: Low) -> F32:
  Low{k, v} = l
  v

def set_at(k: Nat, ts: Tops, v: F32) -> Tops:
  match k ts:
    case 0n TCon{old, next}:
      TCon{v, next}
    case 1n+p TCon{old, next}:
      TCon{old, set_at(p, next, v)}
    case _ TNil{}:
      TNil{}

# How many tops a natural edge with slope `s` does not clear, as ts2vg's
# num_penetrations weight.
def blocked_natural(ts: Tops, +s: F32, +t: F32, +n: F32) -> F32:
  match ts:
    case TNil{}:
      n
    case TCon{v, next}:
      blocked_natural(next, s, t, pick(greater(s, v, t), n, F32.add(n, 1.0)))

def blocked_horizontal(ts: Tops, +ya: F32, +yb: F32, +n: F32) -> F32:
  match ts:
    case TNil{}:
      n
    case TCon{+v, next}:
      blocked_horizontal(next, ya, yb, pick(F32.is_le(ya, v) || F32.is_le(yb, v), F32.add(n, 1.0), n))

# ts2vg's add_edge with a known weight: NaN means the weight function
# computes it.
def add_known(+k: Weight, +lo: F32, +hi: F32, i1: U32, i2: U32, +x1: F32, +x2: F32, +y1: F32, +y2: F32, +s: F32, +known: F32, es: Edges) -> Edges:
  +w = pick(is_nan(known), weight(k, x1, x2, y1, y2, s), known)
  put(F32.is_le(w, lo) || F32.is_ge(w, hi), i1, i2, w, es)

# The edge from a to b, or from b to a for top_to_bottom when b is higher.
def add_oriented(down: Bool, +k: Weight, +lo: F32, +hi: F32, ia: U32, ib: U32, xa: F32, xb: F32, ya: F32, yb: F32, s: F32, known: F32, es: Edges) -> Edges:
  match down:
    case True{}:
      add_known(k, lo, hi, ib, ia, xb, xa, yb, ya, s, known, es)
    case False{}:
      add_known(k, lo, hi, ia, ib, xa, xb, ya, yb, s, known, es)

def is_down(dir: Direction, +ya: F32, +yb: F32) -> Bool:
  match dir:
    case TopToBottom{}:
      F32.is_gt(yb, ya)
    case _:
      False{}

def is_count(k: Weight) -> Bool:
  match k:
    case NumPenetrations{}:
      True{}
    case _:
      False{}

def natural_edge(+dir: Direction, +k: Weight, +lo: F32, +hi: F32, ia: U32, ib: U32, +xa: F32, +xb: F32, +ya: F32, +yb: F32, +s: F32, +scale_a: F32, ts: Tops, es: Edges) -> Edges:
  +known = pick(is_count(k), blocked_natural(ts, s, tol(scale_a, xb, yb), 0.0), nan())
  add_oriented(is_down(dir, ya, yb), k, lo, hi, ia, ib, xa, xb, ya, yb, s, known, es)

def horizontal_edge(+dir: Direction, +k: Weight, +lo: F32, +hi: F32, ia: U32, ib: U32, +xa: F32, xb: F32, +ya: F32, +yb: F32, ts: Tops, es: Edges) -> Edges:
  +known = pick(is_count(k), blocked_horizontal(ts, ya, yb, 0.0), nan())
  add_oriented(is_down(dir, ya, yb), k, lo, hi, ia, ib, xa, xb, ya, yb, nan(), known, es)

# The sweep of point a over the points right of it: ts2vg's inner loop. A
# point b the sweep sees replaces the smallest top and adds its edge at the
# next step, when `up` says so, so a step after an unseen point calls no
# def that recurses.
def natural_sweep(pts: Pts, up: Bool, +dir: Direction, +k: Weight, +lo: F32, +hi: F32, +ia: U32, +xa: F32, +ya: F32, +scale_a: F32, +ts: Tops, low: Low, +ib: U32, +xb: F32, +yb: F32, +sb: F32, es: Edges) -> Edges:
  match pts up:
    case PNil{} False{}:
      es
    case PNil{} True{}:
      natural_edge(dir, k, lo, hi, ia, ib, xa, xb, ya, yb, sb, scale_a, ts, es)
    case PCon{+ic, +xc, +yc, next} False{}:
      Low{+lk, +lv} = low
      +s = F32.div(F32.sub(yc, ya), F32.sub(xc, xa))
      natural_sweep(next, clears(F32.is_gt(s, lv), s, lv, scale_a, xc, yc), dir, k, lo, hi, ia, xa, ya, scale_a, ts, Low{lk, lv}, ic, xc, yc, s, es)
    case PCon{+ic, +xc, +yc, next} True{}:
      Low{+lk, lv} = low
      +after = set_at(lk, ts, sb)
      +now = lowest(after)
      +s = F32.div(F32.sub(yc, ya), F32.sub(xc, xa))
      natural_sweep(next, clears(F32.is_gt(s, Low.v(now)), s, Low.v(now), scale_a, xc, yc), dir, k, lo, hi, ia, xa, ya, scale_a, after, now, ic, xc, yc, s, natural_edge(dir, k, lo, hi, ia, ib, xa, xb, ya, yb, sb, scale_a, ts, es))

# The same for the horizontal sweep, which stops once the smallest top is
# above a: no later point can be seen.
def horizontal_sweep(pts: Pts, up: Bool, stop: Bool, +dir: Direction, +k: Weight, +lo: F32, +hi: F32, +ia: U32, +xa: F32, +ya: F32, +ts: Tops, low: Low, +ib: U32, +xb: F32, +yb: F32, es: Edges) -> Edges:
  match pts up stop:
    case _ False{} True{}:
      es
    case PNil{} False{} False{}:
      es
    case PNil{} True{} _:
      horizontal_edge(dir, k, lo, hi, ia, ib, xa, xb, ya, yb, ts, es)
    case PCon{+ic, xc, +yc, next} False{} False{}:
      Low{+lk, +lv} = low
      horizontal_sweep(next, F32.is_gt(ya, lv) && F32.is_gt(yc, lv), False{}, dir, k, lo, hi, ia, xa, ya, ts, Low{lk, lv}, ic, xc, yc, es)
    case PCon{+ic, xc, +yc, next} True{} _:
      Low{+lk, lv} = low
      +after = set_at(lk, ts, yb)
      +now = lowest(after)
      horizontal_sweep(next, F32.is_gt(ya, Low.v(now)) && F32.is_gt(yc, Low.v(now)), F32.is_gt(Low.v(now), ya), dir, k, lo, hi, ia, xa, ya, after, now, ic, xc, yc, horizontal_edge(dir, k, lo, hi, ia, ib, xa, xb, ya, yb, ts, es))

def sweep(g: Visibility, +dir: Direction, +k: Weight, +lo: F32, +hi: F32, +limit: Nat, ia: U32, +xa: F32, +ya: F32, pts: Pts, es: Edges) -> Edges:
  match g:
    case Natural{}:
      natural_sweep(pts, False{}, dir, k, lo, hi, ia, xa, ya, scale(xa, ya), tops_new(limit), Low{0n, neg_inf()}, 0, 0.0, 0.0, 0.0, es)
    case Horizontal{}:
      horizontal_sweep(pts, False{}, False{}, dir, k, lo, hi, ia, xa, ya, tops_new(limit), Low{0n, neg_inf()}, 0, 0.0, 0.0, es)

# The sweeps of the first `count` points of `pts`, one rope each: ts2vg's
# outer loop.
def sweeps(pts: Pts, count: Nat, +g: Visibility, +dir: Direction, +k: Weight, +lo: F32, +hi: F32, +limit: Nat) -> Edges:
  match pts count:
    case PCon{i, x, y, +next} 1n+c:
      EJoin{sweep(g, dir, k, lo, hi, limit, i, x, y, next, ENil{}), sweeps(next, c, g, dir, k, lo, hi, limit)}
    case _ _:
      ENil{}

def drop(n: Nat, pts: Pts) -> Pts:
  match n pts:
    case 1n+p PCon{i, x, y, next}:
      drop(p, next)
    case _ _:
      pts

# How many of the first `count` of `len` points do half the sweeps' work. A
# natural sweep walks every point right of its start, so the first c starts
# walk c (2 len - 1 - c) / 2 points; a horizontal sweep stops early, so
# halving the starts is close enough.
def first_half(g: Visibility, +len: U32, +count: U32) -> U32:
  match g:
    case Natural{}:
      +b = F32.sub(F32.mul(2.0, U32.to_f32(len)), 1.0)
      +c = U32.to_f32(count)
      U32.min(count, F32.to_u32(F32.div(F32.sub(b, F32.sqrt(F32.sub(F32.mul(b, b), F32.mul(2.0, F32.mul(c, F32.sub(b, c)))))), 2.0)))
    case Horizontal{}:
      U32.div(count, 2)

# The sweeps of the first `count` points of `pts`, as two halves of equal
# work in parallel, `depth` times over. `len` and `cu` are `pts`'s length
# and `count` as U32; they only place the cut.
def split(depth: Nat, +g: Visibility, +dir: Direction, +k: Weight, +lo: F32, +hi: F32, +limit: Nat, +pts: Pts, +len: U32, +cu: U32, +count: Nat) -> Edges:
  match depth:
    case 0n:
      sweeps(pts, count, g, dir, k, lo, hi, limit)
    case 1n++d:
      +c1u = first_half(g, len, cu)
      +c1 = Nat.min(count, U32.to_nat(c1u))
      a b = split(d, g, dir, k, lo, hi, limit, pts, len, c1u, c1) split(d, g, dir, k, lo, hi, limit, drop(c1, pts), (len - c1u : U32), (cu - c1u : U32), Nat.sub(count, c1))
      EJoin{a, b}

def penetrable.built(+index: Bool, +g: Visibility, +dir: Direction, +k: Weight, +lo: F32, +hi: F32, +limit: U32, ys: Array<F32>, xs: Array<F32>, +n: U32) -> Edges:
  split(7n, g, dir, k, lo, hi, U32.to_nat(limit), penetrable.points(U32.to_nat(n), (n - 1 : U32), Array.get(F32, ys, (n - 1 : U32)), Array.get(F32, xs, (n - 1 : U32)), index, PNil{}), n, n, U32.to_nat(n))

# The limited penetrable graph of the `n` values `ys` at `xs`, crossing at
# most `limit` points. The x of `Index{}` is the index as an F32, exact
# for up to 2^24 values; the x of `At{xs}` must increase.
def penetrable(+g: Visibility, +dir: Direction, +k: Weight, +lo: F32, +hi: F32, +limit: U32, ys: Array<F32>, xs: Xs, +n: U32) -> Edges:
  match xs:
    case Index{}:
      penetrable.built(True{}, g, dir, k, lo, hi, limit, ys, no_xs(), n)
    case At{a}:
      penetrable.built(False{}, g, dir, k, lo, hi, limit, ys, a, n)

# The library

# ts2vg's defaults for the visibility `v`: undirected, unweighted, every
# weight kept, no point crossed.
def options(v: Visibility) -> Options:
  Options{v, Undirected{}, Unweighted{}, neg_inf(), inf(), 0}

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
  Series{n, column(n, ys), Index{}}

# The series of the values `ys`, each at its index.
def series(+ys: List<&2, F32>) -> Series:
  counted(length(ys, 0), ys)

def counted_at(+n: U32, xs: List<&2, F32>, ys: List<&2, F32>) -> Series:
  Series{n, column(n, ys), At{column(n, xs)}}

# The series of the values `ys` at `xs`, which must hold as many values,
# increasing.
def series_at(xs: List<&2, F32>, +ys: List<&2, F32>) -> Series:
  counted_at(length(ys, 0), xs, ys)

def chosen(is_visibility: Bool, +g: Visibility, +dir: Direction, +k: Weight, +lo: F32, +hi: F32, +limit: U32, ys: Array<F32>, xs: Xs, +n: U32) -> Edges:
  match is_visibility:
    case True{}:
      visibility(g, dir, k, lo, hi, ys, xs, n)
    case False{}:
      penetrable(g, dir, k, lo, hi, limit, ys, xs, n)

# The edges of the graph of `s` with the options `o`, as ts2vg's `build`
# makes them. The natural and horizontal graphs run on one thread, and the
# limited penetrable ones split their sweeps among every thread.
def build(o: Options, s: Series) -> Graph:
  Options{g, +dir, k, lo, hi, +limit} = o
  Series{+n, ys, xs} = s
  Graph{n, dir, chosen(U32.is_zero(limit), g, dir, k, lo, hi, limit, ys, xs, n)}

# What to read off the edges

# `f(acc, src, dst, w)` over every edge of `g`, in the order the rope
# holds them, from `acc`.
def fold.edges(~A: Type, ~f: A -> U32 -> U32 -> F32 -> A, es: Edges, acc: A) -> A:
  match es:
    case ENil{}:
      acc
    case ECon{s, t, w, next}:
      fold.edges(~A, ~f, next, f(acc, s, t, w))
    case EJoin{a, b}:
      fold.edges(~A, ~f, b, fold.edges(~A, ~f, a, acc))

def fold(~A: Type, ~f: A -> U32 -> U32 -> F32 -> A, g: Graph, acc: A) -> A:
  Graph{n, dir, es} = g
  fold.edges(~A, ~f, es, acc)

# The degree of each node of `g`, as ts2vg's `degrees`: the edges at the
# node, in either direction.
def degrees(g: Graph) -> Array<U32>:
  Graph{+n, dir, es} = g
  degrees.into(es, slots(n))

# Each half edge (u, v), from u to v, goes into two passes of a counting
# sort: by v, then by u, so each row ends up in increasing order.

def is_undirected(d: Direction) -> Bool:
  match d:
    case Undirected{}:
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

def count_halves(es: Edges, +both: Bool, c: Counts) -> Counts:
  match es:
    case ENil{}:
      c
    case ECon{+s, +t, w, next}:
      count_halves(next, both, count_half(both, t, s, count_half(True{}, s, t, c)))
    case EJoin{a, b}:
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

def by_target(es: Edges, +both: Bool, h: Halves) -> Halves:
  match es:
    case ENil{}:
      h
    case ECon{+s, +t, +w, next}:
      by_target(next, both, place_half(both, t, s, w, place_half(True{}, s, t, w, h)))
    case EJoin{a, b}:
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

def with_starts(es: Edges, +both: Bool, +h: U32, outs: Array<U32>, ins: Array<U32>) -> Adjacency:
  rows_from(h, Array.clone(U32, outs), by_target(es, both, Halves{ins, Array.new(U32, slots_for(h), 0), Array.new(U32, slots_for(h), 0), Array.new(F32, slots_for(h), 0.0)}))

def with_total(es: Edges, +both: Bool, r: Array<U32> & U32, ins: Array<U32>) -> Adjacency:
  (outs, +h) = r
  with_starts(es, both, h, outs, ins)

def tallied(es: Edges, +both: Bool, +n: U32, c: Counts) -> Adjacency:
  Counts{outs, ins} = c
  with_total(es, both, Array.get(U32, starts(U32.to_nat(n), 0, Array.get(U32, outs, 0), 0), n), starts(U32.to_nat(n), 0, Array.get(U32, ins, 0), 0))

# The rows of the nodes of `g`.
def adjacency(g: Graph) -> Adjacency:
  Graph{+n, +dir, +es} = g
  tallied(es, is_undirected(dir), n, count_halves(es, is_undirected(dir), Counts{Array.new(U32, slots_for(n), 0), Array.new(U32, slots_for(n), 0)}))
