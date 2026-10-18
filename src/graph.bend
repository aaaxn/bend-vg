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

# An interval's highest point and its position in the interval.
type Pivot is Data:
  Pivot{i: U32, x: F32, y: F32, k: U32}

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

def natural_right(+k: Weight, +lo: F32, +hi: F32, +ia: U32, +xa: F32, +ya: F32, +scale_a: F32, pts: Pts, +best: F32, es: Edges) -> Edges:
  match pts:
    case PNil{}:
      es
    case PCon{ib, +xb, +yb, next}:
      +s = F32.div(F32.sub(yb, ya), F32.sub(xb, xa))
      +seen = clears(F32.is_gt(s, best), s, best, scale_a, xb, yb)
      natural_right(k, lo, hi, ia, xa, ya, scale_a, next, pick(seen, s, best), add_right(seen, k, lo, hi, ia, ib, xa, xb, ya, yb, s, es))

def natural_left(+dir: Direction, +k: Weight, +lo: F32, +hi: F32, +ia: U32, +xa: F32, +ya: F32, +scale_a: F32, pts: Pts, +best: F32, es: Edges) -> Edges:
  match pts:
    case PNil{}:
      es
    case PCon{ib, +xb, +yb, next}:
      +s = F32.div(F32.sub(yb, ya), F32.neg(F32.sub(xb, xa)))
      +seen = clears(F32.is_gt(s, best), s, best, scale_a, xb, yb)
      natural_left(dir, k, lo, hi, ia, xa, ya, scale_a, next, pick(seen, s, best), add_left(seen, dir, k, lo, hi, ia, ib, xa, xb, ya, yb, F32.neg(s), es))

def horizontal_right(+k: Weight, +lo: F32, +hi: F32, +ia: U32, +xa: F32, +ya: F32, pts: Pts, +best: F32, es: Edges) -> Edges:
  match pts:
    case PNil{}:
      es
    case PCon{ib, xb, +yb, next}:
      +seen = F32.is_gt(yb, best)
      horizontal_right(k, lo, hi, ia, xa, ya, next, pick(seen, yb, best), add_right(seen, k, lo, hi, ia, ib, xa, xb, ya, yb, nan(), es))

def horizontal_left(+dir: Direction, +k: Weight, +lo: F32, +hi: F32, +ia: U32, +xa: F32, +ya: F32, pts: Pts, +best: F32, es: Edges) -> Edges:
  match pts:
    case PNil{}:
      es
    case PCon{ib, xb, +yb, next}:
      +seen = F32.is_gt(yb, best)
      horizontal_left(dir, k, lo, hi, ia, xa, ya, next, pick(seen, yb, best), add_left(seen, dir, k, lo, hi, ia, ib, xa, xb, ya, yb, nan(), es))

def left_sweep(g: Graph, +dir: Direction, +k: Weight, +lo: F32, +hi: F32, ia: U32, +xa: F32, +ya: F32, pts: Pts, es: Edges) -> Edges:
  match g:
    case Natural{}:
      natural_left(dir, k, lo, hi, ia, xa, ya, scale(xa, ya), pts, neg_inf(), es)
    case Horizontal{}:
      horizontal_left(dir, k, lo, hi, ia, xa, ya, pts, neg_inf(), es)

def right_sweep(g: Graph, +k: Weight, +lo: F32, +hi: F32, ia: U32, +xa: F32, +ya: F32, pts: Pts, es: Edges) -> Edges:
  match g:
    case Natural{}:
      natural_right(k, lo, hi, ia, xa, ya, scale(xa, ya), pts, neg_inf(), es)
    case Horizontal{}:
      horizontal_right(k, lo, hi, ia, xa, ya, pts, neg_inf(), es)

# Divide and conquer: ts2vg's _compute_graph. The pivot is the first highest
# point; its sweeps add its edges, and the points left and right of it form
# two independent intervals, built in parallel. Each side is already ordered
# nearest the pivot first, so it becomes an interval as it is: the left side
# runs by decreasing index and the right side by increasing index.

# How an interval's points run: by increasing or by decreasing index.
type Walk is Data:
  Rightward{}
  Leftward{}

# Whether y beats `by`, the highest point so far, as ts2vg's argmax scans an
# interval by increasing index and takes a point above the best. That keeps
# the first highest point, and NaN only as the interval's first point.
# Walking leftward, an equal later point comes first, and a NaN best gives
# way. A leftward interval is a left side, whose first point is never NaN:
# ts2vg would have taken that point as the pivot.
def above(walk: Walk, +y: F32, +by: F32) -> Bool:
  match walk:
    case Rightward{}:
      F32.is_gt(y, by)
    case Leftward{}:
      F32.is_ge(y, by) || is_nan(by)

def argmax(+walk: Walk, pts: Pts, +bi: U32, +bx: F32, +by: F32, +bk: U32, +k: U32) -> Pivot:
  match pts:
    case PNil{}:
      Pivot{bi, bx, by, bk}
    case PCon{i, x, +y, next}:
      +up = above(walk, y, by)
      argmax(walk, next, pick_u32(up, i, bi), pick(up, x, bx), pick(up, y, by), pick_u32(up, k, bk), (k + 1 : U32))

# The first k points, reversed, and the points after the (k+1)-th.
def take_rev(k: Nat, pts: Pts, acc: Pts) -> Pts & Pts:
  match k pts:
    case 0n PCon{i, x, y, rest}:
      (acc, rest)
    case 1n+q PCon{i, x, y, rest}:
      take_rev(q, rest, PCon{i, x, y, acc})
    case _ PNil{}:
      (acc, PNil{})

# The points left and right of the pivot, each nearest first.
type Sides is Data:
  Sides{left: Pts, right: Pts}

# The sides of an interval walked in `walk`, from take_rev's cut at its pivot.
def sides(walk: Walk, parts: Pts & Pts) -> Sides:
  match walk:
    case Rightward{}:
      (before, after) = parts
      Sides{before, after}
    case Leftward{}:
      (before, after) = parts
      Sides{after, before}

# The steps of one interval. Bend has no mutual recursion and matches only
# parameters and pattern variables, so `go` is one def that runs each step
# and hands the step's computed result to the next one as a field.
type Step is Type:
  Seg{walk: Walk, seg: Pts}
  Cut{walk: Walk, pv: Pivot, seg: Pts}
  Parts{pi: U32, px: F32, py: F32, sides: Sides}

# Each step spends one unit of fuel, and an interval of one point takes its
# three steps too, so 3 per point is enough. argmax only reads `next`, so
# the points stay unshared.
def go(fuel: Nat, +g: Graph, +dir: Direction, +k: Weight, +lo: F32, +hi: F32, step: Step) -> Edges:
  match fuel step:
    case 1n++p Seg{+walk, PCon{+i, +x, +y, +next}}:
      go(p, g, dir, k, lo, hi, Cut{walk, argmax(walk, next, i, x, y, 0, 1), PCon{i, x, y, next}})
    case 1n++p Cut{walk, pv, seg}:
      Pivot{+pi, +px, +py, pk} = pv
      go(p, g, dir, k, lo, hi, Parts{pi, px, py, sides(walk, take_rev(U32.to_nat(pk), seg, PNil{}))})
    case 1n++p Parts{+pi, +px, +py, Sides{+left, +right}}:
      here = right_sweep(g, k, lo, hi, pi, px, py, right, left_sweep(g, dir, k, lo, hi, pi, px, py, left, ENil{}))
      a b = go(p, g, dir, k, lo, hi, Seg{Leftward{}, left}) go(p, g, dir, k, lo, hi, Seg{Rightward{}, right})
      EJoin{here, EJoin{a, b}}
    case _ _:
      ENil{}

# The graph of `n` points. `lo` and `hi` bound the weights, as ts2vg's
# min_weight and max_weight; pass neg_inf() and inf() for no bound.
def build(+g: Graph, +dir: Direction, +k: Weight, +lo: F32, +hi: F32, pts: Pts, n: U32) -> Edges:
  go(Nat.mul(3n, U32.to_nat(n)), g, dir, k, lo, hi, Seg{Rightward{}, pts})
