# ts2vg's visibility graphs of time series, in Bend2, on every CPU thread.
#
#   import bend-visgraph@2.0.0.0/visgraph.bend as VG
#   import bend-visgraph@2.0.0.0/parallel.bend as Par
#
# Par.build and Par.degrees are VG.build and VG.degrees on every thread.
# Each def here that hands one array to two tasks relies on Base's @unsafe
# Array.fork: the tasks that share an array read it, write cells no other
# task writes, or add to cells atomically.
import Base
import ./visgraph.bend as VG

def fork3(a: Array<F32> & Array<F32>, b: Array<U32> & Array<U32>, c: Array<U32> & Array<U32>) -> VG.Cols & VG.Cols:
  (a1, a2) = a
  (b1, b2) = b
  (c1, c2) = c
  (VG.Cols{a1, b1, c1}, VG.Cols{a2, b2, c2})

def fork_cols(c: VG.Cols) -> VG.Cols & VG.Cols:
  VG.Cols{ys, lefts, rights} = c
  fork3(Array.fork(F32, ys), Array.fork(U32, lefts), Array.fork(U32, rights))

# The stack runs on blocks in parallel; a merge then walks the blocks in
# order.
type Blocks is Data:
  BOne{b: VG.Block}
  BJoin{a: Blocks, b: Blocks}

def block_of(l: VG.Local) -> Blocks:
  VG.Local{b, c} = l
  BOne{b}

# It forks nothing, so the runtime runs it once the tree has grown, on any
# idle thread; work done before a fork runs while the tree grows, on a few
# threads.
def block_leaf(+s: U32, +e: U32, c: VG.Cols) -> Blocks:
  VG.Cols{ys, lefts, rights} = c
  block_of(VG.block_pass(U32.to_nat((e - s : U32)), s, Array.get(F32, ys, s), lefts, rights))

def block_tree(depth: Nat, +s: U32, +e: U32, cc: VG.Cols & VG.Cols) -> Blocks:
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

def merge(bs: Blocks, m: VG.Merged) -> VG.Merged:
  match bs:
    case BOne{b}:
      VG.merge_block(b, m)
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
      Cut{lefts, rights, close(last, start, i, cs), VG.pick_u32(last, (m + 1 : U32), m)}
    case 1n+c:
      (lefts, +l) = lr
      (rights, +r) = rr
      +w = (acc + l + r + 1 : U32)
      +full = U32.is_ge(w, target)
      +i2 = (i + 1 : U32)
      cut(c, i2, Array.get(U32, lefts, i2), Array.get(U32, rights, i2), VG.pick_u32(full, i2, start), VG.pick_u32(full, 0, w), target, close(full, start, i2, cs), VG.pick_u32(full, (m + 1 : U32), m))

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

def chunks(cs: Chunks, o: VG.Out, +index: Bool, +g: VG.Visibility, +dir: VG.Direction, +k: VG.Weight, +lo: F32, +hi: F32) -> VG.Out:
  match cs:
    case CCon{+start, count, next}:
      VG.Out{cols, xs, es} = o
      VG.Cols{ys, lefts, rights} = cols
      chunks(next, VG.points(U32.to_nat(count), start, Array.get(U32, lefts, start), Array.get(U32, rights, start), VG.Walked{Array.get(F32, ys, start), Array.get(F32, xs, start), es}, index, g, dir, k, lo, hi), index, g, dir, k, lo, hi)
    case CNil{}:
      o

def leaf(cs: Chunks, c: VG.Cols, xs: Array<F32>, +index: Bool, +g: VG.Visibility, +dir: VG.Direction, +k: VG.Weight, +lo: F32, +hi: F32) -> VG.Edges:
  VG.edges_of(chunks(cs, VG.Out{c, xs, VG.ENil{}}, index, g, dir, k, lo, hi))

def tree(depth: Nat, h: Halves, cc: VG.Cols & VG.Cols, xx: Array<F32> & Array<F32>, +index: Bool, +g: VG.Visibility, +dir: VG.Direction, +k: VG.Weight, +lo: F32, +hi: F32) -> VG.Edges:
  match depth h:
    case 1n++d Halves{a, +na, b, +nb}:
      (c1, c2) = cc
      (x1, x2) = xx
      x y = tree(d, halves(a, na), fork_cols(c1), Array.fork(F32, x1), index, g, dir, k, lo, hi) tree(d, halves(b, nb), fork_cols(c2), Array.fork(F32, x2), index, g, dir, k, lo, hi)
      VG.EJoin{x, y}
    case _ Halves{a, na, b, nb}:
      (c1, c2) = cc
      (x1, x2) = xx
      x y = leaf(a, c1, x1, index, g, dir, k, lo, hi) leaf(b, c2, x2, index, g, dir, k, lo, hi)
      VG.EJoin{x, y}

def split(+index: Bool, +g: VG.Visibility, +dir: VG.Direction, +k: VG.Weight, +lo: F32, +hi: F32, ys: Array<F32>, xs: Array<F32>, c: Cut) -> VG.Edges:
  Cut{lefts, rights, cs, +m} = c
  tree(fork_depth(), halves(cs, m), fork_cols(VG.Cols{ys, lefts, rights}), Array.fork(F32, xs), index, g, dir, k, lo, hi)

def cut_all(+index: Bool, +g: VG.Visibility, +dir: VG.Direction, +k: VG.Weight, +lo: F32, +hi: F32, +n: U32, ys: Array<F32>, xs: Array<F32>, lefts: Array<U32>, r: Array<U32> & F32) -> VG.Edges:
  (rights, +visits) = r
  split(index, g, dir, k, lo, hi, ys, xs, cut(U32.to_nat(n), 0, Array.get(U32, lefts, 0), Array.get(U32, rights, 0), 0, 0, target(visits), CNil{}, 0))

def merged(+index: Bool, +g: VG.Visibility, +dir: VG.Direction, +k: VG.Weight, +lo: F32, +hi: F32, +n: U32, ys: Array<F32>, xs: Array<F32>, m: VG.Merged) -> VG.Edges:
  VG.Merged{st, lefts, rights, +visits} = m
  cut_all(index, g, dir, k, lo, hi, n, ys, xs, lefts, VG.flush(st, n, rights, visits))

def passed(+index: Bool, +g: VG.Visibility, +dir: VG.Direction, +k: VG.Weight, +lo: F32, +hi: F32, +n: U32, xs: Array<F32>, cc: VG.Cols & VG.Cols) -> VG.Edges:
  (c1, c2) = cc
  VG.Cols{ys, lefts, rights} = c2
  merged(index, g, dir, k, lo, hi, n, ys, xs, merge(block_tree(block_depth(n), 0, n, fork_cols(c1)), VG.Merged{VG.KNil{}, lefts, rights, 0.0}))

def built(+index: Bool, +g: VG.Visibility, +dir: VG.Direction, +k: VG.Weight, +lo: F32, +hi: F32, ys: Array<F32>, xs: Array<F32>, +n: U32) -> VG.Edges:
  passed(index, g, dir, k, lo, hi, n, xs, fork_cols(VG.Cols{ys, VG.slots(n), VG.slots(n)}))

# VG.build on every thread: the stack runs on blocks, then the sweeps on
# chunks of equal work.
def visibility(+g: VG.Visibility, +dir: VG.Direction, +k: VG.Weight, +lo: F32, +hi: F32, ys: Array<F32>, xs: VG.Xs, +n: U32) -> VG.Edges:
  match xs:
    case VG.Index{}:
      built(True{}, g, dir, k, lo, hi, ys, VG.no_xs(), n)
    case VG.At{a}:
      built(False{}, g, dir, k, lo, hi, ys, a, n)

def chosen(is_visibility: Bool, +g: VG.Visibility, +dir: VG.Direction, +k: VG.Weight, +lo: F32, +hi: F32, +limit: U32, ys: Array<F32>, xs: VG.Xs, +n: U32) -> VG.Edges:
  match is_visibility:
    case True{}:
      visibility(g, dir, k, lo, hi, ys, xs, n)
    case False{}:
      VG.penetrable(g, dir, k, lo, hi, limit, ys, xs, n)

# VG.build on every thread.
def build(o: VG.Options, s: VG.Series) -> VG.Graph:
  VG.Options{g, +dir, k, lo, hi, +limit} = o
  VG.Series{+n, ys, xs} = s
  VG.Graph{n, dir, chosen(U32.is_zero(limit), g, dir, k, lo, hi, limit, ys, xs, n)}

# Forks down the build's tree of EJoin into VG.degrees.into, which
# forks nothing, so the runtime spreads the tallies over every thread.
def degrees_tree(depth: Nat, es: VG.Edges, dd: Array<U32> & Array<U32>) -> Array<U32>:
  match depth es:
    case 1n++p VG.EJoin{a, b}:
      (d1, d2) = dd
      x y = degrees_tree(p, a, Array.fork(U32, d1)) degrees_tree(p, b, Array.fork(U32, d2))
      Array.join(U32, x, y)
    case 0n VG.EJoin{a, b}:
      (d1, d2) = dd
      x y = VG.degrees.into(a, d1) VG.degrees.into(b, d2)
      Array.join(U32, x, y)
    case _ _:
      (d1, d2) = dd
      VG.degrees.into(es, Array.join(U32, d1, d2))

# VG.degrees on every thread.
def degrees(g: VG.Graph) -> Array<U32>:
  VG.Graph{+n, dir, es} = g
  degrees_tree(fork_depth(), es, Array.fork(U32, VG.slots(n)))
