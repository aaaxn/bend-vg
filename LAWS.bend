# The rules bend-vg keeps. F32 arithmetic is opaque to the checker, so the
# laws state what holds for every F32 word: how the graphs split their sweeps
# among threads.
import Base
import ./src/graph.bend as G
import ./src/penetrable.bend as P

def rev_onto(a: G.Chunks, b: G.Chunks) -> G.Chunks:
  match a:
    case G.CNil{}:
      b
    case G.CCon{start, count, next}:
      rev_onto(next, G.CCon{start, count, b})

def rejoined(h: G.Halves) -> G.Chunks:
  G.Halves{a, na, b, nb} = h
  rev_onto(a, b)

# LAW: a level of the fork tree halves its chunks without losing or
# repeating one: the first half, reversed back, then the second half, are
# the chunks it was given
law halve_keeps:
  for +k     : Nat
  for +cs    : G.Chunks
  for +na    : U32
  for +total : U32
  for +acc   : G.Chunks
  {rejoined(G.halve(k, cs, na, total, acc)) == rev_onto(acc, cs) : G.Chunks}

# A rope's edges in order, as a chain of ECon.
def cat(a: G.Edges, b: G.Edges) -> G.Edges:
  match a:
    case G.ENil{}:
      b
    case G.ECon{s, t, w, next}:
      G.ECon{s, t, w, cat(next, b)}
    case G.EJoin{x, y}:
      cat(x, cat(y, b))

def normal(es: G.Edges) -> G.Edges:
  match es:
    case G.ENil{}:
      G.ENil{}
    case G.ECon{s, t, w, next}:
      G.ECon{s, t, w, normal(next)}
    case G.EJoin{a, b}:
      cat(normal(a), normal(b))

# LAW: the sweeps of two consecutive ranges of start points give the edges
# of the sweeps of both ranges at once, in the same order
law sweeps_split:
  for +pts   : P.Pts
  for +c1    : Nat
  for +c2    : Nat
  for +g     : G.Graph
  for +dir   : G.Direction
  for +k     : G.Weight
  for +lo    : F32
  for +hi    : F32
  for +limit : Nat
  {normal(G.EJoin{P.sweeps(pts, c1, g, dir, k, lo, hi, limit), P.sweeps(P.drop(c1, pts), c2, g, dir, k, lo, hi, limit)}) == normal(P.sweeps(pts, Nat.add(c1, c2), g, dir, k, lo, hi, limit)) : G.Edges}

# LAW: the parallel penetrable build gives the edges of one sequential pass
# over its start points, in the same order, wherever it cuts them
law split_sweeps:
  for depth  : Nat
  for +g     : G.Graph
  for +dir   : G.Direction
  for +k     : G.Weight
  for +lo    : F32
  for +hi    : F32
  for +limit : Nat
  for +pts   : P.Pts
  for +len   : U32
  for +cu    : U32
  for +count : Nat
  {normal(P.split(depth, g, dir, k, lo, hi, limit, pts, len, cu, count)) == normal(P.sweeps(pts, count, g, dir, k, lo, hi, limit)) : G.Edges}
