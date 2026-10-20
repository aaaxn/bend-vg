# Times the graphs of many short series, as a sliding-window study builds
# them: the series cut into windows of `w` values, one graph per window,
# each with its edges and degrees, as ts2vg's `build` makes them.
#   windows INPUT natural|horizontal W copy|one|par|split
# prints `windows edges checksum ms`. `copy` only cuts the windows and sums
# their values. `one` builds each window's graph with VG.build and `par` with
# Par.build, one window after another. `split` builds them with VG.build,
# with the windows split among the threads. The checksum, the sum of every
# edge's ends and every degree, is bench.bend's, over every window's graph.
import Base
import ../visgraph.bend as VG
import ../parallel.bend as Par
import ../src/series.bend as Series
import ./bench.bend as B

def tally(t: B.Tally, +s: U32, +d: U32) -> B.Tally:
  B.Tally{m, sum} = t
  B.Tally{(m + 1 : U32), (sum + s + d : U32)}

# The tally `t` with the edges of `g` and its `w` degrees `ds`.
def counted(+w: U32, +g: VG.Graph, ds: Array<U32>, t: B.Tally) -> B.Tally:
  B.add_degrees(VG.fold(~B.Tally, ~(acc => +s => +d => x => tally(acc, s, d)), g, t), B.degree_sum(U32.to_nat(w), 0, Array.get(U32, ds, 0), 0))

def one(+w: U32, +g: VG.Graph, t: B.Tally) -> B.Tally:
  counted(w, g, VG.degrees(g), t)

def every(+w: U32, +g: VG.Graph, t: B.Tally) -> B.Tally:
  counted(w, g, Par.degrees(g), t)

type Mode is Data:
  Copy{}
  OneThread{}
  EveryThread{}
  Spread{}

# The `count` values of `src` from `i` on, into `dst` from `j` on.
def cut(count: Nat, +i: U32, r: Array<F32> & F32, +j: U32, dst: Array<F32>) -> Array<F32> & Array<F32>:
  match count:
    case 0n:
      (src, v) = r
      (src, dst)
    case 1n+c:
      (src, v) = r
      cut(c, (i + 1 : U32), Array.get(F32, src, (i + 1 : U32)), (j + 1 : U32), Array.set(F32, dst, j, v))

def window(+w: U32, +start: U32, src: Array<F32>) -> Array<F32> & Array<F32>:
  cut(U32.to_nat(w), start, Array.get(F32, src, start), 0, Array.new(F32, Nat.add(1n, U32.log2(w)), 0.0))

# The window in `r` and the `k` after it, last first onto `acc`.
def windows(k: Nat, +w: U32, +start: U32, r: Array<F32> & Array<F32>, acc: List<Array<F32>>) -> List<Array<F32>>:
  match k:
    case 0n:
      (src, a) = r
      a <> acc
    case 1n+c:
      (src, a) = r
      windows(c, w, (start + w : U32), window(w, (start + w : U32), src), a <> acc)

# The sum of the `count` values of an array from `i` on.
def total(count: Nat, +i: U32, r: Array<F32> & F32, +acc: F32) -> F32:
  match count:
    case 0n:
      (a, v) = r
      acc
    case 1n+c:
      (a, v) = r
      total(c, (i + 1 : U32), Array.get(F32, a, (i + 1 : U32)), F32.add(acc, v))

def summed(t: B.Tally, +v: F32) -> B.Tally:
  B.Tally{m, sum} = t
  B.Tally{m, (sum + F32.to_u32(F32.abs(v)) : U32)}

def built(mode: Mode, +g: VG.Visibility, +w: U32, a: Array<F32>, t: B.Tally) -> B.Tally:
  match mode:
    case Copy{}:
      summed(t, total(U32.to_nat(w), 0, Array.get(F32, a, 0), 0.0))
    case EveryThread{}:
      every(w, Par.build(VG.options(g), VG.Series{w, a, VG.Index{}}), t)
    case _:
      one(w, VG.build(VG.options(g), VG.Series{w, a, VG.Index{}}), t)

def run(ws: List<Array<F32>>, +mode: Mode, +g: VG.Visibility, +w: U32, t: B.Tally) -> B.Tally:
  match ws:
    case Nil{}:
      t
    case Con{a, next}:
      run(next, mode, g, w, built(mode, g, w, a, t))

type Halves is Type:
  Halves{f: List<Array<F32>>, b: List<Array<F32>>}

# The windows `ws` dealt in turn onto `f` and `b`.
def deal(ws: List<Array<F32>>, f: List<Array<F32>>, b: List<Array<F32>>) -> Halves:
  match ws:
    case Con{x, Con{y, rest}}:
      deal(rest, x <> f, y <> b)
    case Con{x, Nil{}}:
      Halves{x <> f, b}
    case Nil{}:
      Halves{f, b}

# The windows dealt in halves `depth` times, each half on its own task.
def tree(depth: Nat, hs: Halves, +g: VG.Visibility, +w: U32) -> B.Tally:
  match depth hs:
    case 0n Halves{f, b}:
      run(b, OneThread{}, g, w, run(f, OneThread{}, g, w, B.Tally{0, 0}))
    case 1n++d Halves{f, b}:
      x y = tree(d, deal(f, Nil{}, Nil{}), g, w) tree(d, deal(b, Nil{}, Nil{}), g, w)
      B.both(x, y)

def graphs(mode: Mode, +g: VG.Visibility, +w: U32, ws: List<Array<F32>>) -> B.Tally:
  match mode:
    case Spread{}:
      tree(Par.fork_depth(), deal(ws, Nil{}, Nil{}), g, w)
    case _:
      run(ws, mode, g, w, B.Tally{0, 0})

def report(+count: U32, +t0: Nat, done: B.Tally & Nat) -> IO(Unit):
  (t, t1) = done
  match t:
    case B.Tally{m, sum}:
      IO.print(U32.show(count) ++ " " ++ U32.show(m) ++ " " ++ U32.show(sum) ++ " " ++ Nat.show(Nat.sub(t1, t0)))

def from_values(+g: VG.Visibility, +w: U32, +mode: Mode, +count: U32, ys: Array<F32>) -> IO(Unit):
  do IO<Unit>:
    t0 : Nat <- IO.now()
    done : B.Tally & Nat <- B.stamp(graphs(mode, g, w, windows(U32.to_nat((count - 1 : U32)), w, 0, window(w, 0, ys), Nil{})))
    report(count, t0, done)

def sized(fits: Bool, +g: VG.Visibility, +w: U32, +mode: Mode, rev: List<&2, F32>, +n: U32) -> IO(Unit):
  match fits:
    case True{}:
      from_values(g, w, mode, (n / w : U32), Series.ys(rev, n))
    case False{}:
      IO.die(Unit, 1, "W must be at least 1 and at most the number of values")

def timed(+g: VG.Visibility, +w: U32, +mode: Mode, p: Series.Parsed) -> IO(Unit):
  match p:
    case Series.Bad{line}:
      IO.die(Unit, 1, "line " ++ U32.show(line) ++ " holds no number")
    case Series.Values{rev, +n}:
      sized(Bool.not(U32.is_zero(w)) && Bool.not(U32.is_lt(n, w)), g, w, mode, rev, n)

def usage() -> String:
  "usage: windows INPUT natural|horizontal W copy|one|par|split"

def mode_of(copy: Bool, one: Bool, par: Bool, split: Bool) -> Maybe<&2, Mode>:
  match copy one par split:
    case True{} _ _ _:
      Some{Copy{}}
    case False{} True{} _ _:
      Some{OneThread{}}
    case False{} False{} True{} _:
      Some{EveryThread{}}
    case False{} False{} False{} True{}:
      Some{Spread{}}
    case False{} False{} False{} False{}:
      None{}

def mode_named(+mode: String) -> Maybe<&2, Mode>:
  mode_of(String.eq(mode, "copy"), String.eq(mode, "one"), String.eq(mode, "par"), String.eq(mode, "split"))

def checked(g: Maybe<&2, VG.Visibility>, w: Maybe<&2, U32>, mode: Maybe<&2, Mode>, input: String) -> IO(Unit):
  match g w mode:
    case Some{+k} Some{+size} Some{+m}:
      do IO<Unit>:
        text : String <- Series.read_text(input)
        timed(k, size, m, Series.parse(text))
    case _ _ _:
      IO.die(Unit, 2, usage())

def start(args: List<String>) -> IO(Unit):
  match args:
    case Con{prog, Con{input, Con{kind, Con{w, Con{mode, Nil{}}}}}}:
      checked(B.graph_named(kind), U32.read(w), mode_named(mode), input)
    case _:
      IO.die(Unit, 2, usage())

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    start(args)
