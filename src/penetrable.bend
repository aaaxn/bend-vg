# Limited penetrable visibility graphs, as ts2vg 1.2.4's _natural_penetrable
# and _horizontal_penetrable build them, in F32: every point sweeps the
# points right of it, and an edge may cross up to `limit` points. The sweeps
# are independent, so the points split into parallel ranges of equal work.
import Base
import ./graph.bend as G

# The points, in a list the parallel ranges share.
type Pts is Data:
  PNil{}
  PCon{i: U32, x: F32, y: F32, next: Pts}

# The points of `ys` from index `i` down to 0, onto `acc`; `yr` holds y at
# `i`. The last read, at index -1, wraps around.
def points(count: Nat, +i: U32, yr: Array<F32> & F32, acc: Pts) -> Pts:
  match count:
    case 0n:
      (ys, y) = yr
      acc
    case 1n+c:
      (ys, +y) = yr
      +i2 = (i - 1 : U32)
      points(c, i2, Array.get(F32, ys, i2), PCon{i, U32.to_f32(i), y, acc})

# The `limit + 1` largest slopes (or heights) a sweep has accepted, as ts2vg's
# max_slopes; the sweep accepts a point above the smallest of them.
type Tops is Data:
  TNil{}
  TCon{v: F32, next: Tops}

# The position and value of the first smallest top.
type Low is Data:
  Low{k: Nat, v: F32}

def tops_new(n: Nat) -> Tops:
  match n:
    case 0n:
      TCon{G.neg_inf(), TNil{}}
    case 1n+p:
      TCon{G.neg_inf(), tops_new(p)}

def pick_low(c: Bool, a: Low, b: Low) -> Low:
  match c:
    case True{}:
      a
    case False{}:
      b

def low_from(ts: Tops, +k: Nat, +best: Low) -> Low:
  match ts:
    case TNil{}:
      best
    case TCon{+v, next}:
      Low{bk, +bv} = best
      low_from(next, 1n+k, pick_low(F32.is_lt(v, bv), Low{k, v}, Low{bk, bv}))

def lowest(ts: Tops) -> Low:
  low_from(ts, 0n, Low{0n, G.inf()})

def Low.v(+l: Low) -> F32:
  Low{k, v} = l
  v

def set_at(k: Nat, ts: Tops, v: F32) -> Tops:
  match k ts:
    case 0n TCon{old, next}:
      TCon{v, next}
    case 1n+p TCon{old, next}:
      TCon{old, set_at(p, next, v)}
    case _ TNil{}:
      TNil{}

# How many tops a natural edge with slope `s` does not clear, as ts2vg's
# num_penetrations weight.
def blocked_natural(ts: Tops, +s: F32, +t: F32, +n: F32) -> F32:
  match ts:
    case TNil{}:
      n
    case TCon{v, next}:
      blocked_natural(next, s, t, G.pick(G.greater(s, v, t), n, F32.add(n, 1.0)))

def blocked_horizontal(ts: Tops, +ya: F32, +yb: F32, +n: F32) -> F32:
  match ts:
    case TNil{}:
      n
    case TCon{+v, next}:
      blocked_horizontal(next, ya, yb, G.pick(F32.is_le(ya, v) || F32.is_le(yb, v), F32.add(n, 1.0), n))

# ts2vg's add_edge with a known weight: NaN means the weight function
# computes it.
def add_known(+k: G.Weight, +lo: F32, +hi: F32, i1: U32, i2: U32, +x1: F32, +x2: F32, +y1: F32, +y2: F32, +s: F32, +known: F32, es: G.Edges) -> G.Edges:
  +w = G.pick(G.is_nan(known), G.weight(k, x1, x2, y1, y2, s), known)
  G.put(F32.is_le(w, lo) || F32.is_ge(w, hi), i1, i2, w, es)

# The edge from a to b, or from b to a for top_to_bottom when b is higher.
def add_oriented(down: Bool, +k: G.Weight, +lo: F32, +hi: F32, ia: U32, ib: U32, xa: F32, xb: F32, ya: F32, yb: F32, s: F32, known: F32, es: G.Edges) -> G.Edges:
  match down:
    case True{}:
      add_known(k, lo, hi, ib, ia, xb, xa, yb, ya, s, known, es)
    case False{}:
      add_known(k, lo, hi, ia, ib, xa, xb, ya, yb, s, known, es)

def is_down(dir: G.Direction, +ya: F32, +yb: F32) -> Bool:
  match dir:
    case G.TopToBottom{}:
      F32.is_gt(yb, ya)
    case _:
      False{}

def is_count(k: G.Weight) -> Bool:
  match k:
    case G.NumPenetrations{}:
      True{}
    case _:
      False{}

def natural_edge(+dir: G.Direction, +k: G.Weight, +lo: F32, +hi: F32, ia: U32, ib: U32, +xa: F32, +xb: F32, +ya: F32, +yb: F32, +s: F32, +scale_a: F32, ts: Tops, es: G.Edges) -> G.Edges:
  +known = G.pick(is_count(k), blocked_natural(ts, s, G.tol(scale_a, xb, yb), 0.0), G.nan())
  add_oriented(is_down(dir, ya, yb), k, lo, hi, ia, ib, xa, xb, ya, yb, s, known, es)

def horizontal_edge(+dir: G.Direction, +k: G.Weight, +lo: F32, +hi: F32, ia: U32, ib: U32, +xa: F32, xb: F32, +ya: F32, +yb: F32, ts: Tops, es: G.Edges) -> G.Edges:
  +known = G.pick(is_count(k), blocked_horizontal(ts, ya, yb, 0.0), G.nan())
  add_oriented(is_down(dir, ya, yb), k, lo, hi, ia, ib, xa, xb, ya, yb, G.nan(), known, es)

# The sweep of point a over the points right of it: ts2vg's inner loop. A
# point b the sweep sees replaces the smallest top and adds its edge at the
# next step, when `up` says so, so a step after an unseen point calls no
# def that recurses.
def natural_sweep(pts: Pts, up: Bool, +dir: G.Direction, +k: G.Weight, +lo: F32, +hi: F32, +ia: U32, +xa: F32, +ya: F32, +scale_a: F32, +ts: Tops, low: Low, +ib: U32, +xb: F32, +yb: F32, +sb: F32, es: G.Edges) -> G.Edges:
  match pts up:
    case PNil{} False{}:
      es
    case PNil{} True{}:
      natural_edge(dir, k, lo, hi, ia, ib, xa, xb, ya, yb, sb, scale_a, ts, es)
    case PCon{+ic, +xc, +yc, next} False{}:
      Low{+lk, +lv} = low
      +s = F32.div(F32.sub(yc, ya), F32.sub(xc, xa))
      natural_sweep(next, G.clears(F32.is_gt(s, lv), s, lv, scale_a, xc, yc), dir, k, lo, hi, ia, xa, ya, scale_a, ts, Low{lk, lv}, ic, xc, yc, s, es)
    case PCon{+ic, +xc, +yc, next} True{}:
      Low{+lk, lv} = low
      +after = set_at(lk, ts, sb)
      +now = lowest(after)
      +s = F32.div(F32.sub(yc, ya), F32.sub(xc, xa))
      natural_sweep(next, G.clears(F32.is_gt(s, Low.v(now)), s, Low.v(now), scale_a, xc, yc), dir, k, lo, hi, ia, xa, ya, scale_a, after, now, ic, xc, yc, s, natural_edge(dir, k, lo, hi, ia, ib, xa, xb, ya, yb, sb, scale_a, ts, es))

# The same for the horizontal sweep, which stops once the smallest top is
# above a: no later point can be seen.
def horizontal_sweep(pts: Pts, up: Bool, stop: Bool, +dir: G.Direction, +k: G.Weight, +lo: F32, +hi: F32, +ia: U32, +xa: F32, +ya: F32, +ts: Tops, low: Low, +ib: U32, +xb: F32, +yb: F32, es: G.Edges) -> G.Edges:
  match pts up stop:
    case _ False{} True{}:
      es
    case PNil{} False{} False{}:
      es
    case PNil{} True{} _:
      horizontal_edge(dir, k, lo, hi, ia, ib, xa, xb, ya, yb, ts, es)
    case PCon{+ic, xc, +yc, next} False{} False{}:
      Low{+lk, +lv} = low
      horizontal_sweep(next, F32.is_gt(ya, lv) && F32.is_gt(yc, lv), False{}, dir, k, lo, hi, ia, xa, ya, ts, Low{lk, lv}, ic, xc, yc, es)
    case PCon{+ic, xc, +yc, next} True{} _:
      Low{+lk, lv} = low
      +after = set_at(lk, ts, yb)
      +now = lowest(after)
      horizontal_sweep(next, F32.is_gt(ya, Low.v(now)) && F32.is_gt(yc, Low.v(now)), F32.is_gt(Low.v(now), ya), dir, k, lo, hi, ia, xa, ya, after, now, ic, xc, yc, horizontal_edge(dir, k, lo, hi, ia, ib, xa, xb, ya, yb, ts, es))

def sweep(g: G.Graph, +dir: G.Direction, +k: G.Weight, +lo: F32, +hi: F32, +limit: Nat, ia: U32, +xa: F32, +ya: F32, pts: Pts, es: G.Edges) -> G.Edges:
  match g:
    case G.Natural{}:
      natural_sweep(pts, False{}, dir, k, lo, hi, ia, xa, ya, G.scale(xa, ya), tops_new(limit), Low{0n, G.neg_inf()}, 0, 0.0, 0.0, 0.0, es)
    case G.Horizontal{}:
      horizontal_sweep(pts, False{}, False{}, dir, k, lo, hi, ia, xa, ya, tops_new(limit), Low{0n, G.neg_inf()}, 0, 0.0, 0.0, es)

# The sweeps of the first `count` points of `pts`, one rope each: ts2vg's
# outer loop.
def sweeps(pts: Pts, count: Nat, +g: G.Graph, +dir: G.Direction, +k: G.Weight, +lo: F32, +hi: F32, +limit: Nat) -> G.Edges:
  match pts count:
    case PCon{i, x, y, +next} 1n+c:
      G.EJoin{sweep(g, dir, k, lo, hi, limit, i, x, y, next, G.ENil{}), sweeps(next, c, g, dir, k, lo, hi, limit)}
    case _ _:
      G.ENil{}

def drop(n: Nat, pts: Pts) -> Pts:
  match n pts:
    case 1n+p PCon{i, x, y, next}:
      drop(p, next)
    case _ _:
      pts

# How many of the first `count` of `len` points do half the sweeps' work. A
# natural sweep walks every point right of its start, so the first c starts
# walk c (2 len - 1 - c) / 2 points; a horizontal sweep stops early, so
# halving the starts is close enough.
def first_half(g: G.Graph, +len: U32, +count: U32) -> U32:
  match g:
    case G.Natural{}:
      +b = F32.sub(F32.mul(2.0, U32.to_f32(len)), 1.0)
      +c = U32.to_f32(count)
      U32.min(count, F32.to_u32(F32.div(F32.sub(b, F32.sqrt(F32.sub(F32.mul(b, b), F32.mul(2.0, F32.mul(c, F32.sub(b, c)))))), 2.0)))
    case G.Horizontal{}:
      U32.div(count, 2)

# The sweeps of the first `count` points of `pts`, as two halves of equal
# work in parallel, `depth` times over. `len` and `cu` are `pts`'s length
# and `count` as U32; they only place the cut.
def split(depth: Nat, +g: G.Graph, +dir: G.Direction, +k: G.Weight, +lo: F32, +hi: F32, +limit: Nat, +pts: Pts, +len: U32, +cu: U32, +count: Nat) -> G.Edges:
  match depth:
    case 0n:
      sweeps(pts, count, g, dir, k, lo, hi, limit)
    case 1n++d:
      +c1u = first_half(g, len, cu)
      +c1 = Nat.min(count, U32.to_nat(c1u))
      a b = split(d, g, dir, k, lo, hi, limit, pts, len, c1u, c1) split(d, g, dir, k, lo, hi, limit, drop(c1, pts), (len - c1u : U32), (cu - c1u : U32), Nat.sub(count, c1))
      G.EJoin{a, b}

# The limited penetrable graph of the `n` values `ys`, each at its index,
# crossing at most `limit` points. x is the index as an F32, exact for up
# to 2^24 values.
def build(+g: G.Graph, +dir: G.Direction, +k: G.Weight, +lo: F32, +hi: F32, +limit: U32, ys: Array<F32>, +n: U32) -> G.Edges:
  split(7n, g, dir, k, lo, hi, U32.to_nat(limit), points(U32.to_nat(n), (n - 1 : U32), Array.get(F32, ys, (n - 1 : U32)), PNil{}), n, n, U32.to_nat(n))
