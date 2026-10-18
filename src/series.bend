# A time series from text with one value per line, as ts2vg's command line
# reads it. Blank lines are skipped. Each value is rounded once, from its
# decimal text to F32, and its x is its index.
import Base
import ./graph.bend as G

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

def values(lines: List<&2, String>, +line: U32, st: Parsed) -> Parsed:
  match lines:
    case Nil{}:
      st
    case Con{s, rest}:
      values(rest, (line + 1 : U32), step(s, line, st))

# The values of `text`, last first, and how many there are; or the first
# line, counted from 1, that holds no number.
def parse(text: String) -> Parsed:
  values(String.lines(text), 1, Values{Nil{}, 0})

# The points of the values `rev`, last first, whose last index is `i`.
def points(rev: List<&2, F32>, +i: U32, acc: G.Pts) -> G.Pts:
  match rev:
    case Nil{}:
      acc
    case Con{y, rest}:
      points(rest, (i - 1 : U32), G.PCon{i, U32.to_f32(i), y, acc})
