# Natural and horizontal visibility graphs, as ts2vg 1.2.4 builds them, in
# F32. Each def below that has a ts2vg twin does the same F32 operations in
# the same order as the twin does in float64.
import Base

type Graph is Data:
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
def right_sweep(g: Graph, index: Bool, count: Nat, yr: Array<F32> & F32, xs: Array<F32>, +k: Weight, +lo: F32, +hi: F32, +ia: U32, +xa: F32, +ya: F32, es: Edges) -> Walked:
  match g index:
    case Natural{} True{}:
      natural_right(~(a => +j => at_index(a, j)), count, (ia + 1 : U32), yr, at_index(xs, (ia + 1 : U32)), k, lo, hi, ia, xa, ya, scale(xa, ya), neg_inf(), es, (ia - 1 : U32))
    case Natural{} False{}:
      natural_right(~(a => +j => Array.get(F32, a, j)), count, (ia + 1 : U32), yr, Array.get(F32, xs, (ia + 1 : U32)), k, lo, hi, ia, xa, ya, scale(xa, ya), neg_inf(), es, (ia - 1 : U32))
    case Horizontal{} True{}:
      horizontal_right(~(a => +j => at_index(a, j)), count, (ia + 1 : U32), yr, at_index(xs, (ia + 1 : U32)), k, lo, hi, ia, xa, ya, neg_inf(), es, (ia - 1 : U32))
    case Horizontal{} False{}:
      horizontal_right(~(a => +j => Array.get(F32, a, j)), count, (ia + 1 : U32), yr, Array.get(F32, xs, (ia + 1 : U32)), k, lo, hi, ia, xa, ya, neg_inf(), es, (ia - 1 : U32))

def left_sweep(g: Graph, index: Bool, count: Nat, +dir: Direction, +k: Weight, +lo: F32, +hi: F32, +ia: U32, +xa: F32, +ya: F32, w: Walked) -> Walked:
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

def points(count: Nat, +i: U32, lr: Array<U32> & U32, rr: Array<U32> & U32, w: Walked, +index: Bool, +g: Graph, +dir: Direction, +k: Weight, +lo: F32, +hi: F32) -> Out:
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

def swept(+index: Bool, +g: Graph, +dir: Direction, +k: Weight, +lo: F32, +hi: F32, +n: U32, ys: Array<F32>, xs: Array<F32>, lefts: Array<U32>, r: Array<U32> & F32) -> Edges:
  (rights, visits) = r
  edges_of(points(U32.to_nat(n), 0, Array.get(U32, lefts, 0), Array.get(U32, rights, 0), Walked{Array.get(F32, ys, 0), Array.get(F32, xs, 0), ENil{}}, index, g, dir, k, lo, hi))

def bounded(+index: Bool, +g: Graph, +dir: Direction, +k: Weight, +lo: F32, +hi: F32, +n: U32, ys: Array<F32>, xs: Array<F32>, m: Merged) -> Edges:
  Merged{st, lefts, rights, +visits} = m
  swept(index, g, dir, k, lo, hi, n, ys, xs, lefts, flush(st, n, rights, visits))

def stacked(+index: Bool, +g: Graph, +dir: Direction, +k: Weight, +lo: F32, +hi: F32, +n: U32, xs: Array<F32>, l: Local) -> Edges:
  Local{b, c} = l
  Cols{ys, lefts, rights} = c
  bounded(index, g, dir, k, lo, hi, n, ys, xs, merge_block(b, Merged{KNil{}, lefts, rights, 0.0}))

def counts(+n: U32) -> Array<U32>:
  Array.new(U32, Nat.add(1n, U32.log2(n)), 0)

# A stand-in for `xs` when x is the index, which no sweep reads.
def no_xs() -> Array<F32>:
  Array.new(F32, 0n, 0.0)

def built(+index: Bool, +g: Graph, +dir: Direction, +k: Weight, +lo: F32, +hi: F32, ys: Array<F32>, xs: Array<F32>, +n: U32) -> Edges:
  stacked(index, g, dir, k, lo, hi, n, xs, block_pass(U32.to_nat(n), 0, Array.get(F32, ys, 0), counts(n), counts(n)))

# The graph of the `n` values `ys` at `xs`, on one thread, as one block.
# `lo` and `hi` bound the weights, as ts2vg's min_weight and max_weight;
# pass neg_inf() and inf() for no bound. The x of `Index{}` is the index as
# an F32, exact for up to 2^24 values; the x of `At{xs}` must increase.
# src/parallel.bend builds the same graph on every thread, and relies on
# Base's @unsafe Array.fork.
def build(+g: Graph, +dir: Direction, +k: Weight, +lo: F32, +hi: F32, ys: Array<F32>, xs: Xs, +n: U32) -> Edges:
  match xs:
    case Index{}:
      built(True{}, g, dir, k, lo, hi, ys, no_xs(), n)
    case At{a}:
      built(False{}, g, dir, k, lo, hi, ys, a, n)
