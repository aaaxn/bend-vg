# Natural and horizontal visibility graphs, as ts2vg 1.2.4 builds them, in
# F32. Each def below that has a ts2vg twin does the same F32 operations in
# the same order as the twin does in float64.
import Base

# The points of a series, in order: the node index, x and y.
type Pts is Data:
  PNil{}
  PCon{i: U32, x: F32, y: F32, next: Pts}

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

# The edges, as a rope: ECon adds an edge and EJoin joins two ropes, so the
# two halves of a split join in one step.
type Edges is Data:
  ENil{}
  ECon{src: U32, dst: U32, w: F32, next: Edges}
  EJoin{a: Edges, b: Edges}

# F32 words

def from_bits(word: U32) -> F32:
  U32{bits} = word
  F32{bits}

def nan() -> F32:
  from_bits(2143289344)

def inf() -> F32:
  from_bits(2139095040)

def neg_inf() -> F32:
  from_bits(4286578688)

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
  Cols{xs: Array<F32>, ys: Array<F32>, lefts: Array<U32>, rights: Array<U32>}

type Counted is Type:
  Counted{cols: Cols, visits: F32}

def counted(xs: Array<F32>, ys: Array<F32>, lefts: Array<U32>, r: Array<U32> & F32) -> Counted:
  (rights, visits) = r
  Counted{Cols{xs, ys, lefts, rights}, visits}

def pass(pts: Pts, +i: U32, +x: F32, +y: F32, popped: Popped, xs: Array<F32>, ys: Array<F32>, lefts: Array<U32>) -> Counted:
  match pts popped:
    case PCon{+i2, +x2, +y2, next} Popped{+first, +below, st, rights, +visits}:
      +k = key(y, below)
      +l = (i - first : U32)
      pass(next, i2, x2, y2, pops(st, F32.is_gt(y2, k), y2, i2, i, k, rights, F32.add(visits, U32.to_f32((l + 1 : U32)))), Array.set(F32, xs, i, x), Array.set(F32, ys, i, y), Array.set(U32, lefts, i, l))
    case PNil{} Popped{+first, +below, st, rights, +visits}:
      +l = (i - first : U32)
      counted(Array.set(F32, xs, i, x), Array.set(F32, ys, i, y), Array.set(U32, lefts, i, l), flush(KCon{i, key(y, below), st}, (i + 1 : U32), rights, F32.add(visits, U32.to_f32((l + 1 : U32)))))

def columns(pts: Pts, +n: U32) -> Counted:
  match pts:
    case PCon{+i, +x, +y, next}:
      +d = Nat.add(1n, U32.log2(n))
      pass(next, i, x, y, Popped{0, inf(), KNil{}, Array.new(U32, d, 0), 0.0}, Array.new(F32, d, 0.0), Array.new(F32, d, 0.0), Array.new(U32, d, 0))
    case PNil{}:
      Counted{Cols{Array.new(F32, 0n, 0.0), Array.new(F32, 0n, 0.0), Array.new(U32, 0n, 0), Array.new(U32, 0n, 0)}, 0.0}

type Chunks is Data:
  CNil{}
  CCon{start: U32, count: U32, next: Chunks}

def close(full: Bool, +start: U32, +end: U32, cs: Chunks) -> Chunks:
  match full:
    case True{}:
      CCon{start, (end - start : U32), cs}
    case False{}:
      cs

type Cut is Type:
  Cut{lefts: Array<U32>, rights: Array<U32>, cs: Chunks, m: U32}

def cut(count: Nat, +i: U32, lr: Array<U32> & U32, rr: Array<U32> & U32, +start: U32, +acc: U32, +target: U32, cs: Chunks, +m: U32) -> Cut:
  match count:
    case 0n:
      (lefts, l) = lr
      (rights, r) = rr
      +last = U32.is_lt(start, i)
      Cut{lefts, rights, close(last, start, i, cs), pick_u32(last, (m + 1 : U32), m)}
    case 1n+c:
      (lefts, +l) = lr
      (rights, +r) = rr
      +w = (acc + l + r + 1 : U32)
      +full = U32.is_ge(w, target)
      +i2 = (i + 1 : U32)
      cut(c, i2, Array.get(U32, lefts, i2), Array.get(U32, rights, i2), pick_u32(full, i2, start), pick_u32(full, 0, w), target, close(full, start, i2, cs), pick_u32(full, (m + 1 : U32), m))

# The levels of the fork tree.
def depth() -> Nat:
  8n

# About two chunks for each of the tree's leaves.
def target(+visits: F32) -> U32:
  U32.max(1, F32.to_u32(F32.div(visits, U32.to_f32(U32.shln(4, depth())))))

type Halves is Data:
  Halves{a: Chunks, na: U32, b: Chunks, nb: U32}

def halve(k: Nat, cs: Chunks, +na: U32, +total: U32, acc: Chunks) -> Halves:
  match k cs:
    case 1n+q CCon{+start, +count, next}:
      halve(q, next, na, total, CCon{start, count, acc})
    case _ _:
      Halves{acc, na, cs, (total - na : U32)}

def halves(cs: Chunks, +m: U32) -> Halves:
  halve(U32.to_nat(U32.shr(m)), cs, U32.shr(m), m, CNil{})

def fork4(a: Array<F32> & Array<F32>, b: Array<F32> & Array<F32>, c: Array<U32> & Array<U32>, d: Array<U32> & Array<U32>) -> Cols & Cols:
  (a1, a2) = a
  (b1, b2) = b
  (c1, c2) = c
  (d1, d2) = d
  (Cols{a1, b1, c1, d1}, Cols{a2, b2, c2, d2})

def fork_cols(c: Cols) -> Cols & Cols:
  Cols{xs, ys, lefts, rights} = c
  fork4(Array.fork(F32, xs), Array.fork(F32, ys), Array.fork(U32, lefts), Array.fork(U32, rights))

# Bend matches only parameters, so a read's result must arrive as one: a
# sweep reads x and y at `ahead`, where the next sweep starts, and hands them
# over.
type Walked is Type:
  Walked{xr: Array<F32> & F32, yr: Array<F32> & F32, es: Edges}

def natural_right(count: Nat, +j: U32, xr: Array<F32> & F32, yr: Array<F32> & F32, +k: Weight, +lo: F32, +hi: F32, +ia: U32, +xa: F32, +ya: F32, +scale_a: F32, +best: F32, es: Edges, +ahead: U32) -> Walked:
  match count:
    case 0n:
      (xs, xb) = xr
      (ys, yb) = yr
      Walked{Array.get(F32, xs, ahead), Array.get(F32, ys, ahead), es}
    case 1n+c:
      (xs, +xb) = xr
      (ys, +yb) = yr
      +s = F32.div(F32.sub(yb, ya), F32.sub(xb, xa))
      +seen = clears(F32.is_gt(s, best), s, best, scale_a, xb, yb)
      +j2 = (j + 1 : U32)
      natural_right(c, j2, Array.get(F32, xs, j2), Array.get(F32, ys, j2), k, lo, hi, ia, xa, ya, scale_a, pick(seen, s, best), add_right(seen, k, lo, hi, ia, j, xa, xb, ya, yb, s, es), ahead)

def natural_left(count: Nat, +j: U32, xr: Array<F32> & F32, yr: Array<F32> & F32, +dir: Direction, +k: Weight, +lo: F32, +hi: F32, +ia: U32, +xa: F32, +ya: F32, +scale_a: F32, +best: F32, es: Edges, +ahead: U32) -> Walked:
  match count:
    case 0n:
      (xs, xb) = xr
      (ys, yb) = yr
      Walked{Array.get(F32, xs, ahead), Array.get(F32, ys, ahead), es}
    case 1n+c:
      (xs, +xb) = xr
      (ys, +yb) = yr
      +s = F32.div(F32.sub(yb, ya), F32.neg(F32.sub(xb, xa)))
      +seen = clears(F32.is_gt(s, best), s, best, scale_a, xb, yb)
      +j2 = (j - 1 : U32)
      natural_left(c, j2, Array.get(F32, xs, j2), Array.get(F32, ys, j2), dir, k, lo, hi, ia, xa, ya, scale_a, pick(seen, s, best), add_left(seen, dir, k, lo, hi, ia, j, xa, xb, ya, yb, F32.neg(s), es), ahead)

def horizontal_right(count: Nat, +j: U32, xr: Array<F32> & F32, yr: Array<F32> & F32, +k: Weight, +lo: F32, +hi: F32, +ia: U32, +xa: F32, +ya: F32, +best: F32, es: Edges, +ahead: U32) -> Walked:
  match count:
    case 0n:
      (xs, xb) = xr
      (ys, yb) = yr
      Walked{Array.get(F32, xs, ahead), Array.get(F32, ys, ahead), es}
    case 1n+c:
      (xs, xb) = xr
      (ys, +yb) = yr
      +seen = F32.is_gt(yb, best)
      +j2 = (j + 1 : U32)
      horizontal_right(c, j2, Array.get(F32, xs, j2), Array.get(F32, ys, j2), k, lo, hi, ia, xa, ya, pick(seen, yb, best), add_right(seen, k, lo, hi, ia, j, xa, xb, ya, yb, nan(), es), ahead)

def horizontal_left(count: Nat, +j: U32, xr: Array<F32> & F32, yr: Array<F32> & F32, +dir: Direction, +k: Weight, +lo: F32, +hi: F32, +ia: U32, +xa: F32, +ya: F32, +best: F32, es: Edges, +ahead: U32) -> Walked:
  match count:
    case 0n:
      (xs, xb) = xr
      (ys, yb) = yr
      Walked{Array.get(F32, xs, ahead), Array.get(F32, ys, ahead), es}
    case 1n+c:
      (xs, xb) = xr
      (ys, +yb) = yr
      +seen = F32.is_gt(yb, best)
      +j2 = (j - 1 : U32)
      horizontal_left(c, j2, Array.get(F32, xs, j2), Array.get(F32, ys, j2), dir, k, lo, hi, ia, xa, ya, pick(seen, yb, best), add_left(seen, dir, k, lo, hi, ia, j, xa, xb, ya, yb, nan(), es), ahead)

def right_sweep(g: Graph, count: Nat, xr: Array<F32> & F32, yr: Array<F32> & F32, +k: Weight, +lo: F32, +hi: F32, +ia: U32, +xa: F32, +ya: F32, es: Edges) -> Walked:
  match g:
    case Natural{}:
      natural_right(count, (ia + 1 : U32), xr, yr, k, lo, hi, ia, xa, ya, scale(xa, ya), neg_inf(), es, (ia - 1 : U32))
    case Horizontal{}:
      horizontal_right(count, (ia + 1 : U32), xr, yr, k, lo, hi, ia, xa, ya, neg_inf(), es, (ia - 1 : U32))

def left_sweep(g: Graph, count: Nat, +dir: Direction, +k: Weight, +lo: F32, +hi: F32, +ia: U32, +xa: F32, +ya: F32, w: Walked) -> Walked:
  match g:
    case Natural{}:
      Walked{xr, yr, es} = w
      natural_left(count, (ia - 1 : U32), xr, yr, dir, k, lo, hi, ia, xa, ya, scale(xa, ya), neg_inf(), es, (ia + 1 : U32))
    case Horizontal{}:
      Walked{xr, yr, es} = w
      horizontal_left(count, (ia - 1 : U32), xr, yr, dir, k, lo, hi, ia, xa, ya, neg_inf(), es, (ia + 1 : U32))

type Out is Type:
  Out{cols: Cols, es: Edges}

def points(count: Nat, +i: U32, lr: Array<U32> & U32, rr: Array<U32> & U32, w: Walked, +g: Graph, +dir: Direction, +k: Weight, +lo: F32, +hi: F32) -> Out:
  match count:
    case 0n:
      (lefts, l) = lr
      (rights, r) = rr
      Walked{xr, yr, es} = w
      (xs, x) = xr
      (ys, y) = yr
      Out{Cols{xs, ys, lefts, rights}, es}
    case 1n+c:
      (lefts, +l) = lr
      (rights, +r) = rr
      Walked{xr, yr, es} = w
      (xs, +x) = xr
      (ys, +y) = yr
      +i2 = (i + 1 : U32)
      points(c, i2, Array.get(U32, lefts, i2), Array.get(U32, rights, i2), left_sweep(g, U32.to_nat(l), dir, k, lo, hi, i, x, y, right_sweep(g, U32.to_nat(r), Array.get(F32, xs, i2), Array.get(F32, ys, i2), k, lo, hi, i, x, y, es)), g, dir, k, lo, hi)

def chunks(cs: Chunks, o: Out, +g: Graph, +dir: Direction, +k: Weight, +lo: F32, +hi: F32) -> Out:
  match cs:
    case CCon{+start, count, next}:
      Out{cols, es} = o
      Cols{xs, ys, lefts, rights} = cols
      chunks(next, points(U32.to_nat(count), start, Array.get(U32, lefts, start), Array.get(U32, rights, start), Walked{Array.get(F32, xs, start), Array.get(F32, ys, start), es}, g, dir, k, lo, hi), g, dir, k, lo, hi)
    case CNil{}:
      o

def edges_of(o: Out) -> Edges:
  Out{cols, es} = o
  es

# It forks nothing, so the runtime runs it once the tree has grown, on any
# idle thread; work done before a fork runs while the tree grows, on a few
# threads.
def leaf(cs: Chunks, c: Cols, +g: Graph, +dir: Direction, +k: Weight, +lo: F32, +hi: F32) -> Edges:
  edges_of(chunks(cs, Out{c, ENil{}}, g, dir, k, lo, hi))

def tree(depth: Nat, h: Halves, cc: Cols & Cols, +g: Graph, +dir: Direction, +k: Weight, +lo: F32, +hi: F32) -> Edges:
  match depth h:
    case 1n++d Halves{a, +na, b, +nb}:
      (c1, c2) = cc
      x y = tree(d, halves(a, na), fork_cols(c1), g, dir, k, lo, hi) tree(d, halves(b, nb), fork_cols(c2), g, dir, k, lo, hi)
      EJoin{x, y}
    case _ Halves{a, na, b, nb}:
      (c1, c2) = cc
      x y = leaf(a, c1, g, dir, k, lo, hi) leaf(b, c2, g, dir, k, lo, hi)
      EJoin{x, y}

def split(+g: Graph, +dir: Direction, +k: Weight, +lo: F32, +hi: F32, xs: Array<F32>, ys: Array<F32>, c: Cut) -> Edges:
  Cut{lefts, rights, cs, +m} = c
  tree(depth(), halves(cs, m), fork_cols(Cols{xs, ys, lefts, rights}), g, dir, k, lo, hi)

def built(+g: Graph, +dir: Direction, +k: Weight, +lo: F32, +hi: F32, +n: U32, c: Counted) -> Edges:
  Counted{cols, +visits} = c
  Cols{xs, ys, lefts, rights} = cols
  split(g, dir, k, lo, hi, xs, ys, cut(U32.to_nat(n), 0, Array.get(U32, lefts, 0), Array.get(U32, rights, 0), 0, 0, target(visits), CNil{}, 0))

# The graph of `n` points. `lo` and `hi` bound the weights, as ts2vg's
# min_weight and max_weight; pass neg_inf() and inf() for no bound.
def build(+g: Graph, +dir: Direction, +k: Weight, +lo: F32, +hi: F32, pts: Pts, +n: U32) -> Edges:
  built(g, dir, k, lo, hi, n, columns(pts, n))
