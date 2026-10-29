import Ladybug.Cypher.Builder

/-!
# Paths, subqueries and unions

```lean
-- persons reachable from p in one or two Knows hops, with the paths
let (path, q) ← matchPaths p Knows (node Person) (max := 2)
-- persons with an employer
where_ (← exists_ do discard (match_ (out p WorksAt (node Company))))
-- the names of persons and companies
(personNames.union companyNames)
```
-/

namespace Ladybug

open Cypher

variable {α N R S T V O σ τ : Type}

/-! ## Paths -/

/-- A path of nodes `N` joined by relationships `R`, endpoints included. -/
structure Path (N R : Type) where
  nodes : Array N
  rels : Array R
  deriving Repr, BEq

instance [FromValue N] [FromValue R] : FromValue (Path N R) where
  typeName := s!"Path {FromValue.typeName N} {FromValue.typeName R}"
  fromValue?
    | .path ns rs => return ⟨← ns.mapM fromValue?, ← rs.mapM fromValue?⟩
    | _ => none

/-- The number of relationships on a path. -/
def pathLength (p : Expr (Path N R)) : Expr Int64 := ⟨.call "length" [p.raw] false⟩
def pathNodes (p : Expr (Path N R)) : Expr (Array N) := ⟨.call "nodes" [p.raw] false⟩
def pathRels (p : Expr (Path N R)) : Expr (Array R) := ⟨.call "rels" [p.raw] false⟩

private def matchPathWith (mode : Core.PathMode) (src : S) (ρ : Type) (dst : T) (min max : Nat) (dir : Core.Dir)
    [NodeVarOf S σ] [RelTable ρ σ σ] [PatEnd T σ V O] : QueryM (Expr (Path σ ρ) × V) := do
  let pv ← QueryM.fresh "p"
  let r ← QueryM.fresh "r"
  let (np, v, _) ← PatEnd.bind dst
  QueryM.emit (.matchPath false pv ⟨NodeVarOf.varName src, none, []⟩ ⟨some r, RelTable.label ρ, dir, []⟩ min max mode np)
  return (⟨.var pv⟩, v)

-- @tg: implements:: [[openspec:cypher-query#Variable-length paths]]
/-- `MATCH p = (src)-[:ρ*min..max]->(dst)`: every path of `min` to `max`
relationships of a table from a node table to itself. `max` has no default, so
an unbounded pattern cannot be written. Returns the path and the end node. -/
def matchPaths (src : S) (ρ : Type) (dst : T) (min : Nat := 1) (max : Nat) (dir : Core.Dir := .out)
    [NodeVarOf S σ] [RelTable ρ σ σ] [PatEnd T σ V O] : QueryM (Expr (Path σ ρ) × V) :=
  matchPathWith .all src ρ dst min max dir

-- @tg: implements:: [[openspec:cypher-query#Shortest paths]]
/-- One shortest path of at most `max` relationships. -/
def shortestPath (src : S) (ρ : Type) (dst : T) (max : Nat) (dir : Core.Dir := .out)
    [NodeVarOf S σ] [RelTable ρ σ σ] [PatEnd T σ V O] : QueryM (Expr (Path σ ρ) × V) :=
  matchPathWith .shortest src ρ dst 1 max dir

/-- Every shortest path of at most `max` relationships. -/
def allShortestPaths (src : S) (ρ : Type) (dst : T) (max : Nat) (dir : Core.Dir := .out)
    [NodeVarOf S σ] [RelTable ρ σ σ] [PatEnd T σ V O] : QueryM (Expr (Path σ ρ) × V) :=
  matchPathWith .allShortest src ρ dst 1 max dir

/-! ## Subqueries -/

/-- Run `body` as a nested pattern scope: variable names stay unique with the
outer query, and only its MATCH and WHERE clauses are kept. -/
private def nested (body : QueryM Unit) : QueryM (List Core.Pattern × Option Core.Expr) := do
  let saved := (← get).clauses
  modify fun s => { s with clauses := #[] }
  body
  let inner := (← get).clauses
  modify fun s => { s with clauses := saved }
  let pats := inner.toList.flatMap fun | .match _ ps => ps | _ => []
  let cond := inner.toList.foldl (init := none) fun acc c => match c, acc with
    | .where e, none => some e
    | .where e, some a => some (.binop .and a e)
    | _, acc => acc
  return (pats, cond)

-- @tg: implements:: [[openspec:cypher-query#Subqueries]]
/-- `EXISTS { MATCH … WHERE … }`; the body may use the outer variables. -/
def exists_ (body : QueryM Unit) : QueryM (Expr Bool) := do
  let (ps, c) ← nested body
  return ⟨.exists ps c⟩

/-- `COUNT { MATCH … WHERE … }`; the body may use the outer variables. -/
def countSub (body : QueryM Unit) : QueryM (Expr Int64) := do
  let (ps, c) ← nested body
  return ⟨.countSub ps c⟩

/-! ## Unions -/

/-- Name every returned column `c0, c1, …`, since UNION needs equal column names. -/
private def aliasReturns (cs : Array Core.Clause) : Array Core.Clause := cs.map fun
  | .return items d m => .return (items.mapIdx fun i it => { it with alias := some s!"c{i}" }) d m
  | c => c

private def unionWith (all : Bool) (a b : Query α) : Query α :=
  ⟨⟨aliasReturns a.core.clauses ++ #[.union all] ++ aliasReturns b.core.clauses⟩, a.decode⟩

-- @tg: implements:: [[openspec:cypher-query#Union]]
/-- The rows of both queries without duplicates; both must return the same type. -/
def Query.union (a b : Query α) : Query α := unionWith false a b

/-- The rows of both queries, duplicates kept. -/
def Query.unionAll (a b : Query α) : Query α := unionWith true a b

end Ladybug
