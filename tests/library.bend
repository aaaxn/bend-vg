# What the library reads off a graph, which the tests compare with ts2vg:
#   library INPUT natural|horizontal undirected|left_to_right|top_to_bottom
# prints a fold's count of the edges and sum of their ends, the degrees,
# and the adjacency's offsets, targets and weights, one line each.
import Base
import ../src/graph.bend as G
import ../src/vg.bend as VG
import ../src/series.bend as Series

type Tally is Data:
  Tally{m: U32, ends: U32}

def tally(t: Tally, +s: U32, +d: U32) -> Tally:
  Tally{m, ends} = t
  Tally{(m + 1 : U32), (ends + s + d : U32)}

def tally_text(t: Tally) -> String:
  Tally{m, ends} = t
  "f " ++ U32.show(m) ++ " " ++ U32.show(ends) ++ "\n"

# The `count` values of an array up to index `i`, each after a space.
def u32s(count: Nat, +i: U32, r: Array<U32> & U32, acc: String) -> String:
  match count:
    case 0n:
      (a, v) = r
      acc
    case 1n+c:
      (a, +v) = r
      u32s(c, (i - 1 : U32), Array.get(U32, a, (i - 1 : U32)), " " ++ U32.show(v) ++ acc)

def f32s(count: Nat, +i: U32, r: Array<F32> & F32, acc: String) -> String:
  match count:
    case 0n:
      (a, v) = r
      acc
    case 1n+c:
      (a, +v) = r
      f32s(c, (i - 1 : U32), Array.get(F32, a, (i - 1 : U32)), " " ++ F32.show(v) ++ acc)

def degrees_text(+n: U32, d: Array<U32>) -> String:
  "d" ++ u32s(U32.to_nat(n), (n - 1 : U32), Array.get(U32, d, (n - 1 : U32)), "") ++ "\n"

def rows_text(+n: U32, r: Array<U32> & U32, targets: Array<U32>, weights: Array<F32>) -> String:
  (offsets, +h) = r
  "o" ++ u32s(U32.to_nat((n + 1 : U32)), n, Array.get(U32, offsets, n), "") ++ "\nt" ++ u32s(U32.to_nat(h), (h - 1 : U32), Array.get(U32, targets, (h - 1 : U32)), "") ++ "\nw" ++ f32s(U32.to_nat(h), (h - 1 : U32), Array.get(F32, weights, (h - 1 : U32)), "") ++ "\n"

def adjacency_text(+n: U32, a: VG.Adjacency) -> String:
  VG.Adjacency{offsets, targets, weights} = a
  rows_text(n, Array.get(U32, offsets, n), targets, weights)

def outputs(+dir: G.Direction, +n: U32, +es: G.Edges) -> String:
  tally_text(VG.fold(~Tally, ~(t => +s => +d => w => tally(t, s, d)), es, Tally{0, 0})) ++ degrees_text(n, VG.degrees(es, n)) ++ adjacency_text(n, VG.adjacency(dir, es, n))

def report(+g: G.Graph, +dir: G.Direction, +k: G.Weight, p: Series.Parsed) -> IO(Unit):
  match p:
    case Series.Bad{line}:
      IO.die(Unit, 1, "line " ++ U32.show(line) ++ " holds no number")
    case Series.Values{rev, +n}:
      IO.write(outputs(dir, n, VG.build(VG.Options{g, dir, k, G.neg_inf(), G.inf(), 0}, VG.Series{n, Series.ys(rev, n), G.Index{}})))

def graph_of(horizontal: Bool) -> G.Graph:
  match horizontal:
    case True{}:
      G.Horizontal{}
    case False{}:
      G.Natural{}

def direction_of(ltr: Bool, ttb: Bool) -> G.Direction:
  match ltr ttb:
    case True{} _:
      G.LeftToRight{}
    case False{} True{}:
      G.TopToBottom{}
    case False{} False{}:
      G.Undirected{}

def start(args: List<String>) -> IO(Unit):
  match args:
    case Con{prog, Con{input, Con{+kind, Con{+dir, Nil{}}}}}:
      do IO<Unit>:
        text : String <- Series.read_text(input)
        report(graph_of(String.eq(kind, "horizontal")), direction_of(String.eq(dir, "left_to_right"), String.eq(dir, "top_to_bottom")), G.Distance{}, Series.parse(text))
    case _:
      IO.die(Unit, 2, "usage: library INPUT natural|horizontal undirected|left_to_right|top_to_bottom")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    start(args)
