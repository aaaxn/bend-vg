# The edge list of a series on one thread, from the modules that do not rely
# on Base's @unsafe, so `bend --check-only` passes on this file:
#   one_thread INPUT natural|horizontal [LIMIT [XS]]
import Base
import ../visgraph.bend as VG
import ../src/series.bend as Series
import ../src/report.bend as Report

def graph_of(horizontal: Bool) -> VG.Visibility:
  match horizontal:
    case True{}:
      VG.Horizontal{}
    case False{}:
      VG.Natural{}

# The x of each value: the index, or the values of XS, which must increase.
def xs_of(x: Maybe<&2, Series.Parsed>, +n: U32) -> VG.Xs:
  match x:
    case Some{Series.Values{rev, m}}:
      VG.At{Series.ys(rev, n)}
    case _:
      VG.Index{}

def edges(+g: VG.Visibility, +limit: U32, p: Series.Parsed, x: Maybe<&2, Series.Parsed>) -> IO(Unit):
  match p:
    case Series.Bad{line}:
      IO.die(Unit, 1, "line " ++ U32.show(line) ++ " holds no number")
    case Series.Values{rev, +n}:
      IO.write(Report.edge_list(False{}, VG.build(VG.Options{g, VG.Undirected{}, VG.Unweighted{}, VG.neg_inf(), VG.inf(), limit}, VG.Series{n, Series.ys(rev, n), xs_of(x, n)})))

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
        edges(graph_of(String.eq(kind, "horizontal")), 0, Series.parse(text), None{})
    case Con{prog, Con{input, Con{+kind, Con{limit, Nil{}}}}}:
      do IO<Unit>:
        text : String <- Series.read_text(input)
        edges(graph_of(String.eq(kind, "horizontal")), limit_of(U32.read(limit)), Series.parse(text), None{})
    case Con{prog, Con{input, Con{+kind, Con{limit, Con{xs, Nil{}}}}}}:
      do IO<Unit>:
        text : String <- Series.read_text(input)
        xtext : String <- Series.read_text(xs)
        edges(graph_of(String.eq(kind, "horizontal")), limit_of(U32.read(limit)), Series.parse(text), Some{Series.parse(xtext)})
    case _:
      IO.die(Unit, 2, "usage: one_thread INPUT natural|horizontal [LIMIT [XS]]")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    start(args)
