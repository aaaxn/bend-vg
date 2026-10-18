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

def append_assoc(a: G.Pts, +b: G.Pts, +c: G.Pts) -> {Laws.append(Laws.append(a, b), c) == Laws.append(a, Laws.append(b, c)) : G.Pts}:
  match a:
    case G.PNil{}:
      {==}
    case G.PCon{+i, +x, +y, next}:
      %append_assoc(next, b, c) : {G.PCon{i, x, y, Laws.append(Laws.append(next, b), c)} == G.PCon{i, x, y, _} : G.Pts}
      {==}

def rev_rev(a: G.Pts, +acc: G.Pts) -> {Laws.rev_onto(Laws.rev_onto(a, acc), G.PNil{}) == Laws.rev_onto(acc, a) : G.Pts}:
  match a:
    case G.PNil{}:
      {==}
    case G.PCon{i, x, y, next}:
      rev_rev(next, G.PCon{i, x, y, acc})

def rev_append(a: G.Pts, +b: G.Pts, +acc: G.Pts) -> {Laws.rev_onto(Laws.append(a, b), acc) == Laws.rev_onto(b, Laws.rev_onto(a, acc)) : G.Pts}:
  match a:
    case G.PNil{}:
      {==}
    case G.PCon{i, x, y, next}:
      rev_append(next, b, G.PCon{i, x, y, acc})

def rev_onto_append(l: G.Pts, +m: G.Pts, +acc: G.Pts) -> {Laws.append(Laws.rev_onto(l, m), acc) == Laws.rev_onto(l, Laws.append(m, acc)) : G.Pts}:
  match l:
    case G.PNil{}:
      {==}
    case G.PCon{i, x, y, next}:
      rev_onto_append(next, G.PCon{i, x, y, m}, acc)

# take_rev_cuts gives the cut. Walking rightward, the left side is `pre`
# reversed, so it reverses back to `pre`. Walking leftward, the left side is
# `post` and the right side is `pre` reversed, and the interval reversed is
# `post` reversed, the pivot, then `pre` reversed.
def Laws.sides_keep(walk, pre, i, x, y, post):
  match walk:
    case G.Rightward{}:
      +r = Laws.rev_onto(pre, G.PNil{})
      cuts = Equal.sym(G.Pts & G.Pts, G.take_rev(Laws.length(pre), Laws.append(pre, G.PCon{i, x, y, post}), G.PNil{}), (r, post), Laws.take_rev_cuts(pre, i, x, y, post, G.PNil{}))
      %cuts : {Laws.joined(G.sides(G.Rightward{}, _), i, x, y) == Laws.append(pre, G.PCon{i, x, y, post}) : G.Pts}
      %rev_rev(pre, G.PNil{}) : {Laws.append(Laws.rev_onto(r, G.PNil{}), G.PCon{i, x, y, post}) == Laws.append(_, G.PCon{i, x, y, post}) : G.Pts}
      {==}
    case G.Leftward{}:
      +r = Laws.rev_onto(pre, G.PNil{})
      cuts = Equal.sym(G.Pts & G.Pts, G.take_rev(Laws.length(pre), Laws.append(pre, G.PCon{i, x, y, post}), G.PNil{}), (r, post), Laws.take_rev_cuts(pre, i, x, y, post, G.PNil{}))
      +whole = Laws.append(pre, G.PCon{i, x, y, post})
      %cuts : {Laws.joined(G.sides(G.Leftward{}, _), i, x, y) == Laws.rev_onto(whole, G.PNil{}) : G.Pts}
      %Equal.sym(G.Pts, Laws.rev_onto(whole, G.PNil{}), Laws.rev_onto(post, G.PCon{i, x, y, r}), rev_append(pre, G.PCon{i, x, y, post}, G.PNil{})) : {Laws.append(Laws.rev_onto(post, G.PNil{}), G.PCon{i, x, y, r}) == _ : G.Pts}
      rev_onto_append(post, G.PNil{}, G.PCon{i, x, y, r})

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
    case P.PNil{} 0n:
      {==}
    case P.PNil{} 1n+c:
      {==}
    case P.PCon{i, x, y, next} 0n:
      {==}
    case P.PCon{+i, +x, +y, +next} 1n+c:
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
