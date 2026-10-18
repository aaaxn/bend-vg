# The proofs of LAWS.bend, each by induction on a list of points or on the
# depth of the split.
import Base
import ./src/graph.bend as G
import ./src/penetrable.bend as P
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

def cat_assoc(a: G.Edges, +b: G.Edges, +c: G.Edges) -> {Laws.cat(Laws.cat(a, b), c) == Laws.cat(a, Laws.cat(b, c)) : G.Edges}:
  match a:
    case G.ENil{}:
      {==}
    case G.ECon{+s, +t, +w, next}:
      %cat_assoc(next, b, c) : {G.ECon{s, t, w, Laws.cat(Laws.cat(next, b), c)} == G.ECon{s, t, w, _} : G.Edges}
      {==}
    case G.EJoin{+x, +y}:
      %cat_assoc(y, b, c) : {Laws.cat(Laws.cat(x, Laws.cat(y, b)), c) == Laws.cat(x, _) : G.Edges}
      cat_assoc(x, Laws.cat(y, b), c)

# Taking the first start out of the first range: the hypothesis covers the
# rest, and cat_assoc regroups the first start's rope.
def Laws.sweeps_split(pts, c1, c2, g, dir, k, lo, hi, limit):
  match pts c1:
    case G.PNil{} 0n:
      {==}
    case G.PNil{} 1n+c:
      {==}
    case G.PCon{i, x, y, next} 0n:
      {==}
    case G.PCon{+i, +x, +y, +next} 1n+c:
      +first = Laws.normal(P.sweep(g, dir, k, lo, hi, limit, i, x, y, next, G.ENil{}))
      +a = Laws.normal(P.sweeps(next, c, g, dir, k, lo, hi, limit))
      +b = Laws.normal(P.sweeps(P.drop(c, next), c2, g, dir, k, lo, hi, limit))
      %Laws.sweeps_split(next, c, c2, g, dir, k, lo, hi, limit) : {Laws.cat(Laws.cat(first, a), b) == Laws.cat(first, _) : G.Edges}
      cat_assoc(first, a, b)

# The first `m` of `count`, then the rest, are `count`.
def min_sub(+count: Nat, +x: Nat) -> {Nat.add(Nat.min(count, x), Nat.sub(count, Nat.min(count, x))) == count : Nat}:
  match count x:
    case 0n _:
      {==}
    case 1n+cp 0n:
      {==}
    case 1n+cp 1n+xp:
      %min_sub(cp, xp) : {1n+Nat.add(Nat.min(cp, xp), Nat.sub(cp, Nat.min(cp, xp))) == 1n+_ : Nat}
      {==}

# Each half of a split is, by the hypothesis, the sweeps of its range;
# sweeps_split joins the two ranges, and min_sub says they make `count`.
def Laws.split_sweeps(depth, g, dir, k, lo, hi, limit, pts, len, cu, count):
  match depth:
    case 0n:
      {==}
    case 1n++d:
      +c1u = P.first_half(g, len, cu)
      +c1 = Nat.min(count, U32.to_nat(c1u))
      +rest = P.drop(c1, pts)
      +low = Laws.normal(P.split(d, g, dir, k, lo, hi, limit, pts, len, c1u, c1))
      +high = Laws.normal(P.split(d, g, dir, k, lo, hi, limit, rest, (len - c1u : U32), (cu - c1u : U32), Nat.sub(count, c1)))
      +low_is = Laws.split_sweeps(d, g, dir, k, lo, hi, limit, pts, len, c1u, c1)
      +high_is = Laws.split_sweeps(d, g, dir, k, lo, hi, limit, rest, (len - c1u : U32), (cu - c1u : U32), Nat.sub(count, c1))
      %Equal.sym(G.Edges, low, Laws.normal(P.sweeps(pts, c1, g, dir, k, lo, hi, limit)), low_is) : {Laws.cat(_, high) == Laws.normal(P.sweeps(pts, count, g, dir, k, lo, hi, limit)) : G.Edges}
      %Equal.sym(G.Edges, high, Laws.normal(P.sweeps(rest, Nat.sub(count, c1), g, dir, k, lo, hi, limit)), high_is) : {Laws.cat(Laws.normal(P.sweeps(pts, c1, g, dir, k, lo, hi, limit)), _) == Laws.normal(P.sweeps(pts, count, g, dir, k, lo, hi, limit)) : G.Edges}
      %min_sub(count, U32.to_nat(c1u)) : {Laws.cat(Laws.normal(P.sweeps(pts, c1, g, dir, k, lo, hi, limit)), Laws.normal(P.sweeps(rest, Nat.sub(count, c1), g, dir, k, lo, hi, limit))) == Laws.normal(P.sweeps(pts, _, g, dir, k, lo, hi, limit)) : G.Edges}
      Laws.sweeps_split(pts, c1, Nat.sub(count, c1), g, dir, k, lo, hi, limit)
