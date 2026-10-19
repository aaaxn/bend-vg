# The build and the degree count on every thread. Each def here that hands
# one array to two tasks relies on Base's @unsafe Array.fork: the tasks that
# share an array read it, write cells no other task writes, or add to cells
# atomically.
import Base
import ./graph.bend as G
import ./report.bend as Report

def fork3(a: Array<F32> & Array<F32>, b: Array<U32> & Array<U32>, c: Array<U32> & Array<U32>) -> G.Cols & G.Cols:
  (a1, a2) = a
  (b1, b2) = b
  (c1, c2) = c
  (G.Cols{a1, b1, c1}, G.Cols{a2, b2, c2})

def fork_cols(c: G.Cols) -> G.Cols & G.Cols:
  G.Cols{ys, lefts, rights} = c
  fork3(Array.fork(F32, ys), Array.fork(U32, lefts), Array.fork(U32, rights))

# The stack runs on blocks in parallel; a merge then walks the blocks in
# order.
type Blocks is Data:
  BOne{b: G.Block}
  BJoin{a: Blocks, b: Blocks}

def block_of(l: G.Local) -> Blocks:
  G.Local{b, c} = l
  BOne{b}

# It forks nothing, so the runtime runs it once the tree has grown, on any
# idle thread; work done before a fork runs while the tree grows, on a few
# threads.
def block_leaf(+s: U32, +e: U32, c: G.Cols) -> Blocks:
  G.Cols{ys, lefts, rights} = c
  block_of(G.block_pass(U32.to_nat((e - s : U32)), s, Array.get(F32, ys, s), lefts, rights))

def block_tree(depth: Nat, +s: U32, +e: U32, cc: G.Cols & G.Cols) -> Blocks:
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

def merge(bs: Blocks, m: G.Merged) -> G.Merged:
  match bs:
    case BOne{b}:
      G.merge_block(b, m)
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
      Cut{lefts, rights, close(last, start, i, cs), G.pick_u32(last, (m + 1 : U32), m)}
    case 1n+c:
      (lefts, +l) = lr
      (rights, +r) = rr
      +w = (acc + l + r + 1 : U32)
      +full = U32.is_ge(w, target)
      +i2 = (i + 1 : U32)
      cut(c, i2, Array.get(U32, lefts, i2), Array.get(U32, rights, i2), G.pick_u32(full, i2, start), G.pick_u32(full, 0, w), target, close(full, start, i2, cs), G.pick_u32(full, (m + 1 : U32), m))

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

def chunks(cs: Chunks, o: G.Out, +index: Bool, +g: G.Graph, +dir: G.Direction, +k: G.Weight, +lo: F32, +hi: F32) -> G.Out:
  match cs:
    case CCon{+start, count, next}:
      G.Out{cols, xs, es} = o
      G.Cols{ys, lefts, rights} = cols
      chunks(next, G.points(U32.to_nat(count), start, Array.get(U32, lefts, start), Array.get(U32, rights, start), G.Walked{Array.get(F32, ys, start), Array.get(F32, xs, start), es}, index, g, dir, k, lo, hi), index, g, dir, k, lo, hi)
    case CNil{}:
      o

def leaf(cs: Chunks, c: G.Cols, xs: Array<F32>, +index: Bool, +g: G.Graph, +dir: G.Direction, +k: G.Weight, +lo: F32, +hi: F32) -> G.Edges:
  G.edges_of(chunks(cs, G.Out{c, xs, G.ENil{}}, index, g, dir, k, lo, hi))

def tree(depth: Nat, h: Halves, cc: G.Cols & G.Cols, xx: Array<F32> & Array<F32>, +index: Bool, +g: G.Graph, +dir: G.Direction, +k: G.Weight, +lo: F32, +hi: F32) -> G.Edges:
  match depth h:
    case 1n++d Halves{a, +na, b, +nb}:
      (c1, c2) = cc
      (x1, x2) = xx
      x y = tree(d, halves(a, na), fork_cols(c1), Array.fork(F32, x1), index, g, dir, k, lo, hi) tree(d, halves(b, nb), fork_cols(c2), Array.fork(F32, x2), index, g, dir, k, lo, hi)
      G.EJoin{x, y}
    case _ Halves{a, na, b, nb}:
      (c1, c2) = cc
      (x1, x2) = xx
      x y = leaf(a, c1, x1, index, g, dir, k, lo, hi) leaf(b, c2, x2, index, g, dir, k, lo, hi)
      G.EJoin{x, y}

def split(+index: Bool, +g: G.Graph, +dir: G.Direction, +k: G.Weight, +lo: F32, +hi: F32, ys: Array<F32>, xs: Array<F32>, c: Cut) -> G.Edges:
  Cut{lefts, rights, cs, +m} = c
  tree(fork_depth(), halves(cs, m), fork_cols(G.Cols{ys, lefts, rights}), Array.fork(F32, xs), index, g, dir, k, lo, hi)

def cut_all(+index: Bool, +g: G.Graph, +dir: G.Direction, +k: G.Weight, +lo: F32, +hi: F32, +n: U32, ys: Array<F32>, xs: Array<F32>, lefts: Array<U32>, r: Array<U32> & F32) -> G.Edges:
  (rights, +visits) = r
  split(index, g, dir, k, lo, hi, ys, xs, cut(U32.to_nat(n), 0, Array.get(U32, lefts, 0), Array.get(U32, rights, 0), 0, 0, target(visits), CNil{}, 0))

def merged(+index: Bool, +g: G.Graph, +dir: G.Direction, +k: G.Weight, +lo: F32, +hi: F32, +n: U32, ys: Array<F32>, xs: Array<F32>, m: G.Merged) -> G.Edges:
  G.Merged{st, lefts, rights, +visits} = m
  cut_all(index, g, dir, k, lo, hi, n, ys, xs, lefts, G.flush(st, n, rights, visits))

def passed(+index: Bool, +g: G.Graph, +dir: G.Direction, +k: G.Weight, +lo: F32, +hi: F32, +n: U32, xs: Array<F32>, cc: G.Cols & G.Cols) -> G.Edges:
  (c1, c2) = cc
  G.Cols{ys, lefts, rights} = c2
  merged(index, g, dir, k, lo, hi, n, ys, xs, merge(block_tree(block_depth(n), 0, n, fork_cols(c1)), G.Merged{G.KNil{}, lefts, rights, 0.0}))

def built(+index: Bool, +g: G.Graph, +dir: G.Direction, +k: G.Weight, +lo: F32, +hi: F32, ys: Array<F32>, xs: Array<F32>, +n: U32) -> G.Edges:
  passed(index, g, dir, k, lo, hi, n, xs, fork_cols(G.Cols{ys, G.counts(n), G.counts(n)}))

# G.build on every thread: the stack runs on blocks, then the sweeps on
# chunks of equal work.
def build(+g: G.Graph, +dir: G.Direction, +k: G.Weight, +lo: F32, +hi: F32, ys: Array<F32>, xs: G.Xs, +n: U32) -> G.Edges:
  match xs:
    case G.Index{}:
      built(True{}, g, dir, k, lo, hi, ys, G.no_xs(), n)
    case G.At{a}:
      built(False{}, g, dir, k, lo, hi, ys, a, n)

# Forks down the build's tree of EJoin into Report.degrees, which
# forks nothing, so the runtime spreads the tallies over every thread.
def degrees_tree(depth: Nat, es: G.Edges, dd: Array<U32> & Array<U32>) -> Array<U32>:
  match depth es:
    case 1n++p G.EJoin{a, b}:
      (d1, d2) = dd
      x y = degrees_tree(p, a, Array.fork(U32, d1)) degrees_tree(p, b, Array.fork(U32, d2))
      Array.join(U32, x, y)
    case 0n G.EJoin{a, b}:
      (d1, d2) = dd
      x y = Report.degrees(a, d1) Report.degrees(b, d2)
      Array.join(U32, x, y)
    case _ _:
      (d1, d2) = dd
      Report.degrees(es, Array.join(U32, d1, d2))

# Report.degrees on every thread.
def degrees(es: G.Edges, d: Array<U32>) -> Array<U32>:
  degrees_tree(fork_depth(), es, Array.fork(U32, d))
