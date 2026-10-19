# What ts2vg's command line prints: the edge list, the degree sequence, the
# degree counts and the degree distribution.
import Base
import ./graph.bend as G

# Edges, one per line: `src dst`, then the weight when the graph is weighted.

def weight_text(weighted: Bool, w: F32) -> String:
  match weighted:
    case True{}:
      " " ++ F32.show(w)
    case False{}:
      ""

def edge_line(+weighted: Bool, s: U32, t: U32, w: F32) -> String:
  U32.show(s) ++ " " ++ U32.show(t) ++ weight_text(weighted, w) ++ "\n"

def edges_text(+weighted: Bool, es: G.Edges, acc: String) -> String:
  match es:
    case G.ENil{}:
      acc
    case G.ECon{s, t, w, next}:
      edges_text(weighted, next, edge_line(weighted, s, t, w) ++ acc)
    case G.EJoin{a, b}:
      edges_text(weighted, b, edges_text(weighted, a, acc))

def is_weighted(k: G.Weight) -> Bool:
  match k:
    case G.Unweighted{}:
      False{}
    case _:
      True{}

# Degrees: each edge adds one to the degree of both of its ends, as ts2vg's
# degrees_in + degrees_out.

# An array with room for `n` slots, indexed from 0.
def slots(+n: U32) -> Array<U32>:
  Array.new(U32, Nat.add(1n, U32.log2(n)), 0)

def bump.set(+i: U32, r: Array<U32> & U32) -> Array<U32>:
  (d, v) = r
  Array.set(U32, d, i, (v + 1 : U32))

def bump(d: Array<U32>, +i: U32) -> Array<U32>:
  bump.set(i, Array.get(U32, d, i))

def added(r: Array<U32> & U32) -> Array<U32>:
  (d, old) = r
  d

def atomic_bump(d: Array<U32>, +i: U32) -> Array<U32>:
  added(Array.atomic.add(d, i, 1))

def tally_degrees(es: G.Edges, d: Array<U32>) -> Array<U32>:
  match es:
    case G.ENil{}:
      d
    case G.ECon{s, t, w, next}:
      tally_degrees(next, atomic_bump(atomic_bump(d, s), t))
    case G.EJoin{a, b}:
      tally_degrees(b, tally_degrees(a, d))

# Forks down the build's tree of EJoin into tally_degrees, which forks
# nothing, so the runtime spreads the tallies over every thread.
def degrees_tree(depth: Nat, es: G.Edges, dd: Array<U32> & Array<U32>) -> Array<U32>:
  match depth es:
    case 1n++p G.EJoin{a, b}:
      (d1, d2) = dd
      x y = degrees_tree(p, a, Array.fork(U32, d1)) degrees_tree(p, b, Array.fork(U32, d2))
      Array.join(U32, x, y)
    case 0n G.EJoin{a, b}:
      (d1, d2) = dd
      x y = tally_degrees(a, d1) tally_degrees(b, d2)
      Array.join(U32, x, y)
    case _ _:
      (d1, d2) = dd
      tally_degrees(es, Array.join(U32, d1, d2))

def degrees(es: G.Edges, d: Array<U32>) -> Array<U32>:
  degrees_tree(G.depth(), es, Array.fork(U32, d))

# The degree sequence, one per line. `r` is the degree array with the
# degree of node `i`; the `f` nodes below `i` are still to print.
def sequence_text(f: Nat, r: Array<U32> & U32, +i: U32, acc: String) -> String:
  match f:
    case 0n:
      (d, v) = r
      U32.show(v) ++ "\n" ++ acc
    case 1n+q:
      (d, v) = r
      sequence_text(q, Array.get(U32, d, (i - 1 : U32)), (i - 1 : U32), U32.show(v) ++ "\n" ++ acc)

def degree_sequence.from(empty: Bool, +n: U32, d: Array<U32>) -> String:
  match empty:
    case True{}:
      ""
    case False{}:
      sequence_text(U32.to_nat((n - 1 : U32)), Array.get(U32, d, (n - 1 : U32)), (n - 1 : U32), "")

def degree_sequence.go(+n: U32, d: Array<U32>) -> String:
  degree_sequence.from(U32.is_zero(n), n, d)

def degree_sequence(es: G.Edges, +n: U32) -> String:
  degree_sequence.go(n, degrees(es, slots(n)))

# How many nodes have each degree: `r` is the degree array with the degree
# of node `i`; the `f` nodes above `i` are still to count.
def count_loop(f: Nat, r: Array<U32> & U32, +i: U32, c: Array<U32>) -> Array<U32>:
  match f:
    case 0n:
      (d, v) = r
      bump(c, v)
    case 1n+q:
      (d, v) = r
      count_loop(q, Array.get(U32, d, (i + 1 : U32)), (i + 1 : U32), bump(c, v))

# Degree counts or the degree distribution: `k count` or `k count/n` for
# each degree k some node has, from the smallest k.
def count_value(share: Bool, +v: U32, +n: U32) -> String:
  match share:
    case True{}:
      F32.show(F32.div(U32.to_f32(v), U32.to_f32(n)))
    case False{}:
      U32.show(v)

def count_line(zero: Bool, +share: Bool, +k: U32, +v: U32, +n: U32, acc: String) -> String:
  match zero:
    case True{}:
      acc
    case False{}:
      U32.show(k) ++ " " ++ count_value(share, v, n) ++ "\n" ++ acc

def counts_text(f: Nat, +share: Bool, +n: U32, r: Array<U32> & U32, +k: U32, acc: String) -> String:
  match f:
    case 0n:
      (c, +v) = r
      count_line(U32.is_zero(v), share, k, v, n, acc)
    case 1n+q:
      (c, +v) = r
      counts_text(q, share, n, Array.get(U32, c, (k - 1 : U32)), (k - 1 : U32), count_line(U32.is_zero(v), share, k, v, n, acc))

def degree_counts.text(+share: Bool, +n: U32, c: Array<U32>) -> String:
  counts_text(U32.to_nat((n - 1 : U32)), share, n, Array.get(U32, c, (n - 1 : U32)), (n - 1 : U32), "")

def degree_counts.from(empty: Bool, +share: Bool, +n: U32, d: Array<U32>) -> String:
  match empty:
    case True{}:
      ""
    case False{}:
      degree_counts.text(share, n, count_loop(U32.to_nat((n - 1 : U32)), Array.get(U32, d, 0), 0, slots(n)))

def degree_counts(+share: Bool, es: G.Edges, +n: U32) -> String:
  degree_counts.from(U32.is_zero(n), share, n, degrees(es, slots(n)))
