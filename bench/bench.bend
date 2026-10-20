# Times one build of a series' graph, as ts2vg's `build` does it: the edges,
# then the degree of each node.
#   bench INPUT natural|horizontal [LIMIT [XS]]
# prints `points edges checksum edges_ms degrees_ms`. The checksum, the sum of every
# edge's ends and every degree, makes the run read the whole graph.
import Base
import ../visgraph.bend as VG
import ../parallel.bend as Par
import ../src/series.bend as Series

type Tally is Data:
  Tally{m: U32, sum: U32}

def tally(es: VG.Edges, t: Tally) -> Tally:
  match es:
    case VG.ENil{}:
      t
    case VG.ECon{s, d, w, next}:
      Tally{m, sum} = t
      tally(next, Tally{(m + 1 : U32), (sum + s + d : U32)})
    case VG.EJoin{a, b}:
      tally(b, tally(a, t))

def both(x: Tally, y: Tally) -> Tally:
  match x y:
    case Tally{m1, s1} Tally{m2, s2}:
      Tally{(m1 + m2 : U32), (s1 + s2 : U32)}

def tally_tree(depth: Nat, es: VG.Edges) -> Tally:
  match depth es:
    case 1n++p VG.EJoin{a, b}:
      x y = tally_tree(p, a) tally_tree(p, b)
      both(x, y)
    case 0n VG.EJoin{a, b}:
      x y = tally(a, Tally{0, 0}) tally(b, Tally{0, 0})
      both(x, y)
    case _ _:
      tally(es, Tally{0, 0})

def degree_sum(count: Nat, +i: U32, r: Array<U32> & U32, +acc: U32) -> U32:
  match count:
    case 0n:
      (d, v) = r
      acc
    case 1n+c:
      (d, +v) = r
      degree_sum(c, (i + 1 : U32), Array.get(U32, d, (i + 1 : U32)), (acc + v : U32))

def add_degrees(t: Tally, +d: U32) -> Tally:
  Tally{m, sum} = t
  Tally{m, (sum + d : U32)}

type Timed is Type:
  Timed{g: VG.Graph, t: Tally, now: Nat}

# The time once the tally `t` of the edges `es` is computed.
def stamp_edges(g: VG.Graph, t: Tally) -> IO(Timed):
  match t:
    case Tally{m, sum}:
      do IO<Timed>:
        now : Nat <- IO.now()
        return Timed{g, Tally{m, sum}, now}

def stamp(t: Tally) -> IO(Tally & Nat):
  match t:
    case Tally{m, sum}:
      do IO<Tally & Nat>:
        now : Nat <- IO.now()
        return (Tally{m, sum}, now)

def report(+n: U32, +t0: Nat, +t1: Nat, done: Tally & Nat) -> IO(Unit):
  (t, t2) = done
  match t:
    case Tally{m, sum}:
      IO.print(U32.show(n) ++ " " ++ U32.show(m) ++ " " ++ U32.show(sum) ++ " " ++ Nat.show(Nat.sub(t1, t0)) ++ " " ++ Nat.show(Nat.sub(t2, t1)))

def degrees_of(+n: U32, +t0: Nat, timed: Timed) -> IO(Unit):
  Timed{g, t, +t1} = timed
  do IO<Unit>:
    done : Tally & Nat <- stamp(add_degrees(t, degree_sum(U32.to_nat(n), 0, Array.get(U32, Par.degrees(g), 0), 0)))
    report(n, t0, t1, done)

def edges_of(+n: U32, +t0: Nat, +g: VG.Graph) -> IO(Unit):
  VG.Graph{m, dir, +es} = g
  do IO<Unit>:
    timed : Timed <- stamp_edges(g, tally_tree(Par.fork_depth(), es))
    degrees_of(n, t0, timed)

def from_values(+g: VG.Visibility, +limit: U32, +n: U32, ys: Array<F32>, xs: VG.Xs) -> IO(Unit):
  do IO<Unit>:
    t0 : Nat <- IO.now()
    edges_of(n, t0, Par.build(VG.Options{g, VG.Undirected{}, VG.Unweighted{}, VG.neg_inf(), VG.inf(), limit}, VG.Series{n, ys, xs}))

# x as the index is an F32, which holds every index below 2^24 exactly.
def from_index(too_long: Bool, +g: VG.Visibility, +limit: U32, rev: List<&2, F32>, +n: U32) -> IO(Unit):
  match too_long:
    case True{}:
      IO.die(Unit, 1, "bench takes at most 16777216 values, since x is the index as an F32")
    case False{}:
      from_values(g, limit, n, Series.ys(rev, n), VG.Index{})

def from_xs(x: Series.XsCheck, +g: VG.Visibility, +limit: U32, rev: List<&2, F32>, +n: U32) -> IO(Unit):
  match x:
    case Series.XsBad{msg}:
      IO.die(Unit, 1, msg)
    case Series.XsOk{xrev}:
      from_values(g, limit, n, Series.ys(rev, n), VG.At{Series.ys(xrev, n)})

def timed(+g: VG.Visibility, +limit: U32, p: Series.Parsed, x: Maybe<&2, Series.Parsed>) -> IO(Unit):
  match p x:
    case Series.Bad{line} _:
      IO.die(Unit, 1, "line " ++ U32.show(line) ++ " holds no number")
    case Series.Values{rev, +n} None{}:
      from_index(U32.is_gt(n, 16777216), g, limit, rev, n)
    case Series.Values{rev, +n} Some{xp}:
      from_xs(Series.xs(xp, n), g, limit, rev, n)

def usage() -> String:
  "usage: bench INPUT natural|horizontal [LIMIT [XS]]"

def graph_of(natural: Bool, horizontal: Bool) -> Maybe<&2, VG.Visibility>:
  match natural horizontal:
    case True{} _:
      Some{VG.Natural{}}
    case False{} True{}:
      Some{VG.Horizontal{}}
    case False{} False{}:
      None{}

def graph_named(+kind: String) -> Maybe<&2, VG.Visibility>:
  graph_of(String.eq(kind, "natural"), String.eq(kind, "horizontal"))

def read_xs(path: Maybe<&2, String>) -> IO(Maybe<&2, Series.Parsed>):
  match path:
    case None{}:
      IO.pure(Maybe<&2, Series.Parsed>, None{})
    case Some{xs}:
      do IO<Maybe<&2, Series.Parsed>>:
        text : String <- Series.read_text(xs)
        return Some{Series.parse(text)}

def run(g: Maybe<&2, VG.Visibility>, limit: Maybe<&2, U32>, input: String, xs: Maybe<&2, String>) -> IO(Unit):
  match g limit:
    case Some{+k} Some{+l}:
      do IO<Unit>:
        text : String <- Series.read_text(input)
        x : Maybe<&2, Series.Parsed> <- read_xs(xs)
        timed(k, l, Series.parse(text), x)
    case None{} _:
      IO.die(Unit, 2, "the graph is natural or horizontal\n" ++ usage())
    case _ None{}:
      IO.die(Unit, 2, "LIMIT is a whole number\n" ++ usage())

def start(args: List<String>) -> IO(Unit):
  match args:
    case Con{prog, Con{input, Con{kind, Nil{}}}}:
      run(graph_named(kind), Some{0}, input, None{})
    case Con{prog, Con{input, Con{kind, Con{limit, Nil{}}}}}:
      run(graph_named(kind), U32.read(limit), input, None{})
    case Con{prog, Con{input, Con{kind, Con{limit, Con{xs, Nil{}}}}}}:
      run(graph_named(kind), U32.read(limit), input, Some{xs})
    case _:
      IO.die(Unit, 2, usage())

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    start(args)
