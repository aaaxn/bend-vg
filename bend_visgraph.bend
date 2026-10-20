# ts2vg's visibility graphs of time series, in Bend2, on every CPU thread.
# Docs, tests and benchmark: https://github.com/aaaxn/bend-visgraph
#
# bend-visgraph's command line takes ts2vg's options with the input first:
#   bend_visgraph INPUT [-o OUTPUT] [-x XS] [-t TYPE] [-d DIRECTED] [-w WEIGHTED] [-p LIMIT] [-m MODE]
# where XS, which ts2vg's command line lacks, holds the x of each value.
import Base
import ./visgraph.bend as VG
import ./parallel.bend as Par
import ./src/series.bend as Series
import ./src/report.bend as Report

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
  Config{output: String, xs: String, g: VG.Visibility, dir: VG.Direction, k: VG.Weight, limit: U32, mode: Mode}
  Usage{msg: String}

type Outcome is Data:
  Ok{text: String}
  Err{msg: String}

def usage() -> String:
  "usage: bend_visgraph INPUT [-o OUTPUT] [-x XS] [-t natural|horizontal] [-d left_to_right|top_to_bottom] [-w WEIGHT] [-p LIMIT] [-m el|ds|dd|dc]"

# Option names

def flags() -> List<&2, Entry<Flag>>:
  [Entry{"-o", Output{}}, Entry{"--output", Output{}}, Entry{"-x", XFile{}}, Entry{"--xs", XFile{}}, Entry{"-t", GraphType{}}, Entry{"--type", GraphType{}},
   Entry{"-d", Directed{}}, Entry{"--directed", Directed{}}, Entry{"-w", Weighted{}}, Entry{"--weighted", Weighted{}},
   Entry{"-p", Limit{}}, Entry{"--penetrable_limit", Limit{}}, Entry{"-m", OutputMode{}}, Entry{"--outputmode", OutputMode{}}]

def graphs() -> List<&2, Entry<VG.Visibility>>:
  [Entry{"natural", VG.Natural{}}, Entry{"horizontal", VG.Horizontal{}}]

def directions() -> List<&2, Entry<VG.Direction>>:
  [Entry{"left_to_right", VG.LeftToRight{}}, Entry{"top_to_bottom", VG.TopToBottom{}}]

def weights() -> List<&2, Entry<VG.Weight>>:
  [Entry{"distance", VG.Distance{}}, Entry{"sq_distance", VG.SqDistance{}}, Entry{"v_distance", VG.VDistance{}},
   Entry{"abs_v_distance", VG.AbsVDistance{}}, Entry{"h_distance", VG.HDistance{}}, Entry{"abs_h_distance", VG.AbsHDistance{}},
   Entry{"slope", VG.Slope{}}, Entry{"abs_slope", VG.AbsSlope{}}, Entry{"angle", VG.Angle{}}, Entry{"abs_angle", VG.AbsAngle{}},
   Entry{"num_penetrations", VG.NumPenetrations{}}]

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
  Config{"", "", VG.Natural{}, VG.Undirected{}, VG.Unweighted{}, 0, EdgeList{}}

def bad(name: String, value: String) -> Config:
  Usage{"invalid value for " ++ name ++ ": " ++ value}

def with_graph(found: Maybe<&2, VG.Visibility>, name: String, value: String, o: String, x: String, d: VG.Direction, k: VG.Weight, l: U32, m: Mode) -> Config:
  match found:
    case Some{g}:
      Config{o, x, g, d, k, l, m}
    case None{}:
      bad(name, value)

def with_direction(found: Maybe<&2, VG.Direction>, name: String, value: String, o: String, x: String, g: VG.Visibility, k: VG.Weight, l: U32, m: Mode) -> Config:
  match found:
    case Some{d}:
      Config{o, x, g, d, k, l, m}
    case None{}:
      bad(name, value)

def with_weight(found: Maybe<&2, VG.Weight>, name: String, value: String, o: String, x: String, g: VG.Visibility, d: VG.Direction, l: U32, m: Mode) -> Config:
  match found:
    case Some{k}:
      Config{o, x, g, d, k, l, m}
    case None{}:
      bad(name, value)

def with_limit(found: Maybe<&2, U32>, name: String, value: String, o: String, x: String, g: VG.Visibility, d: VG.Direction, k: VG.Weight, m: Mode) -> Config:
  match found:
    case Some{l}:
      Config{o, x, g, d, k, l, m}
    case None{}:
      bad(name, value)

def with_mode(found: Maybe<&2, Mode>, name: String, value: String, o: String, x: String, g: VG.Visibility, d: VG.Direction, k: VG.Weight, l: U32) -> Config:
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
      with_graph(lookup(VG.Visibility, value, graphs()), name, value, o, x, d, k, l, m)
    case Config{o, x, g, d, k, l, m} Some{Directed{}}:
      with_direction(lookup(VG.Direction, value, directions()), name, value, o, x, g, k, l, m)
    case Config{o, x, g, d, k, l, m} Some{Weighted{}}:
      with_weight(lookup(VG.Weight, value, weights()), name, value, o, x, g, d, l, m)
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

def output(mode: Mode, +k: VG.Weight, g: VG.Graph, +n: U32) -> String:
  match mode:
    case EdgeList{}:
      Report.edge_list(Report.is_weighted(k), g)
    case DegreeSequence{}:
      Report.degree_sequence(n, Par.degrees(g))
    case DegreeDistribution{}:
      Report.degree_counts(True{}, n, Par.degrees(g))
    case DegreeCounts{}:
      Report.degree_counts(False{}, n, Par.degrees(g))

def only_degrees(mode: Mode) -> Bool:
  match mode:
    case EdgeList{}:
      False{}
    case _:
      True{}

def graph_of(+g: VG.Visibility, +dir: VG.Direction, +k: VG.Weight, +limit: U32, ys: Array<F32>, xs: VG.Xs, +n: U32) -> VG.Graph:
  Par.build(VG.Options{g, dir, k, VG.neg_inf(), VG.inf(), limit}, VG.Series{n, ys, xs})

# Where x comes from: the index, or the values of the -x file, last first.
type XSource is Data:
  ByIndex{}
  Given{rev: List<&2, F32>}

def xs_of(x: XSource, +n: U32) -> VG.Xs:
  match x:
    case ByIndex{}:
      VG.Index{}
    case Given{rev}:
      VG.At{Series.ys(rev, n)}

def report.built(weighted_degrees: Bool, +g: VG.Visibility, +dir: VG.Direction, +k: VG.Weight, +limit: U32, mode: Mode, rev: List<&2, F32>, x: XSource, +n: U32) -> Outcome:
  match weighted_degrees:
    case True{}:
      Err{"Building with 'only_degrees' is only supported for unweighted graphs."}
    case False{}:
      Ok{output(mode, k, graph_of(g, dir, k, limit, Series.ys(rev, n), xs_of(x, n), n), n)}

# x as the index is an F32, which holds every index below 2^24 exactly.
def report.sized(too_long: Bool, +g: VG.Visibility, +dir: VG.Direction, +k: VG.Weight, +limit: U32, +mode: Mode, rev: List<&2, F32>, +n: U32) -> Outcome:
  match too_long:
    case True{}:
      Err{"bend_visgraph takes at most 16777216 values, since x is the index as an F32"}
    case False{}:
      report.built(only_degrees(mode) && Report.is_weighted(k), g, dir, k, limit, mode, rev, ByIndex{}, n)

def report.xs(x: Series.XsCheck, +g: VG.Visibility, +dir: VG.Direction, +k: VG.Weight, +limit: U32, +mode: Mode, rev: List<&2, F32>, +n: U32) -> Outcome:
  match x:
    case Series.XsBad{msg}:
      Err{msg}
    case Series.XsOk{xrev}:
      report.built(only_degrees(mode) && Report.is_weighted(k), g, dir, k, limit, mode, rev, Given{xrev}, n)

# The x coordinates of the -x file, if one was given.
type XsIn is Data:
  NoXs{}
  XsRead{p: Series.Parsed}

def report(p: Series.Parsed, x: XsIn, +g: VG.Visibility, +dir: VG.Direction, +k: VG.Weight, +limit: U32, +mode: Mode) -> Outcome:
  match p x:
    case Series.Bad{line} _:
      Err{"line " ++ U32.show(line) ++ " holds no number"}
    case Series.Values{rev, +n} NoXs{}:
      report.sized(U32.is_gt(n, 16777216), g, dir, k, limit, mode, rev, n)
    case Series.Values{rev, +n} XsRead{xp}:
      report.xs(Series.xs(xp, n), g, dir, k, limit, mode, rev, n)

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
