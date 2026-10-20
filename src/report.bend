# What ts2vg's command line prints: the edge list, the degree sequence, the
# degree counts and the degree distribution.
import Base
import ../visgraph.bend as VG

# Edges, one per line: `src dst`, then the weight when the graph is weighted.

def weight_text(weighted: Bool, w: F32) -> String:
  match weighted:
    case True{}:
      " " ++ F32.show(w)
    case False{}:
      ""

def edge_line(+weighted: Bool, s: U32, t: U32, w: F32) -> String:
  U32.show(s) ++ " " ++ U32.show(t) ++ weight_text(weighted, w) ++ "\n"

def edges_text(+weighted: Bool, es: VG.Edges, acc: String) -> String:
  match es:
    case VG.ENil{}:
      acc
    case VG.ECon{s, t, w, next}:
      edges_text(weighted, next, edge_line(weighted, s, t, w) ++ acc)
    case VG.EJoin{a, b}:
      edges_text(weighted, b, edges_text(weighted, a, acc))

def is_weighted(k: VG.Weight) -> Bool:
  match k:
    case VG.Unweighted{}:
      False{}
    case _:
      True{}

def bump.set(+i: U32, r: Array<U32> & U32) -> Array<U32>:
  (d, v) = r
  Array.set(U32, d, i, (v + 1 : U32))

def bump(d: Array<U32>, +i: U32) -> Array<U32>:
  bump.set(i, Array.get(U32, d, i))

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

# The degree sequence of the `n` nodes whose degrees `d` holds.
def degree_sequence(+n: U32, d: Array<U32>) -> String:
  degree_sequence.from(U32.is_zero(n), n, d)

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
      degree_counts.text(share, n, count_loop(U32.to_nat((n - 1 : U32)), Array.get(U32, d, 0), 0, VG.slots(n)))

def degree_counts(+share: Bool, +n: U32, d: Array<U32>) -> String:
  degree_counts.from(U32.is_zero(n), share, n, d)

# The edge list of `g`.
def edge_list(+weighted: Bool, g: VG.Graph) -> String:
  VG.Graph{n, dir, es} = g
  edges_text(weighted, es, "")
