# Times one build of a series' graph, as ts2vg's `build` does it: the edges,
# then the degree of each node.
#   bench INPUT natural|horizontal [LIMIT [XS]]
# prints `points edges checksum edges_ms degrees_ms`. The checksum, the sum of every
# edge's ends and every degree, makes the run read the whole graph.
import Base
import ../src/graph.bend as G
import ../src/parallel.bend as Par
import ../src/vg.bend as VG
import ../src/series.bend as Series
import ../src/report.bend as Report

type Tally is Data:
  Tally{m: U32, sum: U32}

def tally(es: G.Edges, t: Tally) -> Tally:
  match es:
    case G.ENil{}:
      t
    case G.ECon{s, d, w, next}:
      Tally{m, sum} = t
      tally(next, Tally{(m + 1 : U32), (sum + s + d : U32)})
    case G.EJoin{a, b}:
      tally(b, tally(a, t))

def both(x: Tally, y: Tally) -> Tally:
  match x y:
    case Tally{m1, s1} Tally{m2, s2}:
      Tally{(m1 + m2 : U32), (s1 + s2 : U32)}

def tally_tree(depth: Nat, es: G.Edges) -> Tally:
  match depth es:
    case 1n++p G.EJoin{a, b}:
      x y = tally_tree(p, a) tally_tree(p, b)
      both(x, y)
    case 0n G.EJoin{a, b}:
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
  Timed{es: G.Edges, t: Tally, now: Nat}

# The time once the tally `t` of the edges `es` is computed.
def stamp_edges(es: G.Edges, t: Tally) -> IO(Timed):
  match t:
    case Tally{m, sum}:
      do IO<Timed>:
        now : Nat <- IO.now()
        return Timed{es, Tally{m, sum}, now}

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
  Timed{es, t, +t1} = timed
  do IO<Unit>:
    done : Tally & Nat <- stamp(add_degrees(t, degree_sum(U32.to_nat(n), 0, Array.get(U32, Par.degrees(es, n), 0), 0)))
    report(n, t0, t1, done)

def edges_of(+n: U32, +t0: Nat, +es: G.Edges) -> IO(Unit):
  do IO<Unit>:
    timed : Timed <- stamp_edges(es, tally_tree(Par.fork_depth(), es))
    degrees_of(n, t0, timed)

def from_values(+g: G.Graph, +limit: U32, +n: U32, ys: Array<F32>, xs: G.Xs) -> IO(Unit):
  do IO<Unit>:
    t0 : Nat <- IO.now()
    edges_of(n, t0, Par.build(VG.Options{g, G.Undirected{}, G.Unweighted{}, G.neg_inf(), G.inf(), limit}, VG.Series{n, ys, xs}))

# The x of each value: the index, or the values of XS.
def xs_of(x: Maybe<&2, Series.Parsed>, +n: U32) -> G.Xs:
  match x:
    case Some{Series.Values{rev, m}}:
      G.At{Series.ys(rev, n)}
    case _:
      G.Index{}

def timed(g: G.Graph, +limit: U32, p: Series.Parsed, x: Maybe<&2, Series.Parsed>) -> IO(Unit):
  match p:
    case Series.Bad{line}:
      IO.die(Unit, 1, "line " ++ U32.show(line) ++ " holds no number")
    case Series.Values{rev, +n}:
      from_values(g, limit, n, Series.ys(rev, n), xs_of(x, n))

def graph_of(horizontal: Bool) -> G.Graph:
  match horizontal:
    case True{}:
      G.Horizontal{}
    case False{}:
      G.Natural{}

def limit_of(found: Maybe<&2, U32>) -> U32:
  match found:
    case Some{l}:
      l
    case None{}:
      0

def start(args: List<String>) -> IO(Unit):
  match args:
    case Con{prog, Con{input, Con{+kind, Nil{}}}}:
      do IO<Unit>:
        text : String <- Series.read_text(input)
        timed(graph_of(String.eq(kind, "horizontal")), 0, Series.parse(text), None{})
    case Con{prog, Con{input, Con{+kind, Con{limit, Nil{}}}}}:
      do IO<Unit>:
        text : String <- Series.read_text(input)
        timed(graph_of(String.eq(kind, "horizontal")), limit_of(U32.read(limit)), Series.parse(text), None{})
    case Con{prog, Con{input, Con{+kind, Con{limit, Con{xs, Nil{}}}}}}:
      do IO<Unit>:
        text : String <- Series.read_text(input)
        xtext : String <- Series.read_text(xs)
        timed(graph_of(String.eq(kind, "horizontal")), limit_of(U32.read(limit)), Series.parse(text), Some{Series.parse(xtext)})
    case _:
      IO.die(Unit, 2, "usage: bench INPUT natural|horizontal [LIMIT [XS]]")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    start(args)
