import Ladybug.Graph

/-!
# Repository operations

Generic create/read/update/delete, relationship and traversal operations on
declared tables, written once against `MonadGraph`:

```lean
Repo.insert (Person.mk 1 "Ann" none)
let p? ← Repo.get? Person (1 : Int64)
Repo.link (1 : Int64) (WorksAt.mk 2020) "ACME"
let jobs ← Repo.outgoing WorksAt (1 : Int64)   -- Array (Company × WorksAt)
```
-/

namespace Ladybug.Repo

open Cypher

variable {m : Type → Type} {α ρ σ τ κ κ' V O β : Type}

/-! ## Core helpers -/

private def keyEq (var : String) (key : String) (v : Value) : Core.Expr :=
  .binop .eq (.prop (.var var) key) (.value v)

private def nodeMatch (var : String) (label key : String) (k : Value) : Array Core.Clause :=
  #[.match false [⟨⟨var, some label, []⟩, []⟩], .where (keyEq var key k)]

/-- `SET var.c = …` for every column except `skip`; nothing if there is none. -/
private def setAll (var : String) (cols : Array Column) (skip : String) (v : Value) : Array Core.Clause :=
  match (cols.toList.filter (·.name != skip)).map fun c =>
      (⟨.prop (.var var) c.name, c.written (.value ((v.field? c.name).getD .null))⟩ : Core.SetItem) with
  | [] => #[]
  | items => #[.set items]

private def propsOf (cols : Array Column) (v : Value) : List (String × Core.Expr) :=
  cols.toList.map fun c => (c.name, c.written (.value ((v.field? c.name).getD .null)))

private def returnItems (es : List Core.Expr) : Core.Clause := .return (es.map (⟨·, none⟩)) false {}

private def countQuery (cs : Array Core.Clause) : Query Int64 :=
  ⟨⟨cs.push (returnItems [.countStar])⟩, FromRow.decode⟩

private def runCount [MonadGraph m] (cs : Array Core.Clause) : m Int64 := do
  return (← runQuery (countQuery cs))[0]?.getD 0

private def keyOf [NodeKey α κ] [ToValue κ] (x : α) : Value := toValue (NodeKey.keyOf x)

/-! ## Nodes -/

-- @tg: implements:: [[openspec:graph-orm#Node CRUD]]
/-- Create a node; fails with `.constraint` if its key exists. -/
def insert [MonadGraph m] [NodeTable α] [ToValue α] (x : α) : m Unit :=
  runStmt ⟨⟨#[.create [⟨⟨"n0", some (NodeTable.label α), propsOf (NodeTable.columns α) (toValue x)⟩, []⟩]]⟩⟩

/-- Create the node, or overwrite every property of the node with the same key. -/
def upsert [MonadGraph m] [NodeTable α] [ToValue α] (x : α) : m Unit := do
  let v := toValue x
  let key := NodeTable.key α
  runStmt ⟨⟨#[.merge ⟨⟨"n0", some (NodeTable.label α), [(key, .value ((v.field? key).getD .null))]⟩, []⟩]
    ++ setAll "n0" (NodeTable.columns α) key v⟩⟩

/-- The node with this key, if any. -/
def get? (α : Type) [MonadGraph m] [NodeTable α] [FromValue α] [NodeKey α κ] [ToValue κ] (k : κ) : m (Option α) := do
  let cs := nodeMatch "n0" (NodeTable.label α) (NodeTable.key α) (toValue k)
  let q : Query α := ⟨⟨cs.push (returnItems [.var "n0"])⟩, FromRow.decode⟩
  return (← runQuery q)[0]?

def findAll (α : Type) [MonadGraph m] [NodeTable α] [FromValue α] : m (Array α) :=
  runQuery (⟨⟨#[.match false [⟨⟨"n0", some (NodeTable.label α), []⟩, []⟩], returnItems [.var "n0"]]⟩,
    FromRow.decode⟩ : Query α)

/-- The nodes satisfying a typed predicate. -/
def findWhere (α : Type) [MonadGraph m] [NodeTable α] [FromValue α] [HasVar α V O] [NodeVarOf V α]
    [Expr.IsPred β] (pred : V → Expr β) : m (Array α) :=
  runQueryM do
    let v ← match_ (node α)
    where_ (pred v)
    return_ v

/-- Overwrite the node with the same key; fails with `.notFound` if there is none. -/
def update [MonadGraph m] [NodeTable α] [ToValue α] [NodeKey α κ] [ToValue κ] (x : α) : m Unit := do
  let v := toValue x
  let key := NodeTable.key α
  let n ← runCount (nodeMatch "n0" (NodeTable.label α) key (keyOf x) ++ setAll "n0" (NodeTable.columns α) key v)
  if n == 0 then throw (.notFound s!"{NodeTable.label α} with {key} = {keyOf x}")

/-- Delete the node with this key; fails with `.constraint` if it has relationships. -/
def delete (α : Type) [MonadGraph m] [NodeTable α] [NodeKey α κ] [ToValue κ] (k : κ) : m Unit :=
  runStmt ⟨⟨nodeMatch "n0" (NodeTable.label α) (NodeTable.key α) (toValue k) |>.push (.delete false [.var "n0"])⟩⟩

/-- Delete the node with this key and all of its relationships. -/
def detachDelete (α : Type) [MonadGraph m] [NodeTable α] [NodeKey α κ] [ToValue κ] (k : κ) : m Unit :=
  runStmt ⟨⟨nodeMatch "n0" (NodeTable.label α) (NodeTable.key α) (toValue k) |>.push (.delete true [.var "n0"])⟩⟩

/-! ## Relationships -/

private def endpoints (ρ : Type) [RelTable ρ σ τ] [NodeTable σ] [NodeTable τ] (src dst : Value) : Array Core.Clause :=
  nodeMatch "a" (NodeTable.label σ) (NodeTable.key σ) src ++ nodeMatch "b" (NodeTable.label τ) (NodeTable.key τ) dst

private def relStep (ρ : Type) [RelTable ρ σ τ] (from_ to : String) : Core.Clause :=
  .match false [⟨⟨from_, none, []⟩, [(⟨some "r", RelTable.label ρ, .out, []⟩, ⟨to, none, []⟩)]⟩]

-- @tg: implements:: [[openspec:graph-orm#Relationship links]]
/-- Create a relationship between the nodes with these keys; fails with
`.notFound`, creating nothing, if either node is missing. -/
def link [MonadGraph m] [RelTable ρ σ τ] [NodeTable σ] [NodeTable τ] [ToValue ρ]
    [NodeKey σ κ] [NodeKey τ κ'] [ToValue κ] [ToValue κ'] (src : κ) (r : ρ) (dst : κ') : m Unit := do
  let rel : Core.RelPat := ⟨some "r", RelTable.label ρ, .out, propsOf (RelTable.columns ρ) (toValue r)⟩
  let create := Core.Clause.create [⟨⟨"a", none, []⟩, [(rel, ⟨"b", none, []⟩)]⟩]
  let n ← runCount ((endpoints ρ (toValue src) (toValue dst)).push create)
  if n == 0 then
    throw (.notFound s!"{RelTable.label ρ}: no {NodeTable.label σ} {toValue src} or no {NodeTable.label τ} {toValue dst}")

/-- The relationships of table `ρ` from one node to another. -/
def between (ρ : Type) [MonadGraph m] [RelTable ρ σ τ] [NodeTable σ] [NodeTable τ] [FromValue ρ]
    [NodeKey σ κ] [NodeKey τ κ'] [ToValue κ] [ToValue κ'] (src : κ) (dst : κ') : m (Array ρ) :=
  runQuery (⟨⟨(endpoints ρ (toValue src) (toValue dst)).push (relStep ρ "a" "b") |>.push (returnItems [.var "r"])⟩,
    FromRow.decode⟩ : Query ρ)

/-- Delete the relationships of table `ρ` from one node to another; the nodes stay. -/
def unlink (ρ : Type) [MonadGraph m] [RelTable ρ σ τ] [NodeTable σ] [NodeTable τ]
    [NodeKey σ κ] [NodeKey τ κ'] [ToValue κ] [ToValue κ'] (src : κ) (dst : κ') : m Unit :=
  runStmt ⟨⟨(endpoints ρ (toValue src) (toValue dst)).push (relStep ρ "a" "b") |>.push (.delete false [.var "r"])⟩⟩

/-! ## Traversal -/

-- @tg: implements:: [[openspec:graph-orm#Traversal helpers]]
/-- The destination nodes of `ρ` relationships leaving the node with this key, with the relationships. -/
def outgoing (ρ : Type) [MonadGraph m] [RelTable ρ σ τ] [NodeTable σ] [NodeTable τ] [FromValue τ] [FromValue ρ]
    [NodeKey σ κ] [ToValue κ] (src : κ) : m (Array (τ × ρ)) :=
  let cs := nodeMatch "a" (NodeTable.label σ) (NodeTable.key σ) (toValue src)
  let step := Core.Clause.match false
    [⟨⟨"a", none, []⟩, [(⟨some "r", RelTable.label ρ, .out, []⟩, ⟨"b", some (NodeTable.label τ), []⟩)]⟩]
  runQuery (⟨⟨cs.push step |>.push (returnItems [.var "b", .var "r"])⟩, FromRow.decode⟩ : Query (τ × ρ))

/-- The source nodes of `ρ` relationships entering the node with this key, with the relationships. -/
def incoming (ρ : Type) [MonadGraph m] [RelTable ρ σ τ] [NodeTable σ] [NodeTable τ] [FromValue σ] [FromValue ρ]
    [NodeKey τ κ'] [ToValue κ'] (dst : κ') : m (Array (σ × ρ)) :=
  let cs := nodeMatch "b" (NodeTable.label τ) (NodeTable.key τ) (toValue dst)
  let step := Core.Clause.match false
    [⟨⟨"b", none, []⟩, [(⟨some "r", RelTable.label ρ, .inc, []⟩, ⟨"a", some (NodeTable.label σ), []⟩)]⟩]
  runQuery (⟨⟨cs.push step |>.push (returnItems [.var "a", .var "r"])⟩, FromRow.decode⟩ : Query (σ × ρ))

/-! ## Batches -/

private def chunks (xs : Array β) (size : Nat) : Array (Array β) := Id.run do
  let size := max size 1
  let mut out := #[]
  let mut i := 0
  while i < xs.size do
    out := out.push (xs.extract i (i + size))
    i := i + size
  return out

private def rowProps (cols : Array Column) : List (String × Core.Expr) :=
  cols.toList.map fun c => (c.name, c.written (.prop (.var "row") c.name))

-- @tg: implements:: [[openspec:graph-orm#Batched insert]]
/-- Insert nodes in batches, one `UNWIND $rows … CREATE` query per batch.
Run it inside `withTx` to make the whole load atomic. -/
def insertMany [MonadGraph m] [NodeTable α] [ToValue α] (xs : Array α) (batchSize : Nat := 1000) : m Unit := do
  for batch in chunks xs batchSize do
    runStmt ⟨⟨#[.unwind (.value (.list (batch.map toValue))) "row",
      .create [⟨⟨"n0", some (NodeTable.label α), rowProps (NodeTable.columns α)⟩, []⟩]]⟩⟩

/-- Upsert nodes in batches, one `UNWIND $rows … MERGE … SET` query per batch. -/
def upsertMany [MonadGraph m] [NodeTable α] [ToValue α] (xs : Array α) (batchSize : Nat := 1000) : m Unit := do
  let key := NodeTable.key α
  let rest := (NodeTable.columns α).toList.filter (·.name != key)
  for batch in chunks xs batchSize do
    let clauses : Array Core.Clause := #[.unwind (.value (.list (batch.map toValue))) "row",
      .merge ⟨⟨"n0", some (NodeTable.label α), [(key, .prop (.var "row") key)]⟩, []⟩]
    let clauses := if rest.isEmpty then clauses
      else clauses.push (.set (rest.map fun c => ⟨.prop (.var "n0") c.name, c.written (.prop (.var "row") c.name)⟩))
    runStmt ⟨⟨clauses⟩⟩

/-- Create relationships in batches from (source key, relationship, destination key) triples. -/
def linkMany [MonadGraph m] [RelTable ρ σ τ] [NodeTable σ] [NodeTable τ] [ToValue ρ] [ToValue κ] [ToValue κ']
    (triples : Array (κ × ρ × κ')) (batchSize : Nat := 1000) : m Unit := do
  let cols := RelTable.columns ρ
  for batch in chunks triples batchSize do
    let rows := batch.map fun (s, r, d) =>
      let rv := toValue r
      Value.struct (#[("lbug_src", toValue s), ("lbug_dst", toValue d)] ++
        cols.map fun c => (c.name, (rv.field? c.name).getD .null))
    let rel : Core.RelPat := ⟨some "r", RelTable.label ρ, .out, rowProps cols⟩
    runStmt ⟨⟨#[.unwind (.value (.list rows)) "row",
      .match false [⟨⟨"a", some (NodeTable.label σ), []⟩, []⟩],
      .where (.binop .eq (.prop (.var "a") (NodeTable.key σ)) (.prop (.var "row") "lbug_src")),
      .match false [⟨⟨"b", some (NodeTable.label τ), []⟩, []⟩],
      .where (.binop .eq (.prop (.var "b") (NodeTable.key τ)) (.prop (.var "row") "lbug_dst")),
      .create [⟨⟨"a", none, []⟩, [(rel, ⟨"b", none, []⟩)]⟩]]⟩⟩

end Ladybug.Repo
