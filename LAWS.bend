# The rules bend-visgraph keeps. F32 arithmetic is opaque to the checker, so
# the laws state what holds for every F32 word: how the graphs split their
# sweeps among threads.
import Base
import ./visgraph.bend as VG
import ./parallel.bend as Par

def rev_onto(a: Par.Chunks, b: Par.Chunks) -> Par.Chunks:
  match a:
    case Par.CNil{}:
      b
    case Par.CCon{start, count, next}:
      rev_onto(next, Par.CCon{start, count, b})

def rejoined(h: Par.Halves) -> Par.Chunks:
  Par.Halves{a, na, b, nb} = h
  rev_onto(a, b)

# LAW: a level of the fork tree halves its chunks without losing or
# repeating one: the first half, reversed back, then the second half, are
# the chunks it was given
law halve_keeps:
  for +k     : Nat
  for +cs    : Par.Chunks
  for +na    : U32
  for +total : U32
  for +acc   : Par.Chunks
  {rejoined(Par.halve(k, cs, na, total, acc)) == rev_onto(acc, cs) : Par.Chunks}

# A rope's edges in order, as a chain of ECon.
def cat(a: VG.Edges, b: VG.Edges) -> VG.Edges:
  match a:
    case VG.ENil{}:
      b
    case VG.ECon{s, t, w, next}:
      VG.ECon{s, t, w, cat(next, b)}
    case VG.EJoin{x, y}:
      cat(x, cat(y, b))

def normal(es: VG.Edges) -> VG.Edges:
  match es:
    case VG.ENil{}:
      VG.ENil{}
    case VG.ECon{s, t, w, next}:
      VG.ECon{s, t, w, normal(next)}
    case VG.EJoin{a, b}:
      cat(normal(a), normal(b))

# LAW: the sweeps of two consecutive ranges of start points give the edges
# of the sweeps of both ranges at once, in the same order
law sweeps_split:
  for +pts   : VG.Pts
  for +c1    : Nat
  for +c2    : Nat
  for +g     : VG.Visibility
  for +dir   : VG.Direction
  for +k     : VG.Weight
  for +lo    : F32
  for +hi    : F32
  for +limit : Nat
  {normal(VG.EJoin{VG.sweeps(pts, c1, g, dir, k, lo, hi, limit), VG.sweeps(VG.drop(c1, pts), c2, g, dir, k, lo, hi, limit)}) == normal(VG.sweeps(pts, Nat.add(c1, c2), g, dir, k, lo, hi, limit)) : VG.Edges}

# LAW: the parallel penetrable build gives the edges of one sequential pass
# over its start points, in the same order, wherever it cuts them
law split_sweeps:
  for depth  : Nat
  for +g     : VG.Visibility
  for +dir   : VG.Direction
  for +k     : VG.Weight
  for +lo    : F32
  for +hi    : F32
  for +limit : Nat
  for +pts   : VG.Pts
  for +len   : U32
  for +cu    : U32
  for +count : Nat
  {normal(VG.split(depth, g, dir, k, lo, hi, limit, pts, len, cu, count)) == normal(VG.sweeps(pts, count, g, dir, k, lo, hi, limit)) : VG.Edges}
