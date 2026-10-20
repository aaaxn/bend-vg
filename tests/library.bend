# What the library reads off a graph, which the tests compare with ts2vg:
#   library INPUT natural|horizontal undirected|left_to_right|top_to_bottom [MIN MAX]
# prints a fold's count of the edges and sum of their ends, the degrees,
# and the adjacency's offsets, targets and weights, one line each. The
# weights are distances, and MIN and MAX bound them as ts2vg's min_weight
# and max_weight do.
import Base
import ../visgraph.bend as VG
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

def outputs(+n: U32, +g: VG.Graph) -> String:
  tally_text(VG.fold(~Tally, ~(t => +s => +d => w => tally(t, s, d)), g, Tally{0, 0})) ++ degrees_text(n, VG.degrees(g)) ++ adjacency_text(n, VG.adjacency(g))

def report(+g: VG.Visibility, +dir: VG.Direction, +k: VG.Weight, +lo: F32, +hi: F32, p: Series.Parsed) -> IO(Unit):
  match p:
    case Series.Bad{line}:
      IO.die(Unit, 1, "line " ++ U32.show(line) ++ " holds no number")
    case Series.Values{rev, +n}:
      IO.write(outputs(n, VG.build(VG.Options{g, dir, k, lo, hi, 0}, VG.Series{n, Series.ys(rev, n), VG.Index{}})))

def graph_of(horizontal: Bool) -> VG.Visibility:
  match horizontal:
    case True{}:
      VG.Horizontal{}
    case False{}:
      VG.Natural{}

def direction_of(ltr: Bool, ttb: Bool) -> VG.Direction:
  match ltr ttb:
    case True{} _:
      VG.LeftToRight{}
    case False{} True{}:
      VG.TopToBottom{}
    case False{} False{}:
      VG.Undirected{}

def usage() -> String:
  "usage: library INPUT natural|horizontal undirected|left_to_right|top_to_bottom [MIN MAX]"

def run(input: String, kind: String, +dir: String, lo: Maybe<&2, F32>, hi: Maybe<&2, F32>) -> IO(Unit):
  match lo hi:
    case Some{+l} Some{+h}:
      do IO<Unit>:
        text : String <- Series.read_text(input)
        report(graph_of(String.eq(kind, "horizontal")), direction_of(String.eq(dir, "left_to_right"), String.eq(dir, "top_to_bottom")), VG.Distance{}, l, h, Series.parse(text))
    case _ _:
      IO.die(Unit, 2, "MIN and MAX are numbers\n" ++ usage())

def start(args: List<String>) -> IO(Unit):
  match args:
    case Con{prog, Con{input, Con{kind, Con{dir, Nil{}}}}}:
      run(input, kind, dir, Some{VG.neg_inf()}, Some{VG.inf()})
    case Con{prog, Con{input, Con{kind, Con{dir, Con{lo, Con{hi, Nil{}}}}}}}:
      run(input, kind, dir, F32.read(lo), F32.read(hi))
    case _:
      IO.die(Unit, 2, usage())

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    start(args)
