# The proofs of LAWS.bend, each by induction on a list or on the depth of the
# split.
import Base
import ./visgraph.bend as VG
import ./parallel.bend as Par
import ./LAWS.bend as Laws

# Each step moves a chunk onto acc, as rev_onto does.
def Laws.halve_keeps(k, cs, na, total, acc):
  match k cs:
    case 1n+q Par.CCon{start, count, next}:
      Laws.halve_keeps(q, next, na, total, Par.CCon{start, count, acc})
    case 1n+q Par.CNil{}:
      {==}
    case 0n _:
      {==}

def cat_assoc(a: VG.Edges, +b: VG.Edges, +c: VG.Edges) -> {Laws.cat(Laws.cat(a, b), c) == Laws.cat(a, Laws.cat(b, c)) : VG.Edges}:
  match a:
    case VG.ENil{}:
      {==}
    case VG.ECon{+s, +t, +w, next}:
      %cat_assoc(next, b, c) : {VG.ECon{s, t, w, Laws.cat(Laws.cat(next, b), c)} == VG.ECon{s, t, w, _} : VG.Edges}
      {==}
    case VG.EJoin{+x, +y}:
      %cat_assoc(y, b, c) : {Laws.cat(Laws.cat(x, Laws.cat(y, b)), c) == Laws.cat(x, _) : VG.Edges}
      cat_assoc(x, Laws.cat(y, b), c)

# Taking the first start out of the first range: the hypothesis covers the
# rest, and cat_assoc regroups the first start's rope.
def Laws.sweeps_split(pts, c1, c2, g, dir, k, lo, hi, limit):
  match pts c1:
    case VG.PNil{} 0n:
      {==}
    case VG.PNil{} 1n+c:
      {==}
    case VG.PCon{i, x, y, next} 0n:
      {==}
    case VG.PCon{+i, +x, +y, +next} 1n+c:
      +first = Laws.normal(VG.sweep(g, dir, k, lo, hi, limit, i, x, y, next, VG.ENil{}))
      +a = Laws.normal(VG.sweeps(next, c, g, dir, k, lo, hi, limit))
      +b = Laws.normal(VG.sweeps(VG.drop(c, next), c2, g, dir, k, lo, hi, limit))
      %Laws.sweeps_split(next, c, c2, g, dir, k, lo, hi, limit) : {Laws.cat(Laws.cat(first, a), b) == Laws.cat(first, _) : VG.Edges}
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
      +c1u = VG.first_half(g, len, cu)
      +c1 = Nat.min(count, U32.to_nat(c1u))
      +rest = VG.drop(c1, pts)
      +low = Laws.normal(VG.split(d, g, dir, k, lo, hi, limit, pts, len, c1u, c1))
      +high = Laws.normal(VG.split(d, g, dir, k, lo, hi, limit, rest, (len - c1u : U32), (cu - c1u : U32), Nat.sub(count, c1)))
      +low_is = Laws.split_sweeps(d, g, dir, k, lo, hi, limit, pts, len, c1u, c1)
      +high_is = Laws.split_sweeps(d, g, dir, k, lo, hi, limit, rest, (len - c1u : U32), (cu - c1u : U32), Nat.sub(count, c1))
      %Equal.sym(VG.Edges, low, Laws.normal(VG.sweeps(pts, c1, g, dir, k, lo, hi, limit)), low_is) : {Laws.cat(_, high) == Laws.normal(VG.sweeps(pts, count, g, dir, k, lo, hi, limit)) : VG.Edges}
      %Equal.sym(VG.Edges, high, Laws.normal(VG.sweeps(rest, Nat.sub(count, c1), g, dir, k, lo, hi, limit)), high_is) : {Laws.cat(Laws.normal(VG.sweeps(pts, c1, g, dir, k, lo, hi, limit)), _) == Laws.normal(VG.sweeps(pts, count, g, dir, k, lo, hi, limit)) : VG.Edges}
      %min_sub(count, U32.to_nat(c1u)) : {Laws.cat(Laws.normal(VG.sweeps(pts, c1, g, dir, k, lo, hi, limit)), Laws.normal(VG.sweeps(rest, Nat.sub(count, c1), g, dir, k, lo, hi, limit))) == Laws.normal(VG.sweeps(pts, _, g, dir, k, lo, hi, limit)) : VG.Edges}
      Laws.sweeps_split(pts, c1, Nat.sub(count, c1), g, dir, k, lo, hi, limit)
