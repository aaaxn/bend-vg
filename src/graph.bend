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
  Cols{ys: Array<F32>, lefts: Array<U32>, rights: Array<U32>}

def fork3(a: Array<F32> & Array<F32>, b: Array<U32> & Array<U32>, c: Array<U32> & Array<U32>) -> Cols & Cols:
  (a1, a2) = a
  (b1, b2) = b
  (c1, c2) = c
  (Cols{a1, b1, c1}, Cols{a2, b2, c2})

def fork_cols(c: Cols) -> Cols & Cols:
  Cols{ys, lefts, rights} = c
  fork3(Array.fork(F32, ys), Array.fork(U32, lefts), Array.fork(U32, rights))

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

type Block is Data:
  Block{start: U32, opening_nans: U32, unbounded: Unbounded, st: Stack, visits: F32}

type Blocks is Data:
  BOne{b: Block}
  BJoin{a: Blocks, b: Blocks}

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

def block_of(l: Local) -> Blocks:
  Local{b, c} = l
  BOne{b}

# It forks nothing, so the runtime runs it once the tree has grown, on any
# idle thread; work done before a fork runs while the tree grows, on a few
# threads.
def block_leaf(+s: U32, +e: U32, c: Cols) -> Blocks:
  Cols{ys, lefts, rights} = c
  block_of(block_pass(U32.to_nat((e - s : U32)), s, Array.get(F32, ys, s), lefts, rights))

def block_tree(depth: Nat, +s: U32, +e: U32, cc: Cols & Cols) -> Blocks:
  match depth:
    case 1n++d:
      (c1, c2) = cc
      +mid = (s + U32.shr((e - s : U32)) : U32)
      x y = block_tree(d, s, mid, fork_cols(c1)) block_tree(d, mid, e, fork_cols(c2))
      BJoin{x, y}
    case 0n:
      (c1, c2) = cc
      +mid = (s + U32.shr((e - s : U32)) : U32)
      x y = block_leaf(s, mid, c1) block_leaf(mid, e, c2)
      BJoin{x, y}

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

def merge_block(b: Block, m: Merged) -> Merged:
  Block{+start, +opening_nans, unbounded, st, +visits} = b
  Merged{g, lefts, rights, +v} = m
  push_block_stack(st, bound_unbounded(in_order(unbounded, UNil{}), Merged{push_opening_nans(U32.to_nat(opening_nans), start, g), lefts, rights, F32.add(v, visits)}))

# The merge replays the stack over every point before each block. The points
# the block's own stack could not bound pop it in order; the others sit on
# the block's stack, which goes on top.
def merge(bs: Blocks, m: Merged) -> Merged:
  match bs:
    case BOne{b}:
      merge_block(b, m)
    case BJoin{a, b}:
      merge(b, merge(a, m))

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

def fork_depth() -> Nat:
  8n

# At most 512 blocks, and at least 32 points in each unless n is below 64.
def block_depth(+n: U32) -> Nat:
  Nat.min(fork_depth(), U32.log2(U32.shrn(n, 6n)))

# About two chunks for each of the tree's leaves.
def target(+visits: F32) -> U32:
  U32.max(1, F32.to_u32(F32.div(visits, U32.to_f32(U32.shln(4, fork_depth())))))

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

# Bend matches only parameters, so a read's result must arrive as one: a
# sweep reads y at `ahead`, where the next sweep starts, and hands it over.
type Walked is Type:
  Walked{yr: Array<F32> & F32, es: Edges}

def natural_right(count: Nat, +j: U32, yr: Array<F32> & F32, +k: Weight, +lo: F32, +hi: F32, +ia: U32, +xa: F32, +ya: F32, +scale_a: F32, +best: F32, es: Edges, +ahead: U32) -> Walked:
  match count:
    case 0n:
      (ys, yb) = yr
      Walked{Array.get(F32, ys, ahead), es}
    case 1n+c:
      (ys, +yb) = yr
      +xb = U32.to_f32(j)
      +s = F32.div(F32.sub(yb, ya), F32.sub(xb, xa))
      +seen = clears(F32.is_gt(s, best), s, best, scale_a, xb, yb)
      +j2 = (j + 1 : U32)
      natural_right(c, j2, Array.get(F32, ys, j2), k, lo, hi, ia, xa, ya, scale_a, pick(seen, s, best), add_right(seen, k, lo, hi, ia, j, xa, xb, ya, yb, s, es), ahead)

def natural_left(count: Nat, +j: U32, yr: Array<F32> & F32, +dir: Direction, +k: Weight, +lo: F32, +hi: F32, +ia: U32, +xa: F32, +ya: F32, +scale_a: F32, +best: F32, es: Edges, +ahead: U32) -> Walked:
  match count:
    case 0n:
      (ys, yb) = yr
      Walked{Array.get(F32, ys, ahead), es}
    case 1n+c:
      (ys, +yb) = yr
      +xb = U32.to_f32(j)
      +s = F32.div(F32.sub(yb, ya), F32.neg(F32.sub(xb, xa)))
      +seen = clears(F32.is_gt(s, best), s, best, scale_a, xb, yb)
      +j2 = (j - 1 : U32)
      natural_left(c, j2, Array.get(F32, ys, j2), dir, k, lo, hi, ia, xa, ya, scale_a, pick(seen, s, best), add_left(seen, dir, k, lo, hi, ia, j, xa, xb, ya, yb, F32.neg(s), es), ahead)

def horizontal_right(count: Nat, +j: U32, yr: Array<F32> & F32, +k: Weight, +lo: F32, +hi: F32, +ia: U32, +xa: F32, +ya: F32, +best: F32, es: Edges, +ahead: U32) -> Walked:
  match count:
    case 0n:
      (ys, yb) = yr
      Walked{Array.get(F32, ys, ahead), es}
    case 1n+c:
      (ys, +yb) = yr
      +seen = F32.is_gt(yb, best)
      +j2 = (j + 1 : U32)
      horizontal_right(c, j2, Array.get(F32, ys, j2), k, lo, hi, ia, xa, ya, pick(seen, yb, best), add_right(seen, k, lo, hi, ia, j, xa, U32.to_f32(j), ya, yb, nan(), es), ahead)

def horizontal_left(count: Nat, +j: U32, yr: Array<F32> & F32, +dir: Direction, +k: Weight, +lo: F32, +hi: F32, +ia: U32, +xa: F32, +ya: F32, +best: F32, es: Edges, +ahead: U32) -> Walked:
  match count:
    case 0n:
      (ys, yb) = yr
      Walked{Array.get(F32, ys, ahead), es}
    case 1n+c:
      (ys, +yb) = yr
      +seen = F32.is_gt(yb, best)
      +j2 = (j - 1 : U32)
      horizontal_left(c, j2, Array.get(F32, ys, j2), dir, k, lo, hi, ia, xa, ya, pick(seen, yb, best), add_left(seen, dir, k, lo, hi, ia, j, xa, U32.to_f32(j), ya, yb, nan(), es), ahead)

def right_sweep(g: Graph, count: Nat, yr: Array<F32> & F32, +k: Weight, +lo: F32, +hi: F32, +ia: U32, +xa: F32, +ya: F32, es: Edges) -> Walked:
  match g:
    case Natural{}:
      natural_right(count, (ia + 1 : U32), yr, k, lo, hi, ia, xa, ya, scale(xa, ya), neg_inf(), es, (ia - 1 : U32))
    case Horizontal{}:
      horizontal_right(count, (ia + 1 : U32), yr, k, lo, hi, ia, xa, ya, neg_inf(), es, (ia - 1 : U32))

def left_sweep(g: Graph, count: Nat, +dir: Direction, +k: Weight, +lo: F32, +hi: F32, +ia: U32, +xa: F32, +ya: F32, w: Walked) -> Walked:
  match g:
    case Natural{}:
      Walked{yr, es} = w
      natural_left(count, (ia - 1 : U32), yr, dir, k, lo, hi, ia, xa, ya, scale(xa, ya), neg_inf(), es, (ia + 1 : U32))
    case Horizontal{}:
      Walked{yr, es} = w
      horizontal_left(count, (ia - 1 : U32), yr, dir, k, lo, hi, ia, xa, ya, neg_inf(), es, (ia + 1 : U32))

type Out is Type:
  Out{cols: Cols, es: Edges}

def points(count: Nat, +i: U32, lr: Array<U32> & U32, rr: Array<U32> & U32, w: Walked, +g: Graph, +dir: Direction, +k: Weight, +lo: F32, +hi: F32) -> Out:
  match count:
    case 0n:
      (lefts, l) = lr
      (rights, r) = rr
      Walked{yr, es} = w
      (ys, y) = yr
      Out{Cols{ys, lefts, rights}, es}
    case 1n+c:
      (lefts, +l) = lr
      (rights, +r) = rr
      Walked{yr, es} = w
      (ys, +y) = yr
      +x = U32.to_f32(i)
      +i2 = (i + 1 : U32)
      points(c, i2, Array.get(U32, lefts, i2), Array.get(U32, rights, i2), left_sweep(g, U32.to_nat(l), dir, k, lo, hi, i, x, y, right_sweep(g, U32.to_nat(r), Array.get(F32, ys, i2), k, lo, hi, i, x, y, es)), g, dir, k, lo, hi)

def chunks(cs: Chunks, o: Out, +g: Graph, +dir: Direction, +k: Weight, +lo: F32, +hi: F32) -> Out:
  match cs:
    case CCon{+start, count, next}:
      Out{cols, es} = o
      Cols{ys, lefts, rights} = cols
      chunks(next, points(U32.to_nat(count), start, Array.get(U32, lefts, start), Array.get(U32, rights, start), Walked{Array.get(F32, ys, start), es}, g, dir, k, lo, hi), g, dir, k, lo, hi)
    case CNil{}:
      o

def edges_of(o: Out) -> Edges:
  Out{cols, es} = o
  es

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

def split(+g: Graph, +dir: Direction, +k: Weight, +lo: F32, +hi: F32, ys: Array<F32>, c: Cut) -> Edges:
  Cut{lefts, rights, cs, +m} = c
  tree(fork_depth(), halves(cs, m), fork_cols(Cols{ys, lefts, rights}), g, dir, k, lo, hi)

def cut_all(+g: Graph, +dir: Direction, +k: Weight, +lo: F32, +hi: F32, +n: U32, ys: Array<F32>, lefts: Array<U32>, r: Array<U32> & F32) -> Edges:
  (rights, +visits) = r
  split(g, dir, k, lo, hi, ys, cut(U32.to_nat(n), 0, Array.get(U32, lefts, 0), Array.get(U32, rights, 0), 0, 0, target(visits), CNil{}, 0))

def merged(+g: Graph, +dir: Direction, +k: Weight, +lo: F32, +hi: F32, +n: U32, ys: Array<F32>, m: Merged) -> Edges:
  Merged{st, lefts, rights, +visits} = m
  cut_all(g, dir, k, lo, hi, n, ys, lefts, flush(st, n, rights, visits))

def passed(+g: Graph, +dir: Direction, +k: Weight, +lo: F32, +hi: F32, +n: U32, cc: Cols & Cols) -> Edges:
  (c1, c2) = cc
  Cols{ys, lefts, rights} = c2
  merged(g, dir, k, lo, hi, n, ys, merge(block_tree(block_depth(n), 0, n, fork_cols(c1)), Merged{KNil{}, lefts, rights, 0.0}))

# The graph of the `n` values `ys`, each at its index. `lo` and `hi` bound
# the weights, as ts2vg's min_weight and max_weight; pass neg_inf() and
# inf() for no bound.
def build(+g: Graph, +dir: Direction, +k: Weight, +lo: F32, +hi: F32, ys: Array<F32>, +n: U32) -> Edges:
  passed(g, dir, k, lo, hi, n, fork_cols(Cols{ys, Array.new(U32, Nat.add(1n, U32.log2(n)), 0), Array.new(U32, Nat.add(1n, U32.log2(n)), 0)}))
