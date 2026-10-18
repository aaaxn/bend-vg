# The rules bend-vg keeps. F32 arithmetic is opaque to the checker, so the
# laws state what holds for every F32 word: how the divide and conquer cuts
# an interval into the two sides of its pivot, and how the penetrable graphs split their
# sweeps among threads.
import Base
import ./src/graph.bend as G
import ./src/penetrable.bend as P

def length(pts: G.Pts) -> Nat:
  match pts:
    case G.PNil{}:
      0n
    case G.PCon{i, x, y, next}:
      1n+length(next)

def append(pts: G.Pts, tail: G.Pts) -> G.Pts:
  match pts:
    case G.PNil{}:
      tail
    case G.PCon{i, x, y, next}:
      G.PCon{i, x, y, append(next, tail)}

# The points `rev` in reverse order, then `fwd`.
def rev_onto(rev: G.Pts, fwd: G.Pts) -> G.Pts:
  match rev:
    case G.PNil{}:
      fwd
    case G.PCon{i, x, y, next}:
      rev_onto(next, G.PCon{i, x, y, fwd})

# LAW: cutting an interval at the position of its pivot gives the points
# before the pivot, nearest first, and the points after it, in order
law take_rev_cuts:
  for +pre  : G.Pts
  for +i    : U32
  for +x    : F32
  for +y    : F32
  for +post : G.Pts
  for +acc  : G.Pts
  {G.take_rev(length(pre), append(pre, G.PCon{i, x, y, post}), acc) == (rev_onto(pre, acc), post) : G.Pts & G.Pts}

# The points of an interval walked in `walk`, in index order.
def in_order(walk: G.Walk, pts: G.Pts) -> G.Pts:
  match walk:
    case G.Rightward{}:
      pts
    case G.Leftward{}:
      rev_onto(pts, G.PNil{})

# The left side in index order, the pivot, then the right side.
def joined(s: G.Sides, i: U32, x: F32, y: F32) -> G.Pts:
  G.Sides{left, right} = s
  append(rev_onto(left, G.PNil{}), G.PCon{i, x, y, right})

# LAW: the two sides of an interval cut at its pivot, with the pivot between
# them, are the interval's points in index order, whichever way it is walked
law sides_keep:
  for +walk  : G.Walk
  for +pre  : G.Pts
  for +i    : U32
  for +x    : F32
  for +y    : F32
  for +post : G.Pts
  {joined(G.sides(walk, G.take_rev(length(pre), append(pre, G.PCon{i, x, y, post}), G.PNil{})), i, x, y) == in_order(walk, append(pre, G.PCon{i, x, y, post})) : G.Pts}

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
