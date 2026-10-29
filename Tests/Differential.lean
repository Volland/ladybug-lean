import Tests.Framework
import Tests.Fixtures

/-!
# Differential tests: in-memory backend versus Ladybug

A seeded generator builds small graphs over the test schema and well-typed
queries from builder combinators. Each case runs on both backends; results are
compared as multisets of normalized rows (as sequences when the query orders
by a total key). A disagreement is shrunk by removing nodes and relationships,
then reported with the graph, the query text and both results.
-/

namespace Tests.Differential

open Ladybug Tests.Fixtures

/-! ## Random generation -/

abbrev Gen := StateM StdGen

def nat (lo hi : Nat) : Gen Nat := modifyGet fun g => randNat g lo hi

def pick {α : Type} [Inhabited α] (xs : Array α) : Gen α := do return xs[← nat 0 (xs.size - 1)]!

def chance (percent : Nat) : Gen Bool := return (← nat 1 100) ≤ percent

structure TestGraph where
  persons : Array Person
  companies : Array Company
  works : Array (Int64 × WorksAt × String)
  knows : Array (Int64 × Int64)

def TestGraph.describe (g : TestGraph) : String :=
  let ps := g.persons.toList.map fun p => s!"{p.id}:{p.name}:{p.age}"
  let cs := g.companies.toList.map (·.name)
  let ws := g.works.toList.map fun (p, w, c) => s!"{p}-{w.since}->{c}"
  let ks := g.knows.toList.map fun (a, b) => s!"{a}->{b}"
  s!"persons {ps}\n    companies {cs}\n    works {ws}\n    knows {ks}"

def names : Array String := #["a", "b", "ab", "ba", "c", "abc"]

def genGraph : Gen TestGraph := do
  let np ← nat 0 7
  let persons ← (Array.range np).mapM fun i => do
    let age ← if ← chance 30 then pure none else some <$> (Int64.ofNat <$> nat 10 60)
    return Person.mk (Int64.ofNat (i + 1)) (← pick names) age
  let nc ← nat 0 3
  let companies := (Array.range nc).map fun i => Company.mk s!"c{i}" (Int32.ofNat (1900 + i * 10))
  let mut works := #[]
  let mut knows := #[]
  if !persons.isEmpty && !companies.isEmpty then
    for _ in [0:← nat 0 6] do
      works := works.push ((← pick persons).id, WorksAt.mk (Int64.ofNat (← nat 2000 2005)), (← pick companies).name)
  if !persons.isEmpty then
    for _ in [0:← nat 0 8] do
      knows := knows.push ((← pick persons).id, (← pick persons).id)
  return { persons, companies, works, knows }

/-- Load a graph through the repository API, on any backend. -/
def load {m : Type → Type} [MonadGraph m] (g : TestGraph) : m Unit := do
  applySchema schema
  for p in g.persons do Repo.insert p
  for c in g.companies do Repo.insert c
  for (p, w, c) in g.works do Repo.link p w c
  for (a, b) in g.knows do Repo.link a Knows.mk b

/-- A query whose rows are compared as raw rows. -/
structure TestQuery where
  query : Query Row
  /-- Whether rows come in a total order, so sequences must match. -/
  ordered : Bool := false

def rowsOf {α : Type} (q : Query α) (ordered := false) : TestQuery := ⟨⟨q.core, fun r => .ok r⟩, ordered⟩

def genPred (p : Person.Var) : Gen (Expr (Option Bool)) := do
  let k : Int64 := Int64.ofNat (← nat 10 60)
  let atom : Gen (Expr (Option Bool)) := do
    match ← nat 0 8 with
    | 0 => return p.age >. lit k
    | 1 => return p.age <=. lit k
    | 2 => return p.name ==. lit (← pick names)
    | 3 => return isNull p.age
    | 4 => return isNotNull p.age
    | 5 => return Expr.isIn p.id (Expr.list [lit (Int64.ofNat (← nat 1 4)), lit (Int64.ofNat (← nat 3 8))])
    | 6 => return Expr.startsWith p.name (lit (← pick #["a", "b"]))
    | 7 => return coalesce p.age 0 >. lit k
    | _ => return p.age !=. lit k
  match ← nat 0 4 with
  | 0 => return (← atom) &&. (← atom)
  | 1 => return (← atom) ||. (← atom)
  | 2 => return Expr.not (← atom)
  | _ => atom

def genQuery : Gen TestQuery := do
  match ← nat 0 13 with
  | 0 =>
    let pick ← nat 0 1000
    return rowsOf <| query do
      let p ← match_ (node Person)
      where_ ((genPred p).run' (mkStdGen pick))
      return_ (p.id, p.name, p.age)
  | 1 => return rowsOf <| query do
      let p ← match_ (node Person)
      let (w, c) ← match_ (out p WorksAt (node Company))
      return_ (p.id, c.name, w.since)
  | 2 => return rowsOf <| query do
      let p ← match_ (node Person)
      let (_, c) ← optMatch (out p WorksAt (node Company))
      return_ (p.id, c.name)
  | 3 =>
    let employees : QueryM (Person.Var × Company.Var) := do
      let p ← match_ (node Person)
      let (_, c) ← match_ (out p WorksAt (node Company))
      return (p, c)
    match ← nat 0 5 with
    | 0 => return rowsOf <| query do let (p, c) ← employees; return_ (c.name, Expr.count p.id)
    | 1 => return rowsOf <| query do let (p, c) ← employees; return_ (c.name, Expr.sum p.age)
    | 2 => return rowsOf <| query do let (p, c) ← employees; return_ (c.name, Expr.max p.age)
    | 3 => return rowsOf <| query do let (p, c) ← employees; return_ (c.name, Expr.min p.name)
    | 4 => return rowsOf <| query do let (p, c) ← employees; return_ (c.name, Expr.avg p.age)
    | _ => return rowsOf <| query do let (p, c) ← employees; return_ (c.name, Expr.collect p.age)
  | 4 =>
    let s ← nat 0 2
    let l ← nat 1 4
    return rowsOf (ordered := true) <| query do
      let p ← match_ (node Person)
      orderBy p.age
      orderBy p.id
      skip s
      limit l
      return_ (p.id, p.age)
  | 5 =>
    let lo ← nat 1 2
    let hi ← nat lo 3
    let start := Int64.ofNat (← nat 1 4)
    return rowsOf <| query do
      let a ← match_ (node Person)
      let (_, b) ← matchPaths a Knows (node Person) (min := lo) (max := hi)
      where_ (a.id ==. lit start)
      return_ b.id
  | 6 => return rowsOf <| query do
      let a ← match_ (node Person)
      let (path, b) ← shortestPath a Knows (node Person) (max := 4)
      return_ (a.id, b.id, pathLength path)
  | 7 => return rowsOf <| query do
      let p ← match_ (node Person)
      where_ (← exists_ (discard (match_ (out p WorksAt (node Company)))))
      return_ p.id
  | 8 => return rowsOf <| query do
      let p ← match_ (node Person)
      let n ← countSub (discard (match_ (out p Knows (node Person))))
      return_ (p.id, n)
  | 9 =>
    let all ← chance 50
    let left : Query String := query do
      let p ← match_ (node Person)
      return_ p.name
    let right : Query String := query do
      let c ← match_ (node Company)
      return_ c.name
    return rowsOf (if all then left.unionAll right else left.union right)
  | 10 => return rowsOf <| query do
      let p ← match_ (node Person)
      let (_, c) ← match_ (out p WorksAt (node Company))
      let (n, k) ← with_ (c.name, Expr.count p.id)
      where_ (k >. 1)
      return_ (n, k)
  | 11 => return rowsOf <| query do
      let p ← match_ (node Person)
      return_ (p.id, p.age +. 1, p.age *. 2, p.name ++. lit "!")
  | 12 => return rowsOf <| query do
      let p ← match_ (node Person)
      return_ p.age (distinct := true)
  | _ => return rowsOf <| query do
      let a ← match_ (node Person)
      let (_, b) ← match_ (both a Knows (node Person))
      return_ (a.id, b.id)

/-! ## Normalization and comparison -/

/-- Comparable form of a value: integers of any width as one kind, floats
rounded, nodes and relationships as their properties, lists sorted. -/
partial def normalize : Value → Value
  | .int8 v => .int128 v.toInt | .int16 v => .int128 v.toInt | .int32 v => .int128 v.toInt
  | .int64 v => .int128 v.toInt | .uint8 v => .int128 v.toNat | .uint16 v => .int128 v.toNat
  | .uint32 v => .int128 v.toNat | .uint64 v => .int128 v.toNat
  | .float f => .double ((f.toFloat * 1e4).round / 1e4)
  | .double d => .double ((d * 1e4).round / 1e4)
  | .node _ l ps => .struct (#[("_label", .string l)] ++ ps.map fun (k, v) => (k, normalize v))
  | .rel _ _ _ l ps => .struct (#[("_label", .string l)] ++ ps.map fun (k, v) => (k, normalize v))
  | .list xs => .list ((xs.map normalize).qsort fun a b => toString a < toString b)
  | .path ns rs => .struct #[("nodes", .array (ns.map normalize)), ("rels", .array (rs.map normalize))]
  | .struct fs => .struct (fs.map fun (k, v) => (k, normalize v))
  | v => v

def normRows (rows : Array Row) (ordered : Bool) : Array String :=
  let rs := rows.map fun r => toString (r.values.map normalize).toList
  if ordered then rs else rs.qsort (· < ·)

inductive Outcome where
  | rows (rs : Array String)
  | failed (e : Error)

instance : ToString Outcome where
  toString
    | .rows rs => s!"{rs.toList}"
    | .failed e => s!"error: {e}"

def Outcome.agrees : Outcome → Outcome → Bool
  | .rows a, .rows b => a == b
  | .failed _, .failed _ => true
  | _, _ => false

def runNative (g : TestGraph) (q : TestQuery) : IO Outcome := do
  let r ← (do (← Database.open ":memory:").withConnection do load g; runQuery q.query).run
  return match r with
    | .ok rows => .rows (normRows rows q.ordered)
    | .error e => .failed e

def runMem (g : TestGraph) (q : TestQuery) (faults : Mem.Faults) : Outcome :=
  match (do load g; runQuery q.query : MemM (Array Row)).run' {} faults with
  | .ok rows => .rows (normRows rows q.ordered)
  | .error e => .failed e

structure Counterexample where
  graph : TestGraph
  text : String
  native : Outcome
  memory : Outcome

def Counterexample.report (c : Counterexample) : String :=
  s!"counterexample\n  graph:\n    {c.graph.describe}\n  query: {c.text}\n  ladybug: {c.native}\n  memory:  {c.memory}"

/-- Remove nodes and relationships while the disagreement persists. -/
partial def shrink (g : TestGraph) (q : TestQuery) (faults : Mem.Faults) : IO TestGraph := do
  let disagrees (g : TestGraph) : IO Bool := do return !(← runNative g q).agrees (runMem g q faults)
  let candidates : List TestGraph :=
    (List.range g.knows.size).map (fun i => { g with knows := g.knows.eraseIdx! i }) ++
    (List.range g.works.size).map (fun i => { g with works := g.works.eraseIdx! i }) ++
    (List.range g.persons.size).map fun i =>
      let id := g.persons[i]!.id
      { g with persons := g.persons.eraseIdx! i, works := g.works.filter (·.1 != id),
               knows := g.knows.filter fun (a, b) => a != id && b != id }
  for c in candidates do
    if ← disagrees c then return ← shrink c q faults
  return g

-- @tg: implements:: [[openspec:memory-backend#Differential conformance]]
/-- Run `n` generated cases from `seed`; the first counterexample, shrunk, if any. -/
def runSuite (n seed : Nat) (faults : Mem.Faults := {}) : IO (Option Counterexample) := do
  let mut gen := mkStdGen seed
  for _ in [0:n] do
    let ((g, q), gen') := (do return (← genGraph, ← genQuery) : Gen _).run gen
    gen := gen'
    let native ← runNative g q
    let memory := runMem g q faults
    unless native.agrees memory do
      let g ← shrink g q faults
      return some ⟨g, q.query.text, ← runNative g q, runMem g q faults⟩
  return none

def cases : IO Nat := do
  return ((← IO.getEnv "DIFF_CASES").bind String.toNat?).getD 500

-- @tg: verifies:: [[openspec:memory-backend#Differential conformance#Differential run passes]] {level: integration}
def differentialRunPasses : IO Unit := do
  let n ← cases
  match ← runSuite n 42 with
  | none => pure ()
  | some c => fail c.report

-- @tg: verifies:: [[openspec:memory-backend#Differential conformance#Disagreement is reported]] {level: integration}
def disagreementReported : IO Unit := do
  match ← runSuite 200 7 { nullCompareTrue := true } with
  | none => fail "a broken evaluator passed the differential suite"
  | some c =>
    let report := c.report
    for part in ["graph:", "query:", "ladybug:", "memory:"] do
      check ((report.splitOn part).length > 1) s!"report lacks {part}:\n{report}"

def tests : List Test := [
  ⟨"memory-backend: differential run passes", differentialRunPasses⟩,
  ⟨"memory-backend: disagreement is reported", disagreementReported⟩
]

end Tests.Differential
