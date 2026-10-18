# The rules bend-vg keeps. F32 arithmetic is opaque to the checker, so the
# laws state what holds for every F32 word: how the divide and conquer cuts
# an interval around its pivot.
import Base
import ./src/graph.bend as G

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

def kept(r: G.Edges & G.Pts) -> G.Pts:
  (es, pts) = r
  pts

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

# LAW: a natural left sweep hands back the points it walked, in their order,
# whatever edges it adds
law natural_left_keeps:
  for +dir  : G.Direction
  for +k    : G.Weight
  for +lo   : F32
  for +hi   : F32
  for +ia   : U32
  for +xa   : F32
  for +ya   : F32
  for +rev  : G.Pts
  for +best : F32
  for +es   : G.Edges
  for +fwd  : G.Pts
  {kept(G.natural_left(dir, k, lo, hi, ia, xa, ya, rev, best, es, fwd)) == rev_onto(rev, fwd) : G.Pts}

# LAW: so does a horizontal left sweep
law horizontal_left_keeps:
  for +dir  : G.Direction
  for +k    : G.Weight
  for +lo   : F32
  for +hi   : F32
  for +ia   : U32
  for +xa   : F32
  for +ya   : F32
  for +rev  : G.Pts
  for +best : F32
  for +es   : G.Edges
  for +fwd  : G.Pts
  {kept(G.horizontal_left(dir, k, lo, hi, ia, xa, ya, rev, best, es, fwd)) == rev_onto(rev, fwd) : G.Pts}
