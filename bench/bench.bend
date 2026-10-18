# Times one build of a series' graph, as ts2vg's `build` does it: the edges,
# then the degree of each node.
#   bench INPUT natural|horizontal
# prints `points edges checksum edges_ms degrees_ms`. The checksum, the sum of every
# edge's ends and every degree, makes the run read the whole graph.
import Base
import ../src/graph.bend as G
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

def degree_sum(xs: List<U32>, +acc: U32) -> U32:
  match xs:
    case Nil{}:
      acc
    case Con{x, rest}:
      degree_sum(rest, (acc + x : U32))

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
    done : Tally & Nat <- stamp(add_degrees(t, degree_sum(Array.to_list(~U32, Report.degrees(es, Report.slots(n))), 0)))
    report(n, t0, t1, done)

def edges_of(+n: U32, +t0: Nat, +es: G.Edges) -> IO(Unit):
  do IO<Unit>:
    timed : Timed <- stamp_edges(es, tally(es, Tally{0, 0}))
    degrees_of(n, t0, timed)

def timed(g: G.Graph, p: Series.Parsed) -> IO(Unit):
  match p:
    case Series.Bad{line}:
      IO.die(Unit, 1, "line " ++ U32.show(line) ++ " holds no number")
    case Series.Values{rev, +n}:
      +pts = Series.points(rev, (n - 1 : U32), G.PNil{})
      do IO<Unit>:
        t0 : Nat <- IO.now()
        edges_of(n, t0, G.build(g, G.Undirected{}, G.Unweighted{}, G.neg_inf(), G.inf(), pts, n))

def graph_of(horizontal: Bool) -> G.Graph:
  match horizontal:
    case True{}:
      G.Horizontal{}
    case False{}:
      G.Natural{}

def read_text.done(m: File & Result<&1, &1, U32 & String, String>) -> IO(String):
  (f, r) = m
  do IO<String>:
    text : String <- IO.pass(String, r)
    File.close(f)
    return text

def read_text.sized(m: File & Result<&1, &1, U32 & String, U32>) -> IO(String):
  (f, r) = m
  do IO<String>:
    size : U32 <- IO.pass(U32, r)
    got : File & Result<&1, &1, U32 & String, String> <- File.read(f, size)
    read_text.done(got)

def read_text(path: String) -> IO(String):
  do IO<String>:
    f : File <- IO.try(File, File.open(path, "r"))
    sized : File & Result<&1, &1, U32 & String, U32> <- File.size(f)
    read_text.sized(sized)

def start(args: List<String>) -> IO(Unit):
  match args:
    case Con{prog, Con{input, Con{+kind, rest}}}:
      do IO<Unit>:
        text : String <- read_text(input)
        timed(graph_of(String.eq(kind, "horizontal")), Series.parse(text))
    case _:
      IO.die(Unit, 2, "usage: bench INPUT natural|horizontal")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    start(args)
