# The edge list of a series on one thread, from the modules that do not rely
# on Base's @unsafe, so `bend --check-only` passes on this file:
#   one_thread INPUT natural|horizontal [LIMIT [XS]]
import Base
import ../src/graph.bend as G
import ../src/series.bend as Series
import ../src/report.bend as Report
import ../src/penetrable.bend as P

def graph_of(horizontal: Bool) -> G.Graph:
  match horizontal:
    case True{}:
      G.Horizontal{}
    case False{}:
      G.Natural{}

def built(penetrable: Bool, +g: G.Graph, +limit: U32, ys: Array<F32>, xs: G.Xs, +n: U32) -> G.Edges:
  match penetrable:
    case True{}:
      P.build(g, G.Undirected{}, G.Unweighted{}, G.neg_inf(), G.inf(), limit, ys, xs, n)
    case False{}:
      G.build(g, G.Undirected{}, G.Unweighted{}, G.neg_inf(), G.inf(), ys, xs, n)

# The x of each value: the index, or the values of XS, which must increase.
def xs_of(x: Maybe<&2, Series.Parsed>, +n: U32) -> G.Xs:
  match x:
    case Some{Series.Values{rev, m}}:
      G.At{Series.ys(rev, n)}
    case _:
      G.Index{}

def edges(+g: G.Graph, +limit: U32, p: Series.Parsed, x: Maybe<&2, Series.Parsed>) -> IO(Unit):
  match p:
    case Series.Bad{line}:
      IO.die(Unit, 1, "line " ++ U32.show(line) ++ " holds no number")
    case Series.Values{rev, +n}:
      IO.write(Report.edges_text(False{}, built(Bool.not(U32.is_zero(limit)), g, limit, Series.ys(rev, n), xs_of(x, n), n), ""))

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
