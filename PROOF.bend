# The proofs of LAWS.bend, each by induction on a list of points.
import Base
import ./src/graph.bend as G
import ./LAWS.bend as Laws

# Each step moves the first point of `pre` onto `acc`, as rev_onto does.
def Laws.take_rev_cuts(pre, i, x, y, post, acc):
  match pre:
    case G.PNil{}:
      {==}
    case G.PCon{j, xj, yj, next}:
      Laws.take_rev_cuts(next, i, x, y, post, G.PCon{j, xj, yj, acc})

# Each step conses the point it walked onto `fwd`, as rev_onto does; the
# hypothesis holds for every best slope and edge list the step passes on.
def Laws.natural_left_keeps(dir, k, lo, hi, ia, xa, ya, rev, best, es, fwd):
  match rev:
    case G.PNil{}:
      {==}
    case G.PCon{+ib, +xb, +yb, next}:
      +s = F32.div(F32.sub(yb, ya), F32.neg(F32.sub(xb, xa)))
      +seen = G.greater(s, best, G.tol(xa, xb, ya, yb))
      Laws.natural_left_keeps(dir, k, lo, hi, ia, xa, ya, next, G.pick(seen, s, best), G.add_left(seen, dir, k, lo, hi, ia, ib, xa, xb, ya, yb, F32.neg(s), es), G.PCon{ib, xb, yb, fwd})

def Laws.horizontal_left_keeps(dir, k, lo, hi, ia, xa, ya, rev, best, es, fwd):
  match rev:
    case G.PNil{}:
      {==}
    case G.PCon{+ib, +xb, +yb, next}:
      +seen = F32.is_gt(yb, best)
      Laws.horizontal_left_keeps(dir, k, lo, hi, ia, xa, ya, next, G.pick(seen, yb, best), G.add_left(seen, dir, k, lo, hi, ia, ib, xa, xb, ya, yb, G.nan(), es), G.PCon{ib, xb, yb, fwd})
