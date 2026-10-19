# bend-vg's command line, which takes ts2vg's options with the input first:
#   bend_vg INPUT [-o OUTPUT] [-x XS] [-t TYPE] [-d DIRECTED] [-w WEIGHTED] [-p LIMIT] [-m MODE]
# where XS, which ts2vg's command line lacks, holds the x of each value.
import Base
import ./src/graph.bend as G
import ./src/parallel.bend as Par
import ./src/series.bend as Series
import ./src/report.bend as Report
import ./src/penetrable.bend as Penetrable

type Mode is Data:
  EdgeList{}
  DegreeSequence{}
  DegreeDistribution{}
  DegreeCounts{}

type Flag is Data:
  Output{}
  XFile{}
  GraphType{}
  Directed{}
  Weighted{}
  Limit{}
  OutputMode{}

type Entry<-A: Data> is Data:
  Entry{name: String, value: A}

type Config is Data:
  Config{output: String, xs: String, g: G.Graph, dir: G.Direction, k: G.Weight, limit: U32, mode: Mode}
  Usage{msg: String}

type Outcome is Data:
  Ok{text: String}
  Err{msg: String}

def usage() -> String:
  "usage: bend_vg INPUT [-o OUTPUT] [-x XS] [-t natural|horizontal] [-d left_to_right|top_to_bottom] [-w WEIGHT] [-p LIMIT] [-m el|ds|dd|dc]"

# Option names

def flags() -> List<&2, Entry<Flag>>:
  [Entry{"-o", Output{}}, Entry{"--output", Output{}}, Entry{"-x", XFile{}}, Entry{"--xs", XFile{}}, Entry{"-t", GraphType{}}, Entry{"--type", GraphType{}},
   Entry{"-d", Directed{}}, Entry{"--directed", Directed{}}, Entry{"-w", Weighted{}}, Entry{"--weighted", Weighted{}},
   Entry{"-p", Limit{}}, Entry{"--penetrable_limit", Limit{}}, Entry{"-m", OutputMode{}}, Entry{"--outputmode", OutputMode{}}]

def graphs() -> List<&2, Entry<G.Graph>>:
  [Entry{"natural", G.Natural{}}, Entry{"horizontal", G.Horizontal{}}]

def directions() -> List<&2, Entry<G.Direction>>:
  [Entry{"left_to_right", G.LeftToRight{}}, Entry{"top_to_bottom", G.TopToBottom{}}]

def weights() -> List<&2, Entry<G.Weight>>:
  [Entry{"distance", G.Distance{}}, Entry{"sq_distance", G.SqDistance{}}, Entry{"v_distance", G.VDistance{}},
   Entry{"abs_v_distance", G.AbsVDistance{}}, Entry{"h_distance", G.HDistance{}}, Entry{"abs_h_distance", G.AbsHDistance{}},
   Entry{"slope", G.Slope{}}, Entry{"abs_slope", G.AbsSlope{}}, Entry{"angle", G.Angle{}}, Entry{"abs_angle", G.AbsAngle{}},
   Entry{"num_penetrations", G.NumPenetrations{}}]

def modes() -> List<&2, Entry<Mode>>:
  [Entry{"el", EdgeList{}}, Entry{"ds", DegreeSequence{}}, Entry{"dd", DegreeDistribution{}}, Entry{"dc", DegreeCounts{}}]

def lookup.hit(-A: Data, hit: Bool, v: A, rest: Maybe<&2, A>) -> Maybe<&2, A>:
  match hit:
    case True{}:
      Some{v}
    case False{}:
      rest

def lookup.entry(-A: Data, +s: String, e: Entry<A>, rest: Maybe<&2, A>) -> Maybe<&2, A>:
  Entry{name, v} = e
  lookup.hit(A, String.eq(s, name), v, rest)

def lookup(-A: Data, +s: String, table: List<&2, Entry<A>>) -> Maybe<&2, A>:
  match table:
    case Nil{}:
      None{}
    case Con{e, rest}:
      lookup.entry(A, s, e, lookup(A, s, rest))

# Options

def defaults() -> Config:
  Config{"", "", G.Natural{}, G.Undirected{}, G.Unweighted{}, 0, EdgeList{}}

def bad(name: String, value: String) -> Config:
  Usage{"invalid value for " ++ name ++ ": " ++ value}

def with_graph(found: Maybe<&2, G.Graph>, name: String, value: String, o: String, x: String, d: G.Direction, k: G.Weight, l: U32, m: Mode) -> Config:
  match found:
    case Some{g}:
      Config{o, x, g, d, k, l, m}
    case None{}:
      bad(name, value)

def with_direction(found: Maybe<&2, G.Direction>, name: String, value: String, o: String, x: String, g: G.Graph, k: G.Weight, l: U32, m: Mode) -> Config:
  match found:
    case Some{d}:
      Config{o, x, g, d, k, l, m}
    case None{}:
      bad(name, value)

def with_weight(found: Maybe<&2, G.Weight>, name: String, value: String, o: String, x: String, g: G.Graph, d: G.Direction, l: U32, m: Mode) -> Config:
  match found:
    case Some{k}:
      Config{o, x, g, d, k, l, m}
    case None{}:
      bad(name, value)

def with_limit(found: Maybe<&2, U32>, name: String, value: String, o: String, x: String, g: G.Graph, d: G.Direction, k: G.Weight, m: Mode) -> Config:
  match found:
    case Some{l}:
      Config{o, x, g, d, k, l, m}
    case None{}:
      bad(name, value)

def with_mode(found: Maybe<&2, Mode>, name: String, value: String, o: String, x: String, g: G.Graph, d: G.Direction, k: G.Weight, l: U32) -> Config:
  match found:
    case Some{m}:
      Config{o, x, g, d, k, l, m}
    case None{}:
      bad(name, value)

def set(cfg: Config, flag: Maybe<&2, Flag>, +name: String, +value: String) -> Config:
  match cfg flag:
    case Usage{msg} _:
      Usage{msg}
    case Config{o, x, g, d, k, l, m} None{}:
      Usage{"unknown option: " ++ name}
    case Config{o, x, g, d, k, l, m} Some{Output{}}:
      Config{value, x, g, d, k, l, m}
    case Config{o, x, g, d, k, l, m} Some{XFile{}}:
      Config{o, value, g, d, k, l, m}
    case Config{o, x, g, d, k, l, m} Some{GraphType{}}:
      with_graph(lookup(G.Graph, value, graphs()), name, value, o, x, d, k, l, m)
    case Config{o, x, g, d, k, l, m} Some{Directed{}}:
      with_direction(lookup(G.Direction, value, directions()), name, value, o, x, g, k, l, m)
    case Config{o, x, g, d, k, l, m} Some{Weighted{}}:
      with_weight(lookup(G.Weight, value, weights()), name, value, o, x, g, d, l, m)
    case Config{o, x, g, d, k, l, m} Some{Limit{}}:
      with_limit(U32.read(value), name, value, o, x, g, d, k, m)
    case Config{o, x, g, d, k, l, m} Some{OutputMode{}}:
      with_mode(lookup(Mode, value, modes()), name, value, o, x, g, d, k, l)

def parse(opts: List<String>, cfg: Config) -> Config:
  match opts:
    case Nil{}:
      cfg
    case Con{+name, Con{value, rest}}:
      parse(rest, set(cfg, lookup(Flag, name, flags()), name, value))
    case Con{name, Nil{}}:
      Usage{"missing value for " ++ name}

# The graph and what to print of it

def output(mode: Mode, +k: G.Weight, es: G.Edges, +n: U32) -> String:
  match mode:
    case EdgeList{}:
      Report.edges_text(Report.is_weighted(k), es, "")
    case DegreeSequence{}:
      Report.degree_sequence(n, Par.degrees(es, Report.slots(n)))
    case DegreeDistribution{}:
      Report.degree_counts(True{}, n, Par.degrees(es, Report.slots(n)))
    case DegreeCounts{}:
      Report.degree_counts(False{}, n, Par.degrees(es, Report.slots(n)))

def only_degrees(mode: Mode) -> Bool:
  match mode:
    case EdgeList{}:
      False{}
    case _:
      True{}

def graph_of(penetrable: Bool, +g: G.Graph, +dir: G.Direction, +k: G.Weight, +limit: U32, ys: Array<F32>, xs: G.Xs, +n: U32) -> G.Edges:
  match penetrable:
    case True{}:
      Penetrable.build(g, dir, k, G.neg_inf(), G.inf(), limit, ys, xs, n)
    case False{}:
      Par.build(g, dir, k, G.neg_inf(), G.inf(), ys, xs, n)

# Where x comes from: the index, or the values of the -x file, last first.
type XSource is Data:
  ByIndex{}
  Given{rev: List<&2, F32>}

def xs_of(x: XSource, +n: U32) -> G.Xs:
  match x:
    case ByIndex{}:
      G.Index{}
    case Given{rev}:
      G.At{Series.ys(rev, n)}

def report.built(weighted_degrees: Bool, +g: G.Graph, +dir: G.Direction, +k: G.Weight, +limit: U32, mode: Mode, rev: List<&2, F32>, x: XSource, +n: U32) -> Outcome:
  match weighted_degrees:
    case True{}:
      Err{"Building with 'only_degrees' is only supported for unweighted graphs."}
    case False{}:
      Ok{output(mode, k, graph_of(Bool.not(U32.is_zero(limit)), g, dir, k, limit, Series.ys(rev, n), xs_of(x, n), n), n)}

# x as the index is an F32, which holds every index below 2^24 exactly.
def report.sized(too_long: Bool, +g: G.Graph, +dir: G.Direction, +k: G.Weight, +limit: U32, +mode: Mode, rev: List<&2, F32>, +n: U32) -> Outcome:
  match too_long:
    case True{}:
      Err{"bend_vg takes at most 16777216 values, since x is the index as an F32"}
    case False{}:
      report.built(only_degrees(mode) && Report.is_weighted(k), g, dir, k, limit, mode, rev, ByIndex{}, n)

# Whether each value of `rest`, last first, is below `a`, as ts2vg checks
# that x increases.
def increasing(rest: List<&2, F32>, +a: F32, ok: Bool) -> Bool:
  match rest:
    case Nil{}:
      ok
    case Con{+b, t}:
      increasing(t, b, ok && Bool.not(F32.is_le(F32.sub(a, b), 0.0)))

def increases(xrev: List<&2, F32>) -> Bool:
  match xrev:
    case Nil{}:
      True{}
    case Con{+a, t}:
      increasing(t, a, True{})

def report.xs(same: Bool, up: Bool, +g: G.Graph, +dir: G.Direction, +k: G.Weight, +limit: U32, +mode: Mode, rev: List<&2, F32>, xrev: List<&2, F32>, +n: U32, +m: U32) -> Outcome:
  match same up:
    case False{} _:
      Err{"the x coordinates hold " ++ U32.show(m) ++ " values and the series " ++ U32.show(n)}
    case True{} False{}:
      Err{"the x coordinates must increase"}
    case True{} True{}:
      report.built(only_degrees(mode) && Report.is_weighted(k), g, dir, k, limit, mode, rev, Given{xrev}, n)

# The x coordinates of the -x file, if one was given.
type XsIn is Data:
  NoXs{}
  XsRead{p: Series.Parsed}

def report(p: Series.Parsed, x: XsIn, +g: G.Graph, +dir: G.Direction, +k: G.Weight, +limit: U32, +mode: Mode) -> Outcome:
  match p x:
    case Series.Bad{line} _:
      Err{"line " ++ U32.show(line) ++ " holds no number"}
    case Series.Values{rev, +n} NoXs{}:
      report.sized(U32.is_gt(n, 16777216), g, dir, k, limit, mode, rev, n)
    case Series.Values{rev, n} XsRead{Series.Bad{line}}:
      Err{"line " ++ U32.show(line) ++ " of the x coordinates holds no number"}
    case Series.Values{rev, +n} XsRead{Series.Values{+xrev, +m}}:
      report.xs(U32.is_eq(n, m), increases(xrev), g, dir, k, limit, mode, rev, xrev, n, m)

# Files

def write_text.done(m: File & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  (f, r) = m
  do IO<Unit>:
    done : Unit <- IO.pass(Unit, r)
    File.close(f)

def write_text(path: String, text: String) -> IO(Unit):
  do IO<Unit>:
    f : File <- IO.try(File, File.open(path, "w"))
    m : File & Result<&1, &1, U32 & String, Unit> <- File.write(f, text)
    write_text.done(m)

def emit.to(stdout: Bool, path: String, text: String) -> IO(Unit):
  match stdout:
    case True{}:
      IO.write(text)
    case False{}:
      write_text(path, text)

def emit(+path: String, outcome: Outcome) -> IO(Unit):
  match outcome:
    case Ok{text}:
      emit.to(String.is_empty(path), path, text)
    case Err{msg}:
      IO.die(Unit, 1, msg)

def read_xs(none: Bool, path: String) -> IO(XsIn):
  match none:
    case True{}:
      IO.pure(XsIn, NoXs{})
    case False{}:
      do IO<XsIn>:
        text : String <- Series.read_text(path)
        return XsRead{Series.parse(text)}

def run(input: String, cfg: Config) -> IO(Unit):
  match cfg:
    case Usage{msg}:
      IO.die(Unit, 2, msg ++ "\n" ++ usage())
    case Config{+out, +xpath, g, dir, k, limit, mode}:
      do IO<Unit>:
        text : String <- Series.read_text(input)
        x : XsIn <- read_xs(String.is_empty(xpath), xpath)
        emit(out, report(Series.parse(text), x, g, dir, k, limit, mode))

def start(args: List<String>) -> IO(Unit):
  match args:
    case Con{prog, Con{input, opts}}:
      run(input, parse(opts, defaults()))
    case _:
      IO.die(Unit, 2, usage())

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    start(args)
