# A time series from text with one value per line, as ts2vg's command line
# reads it. Blank lines are skipped. Each value is rounded once, from its
# decimal text to F32, and its x is its index.
import Base

type Parsed is Data:
  Values{rev: List<&2, F32>, n: U32}
  Bad{line: U32}

def add(blank: Bool, m: Maybe<&2, F32>, +line: U32, rev: List<&2, F32>, +n: U32) -> Parsed:
  match blank m:
    case True{} _:
      Values{rev, n}
    case False{} Some{v}:
      Values{v <> rev, (n + 1 : U32)}
    case False{} None{}:
      Bad{line}

def step(s: String, +line: U32, st: Parsed) -> Parsed:
  match st:
    case Values{rev, +n}:
      +t = String.trim(s)
      add(String.is_empty(t), F32.read(t), line, rev, n)
    case Bad{l}:
      Bad{l}

# Base's String.lines recurses once per character, too deep for the JS
# lane's stack, so this walks the text with tail calls. `h` is the character
# before `s`, `nl` whether it is a newline, and `cur` the line before `h`,
# last character first.
def scan(s: String, nl: Bool, +h: Char, cur: String, +line: U32, st: Parsed) -> Parsed:
  match s nl:
    case SNil{} True{}:
      step(String.reverse(cur), line, st)
    case SNil{} False{}:
      step(String.reverse(SCon{h, cur}), line, st)
    case SCon{+h2, t} True{}:
      scan(t, Char.is_eq(h2, '\n'), h2, SNil{}, (line + 1 : U32), step(String.reverse(cur), line, st))
    case SCon{+h2, t} False{}:
      scan(t, Char.is_eq(h2, '\n'), h2, SCon{h, cur}, line, st)

# The values of `text`, last first, and how many there are; or the first
# line, counted from 1, that holds no number.
def parse(text: String) -> Parsed:
  match text:
    case SNil{}:
      Values{Nil{}, 0}
    case SCon{+h, t}:
      scan(t, Char.is_eq(h, '\n'), h, SNil{}, 1, Values{Nil{}, 0})

def column(rev: List<&2, F32>, +i: U32, ys: Array<F32>) -> Array<F32>:
  match rev:
    case Nil{}:
      ys
    case Con{y, rest}:
      column(rest, (i - 1 : U32), Array.set(F32, ys, i, y))

# The `n` values `rev`, last first, as an array indexed from 0.
def ys(rev: List<&2, F32>, +n: U32) -> Array<F32>:
  column(rev, (n - 1 : U32), Array.new(F32, Nat.add(1n, U32.log2(n)), 0.0))
