import Tests.Framework
import Tests.Fixtures

/-! Tests for the `graph-orm` capability. -/

namespace Tests.ORM

open Ladybug Tests.Fixtures

def withSchema {α : Type} (m : LbugM α) : IO α := inMem do
  applySchema schema
  m

def ann : Person := ⟨1, "Ann", some 30⟩

/-- Count the queries a program sends, by wrapping the native backend. -/
abbrev CountM := StateT Nat LbugM

instance : MonadGraph CountM where
  runQuery q := do modify (· + 1); (runQuery q : LbugM _)
  runStmt s := do modify (· + 1); (runStmt s : LbugM Unit)
  withTxMode mode body := fun n => MonadGraph.withTxMode mode (body n)
  applySchema s := (applySchema s : LbugM Unit)
  verifySchema s := (verifySchema s : LbugM _)

private def countPersons : LbugM Int64 := do
  return (← runQueryM do let p ← match_ (node Person); return_ (Expr.count p.id))[0]!

/-! ## Node CRUD -/

-- @tg: verifies:: [[openspec:graph-orm#Node CRUD#Insert then get]] {level: integration}
def insertThenGet : IO Unit := do
  let p ← withSchema do Repo.insert ann; Repo.get? Person (1 : Int64)
  check (p == some ann) s!"got {p}"

-- @tg: verifies:: [[openspec:graph-orm#Node CRUD#Duplicate insert]] {level: integration}
def duplicateInsert : IO Unit := do
  let (err, p) ← withSchema do
    Repo.insert ann
    let err ← try Repo.insert { ann with name := "Other" }; pure none catch e => pure (some e)
    return (err, ← Repo.get? Person (1 : Int64))
  check (match err with | some (.constraint _) => true | _ => false) s!"error: {err}"
  check (p == some ann) s!"first value changed: {p}"

-- @tg: verifies:: [[openspec:graph-orm#Node CRUD#Upsert overwrites]] {level: integration}
def upsertOverwrites : IO Unit := do
  let (p, n) ← withSchema do
    Repo.insert ann
    Repo.upsert { ann with name := "Bea" }
    return (← Repo.get? Person (1 : Int64), ← countPersons)
  check (p.map (·.name) == some "Bea") s!"got {p}"
  assertEq n 1 "person count"

-- @tg: verifies:: [[openspec:graph-orm#Node CRUD#Get missing]] {level: integration}
def getMissing : IO Unit := do
  let p ← withSchema (Repo.get? Person (99 : Int64))
  check p.isNone s!"got {p}"

-- @tg: verifies:: [[openspec:graph-orm#Node CRUD#Update missing]] {level: integration}
def updateMissing : IO Unit := do
  let db ← lbug (Database.open ":memory:")
  discard <| expectError (db.withConnection do applySchema schema; Repo.update (Person.mk 99 "x" none))
    (fun | .notFound _ => true | _ => false) "update of a missing node"

-- @tg: verifies:: [[openspec:graph-orm#Node CRUD#Delete with relationships]] {level: integration}
def deleteWithRelationships : IO Unit := do
  let (err, p, rels) ← withSchema do
    Repo.insert ann
    Repo.insert (Company.mk "ACME" 1990)
    Repo.link (1 : Int64) (WorksAt.mk 2020) "ACME"
    let err ← try Repo.delete Person (1 : Int64); pure none catch e => pure (some e)
    Repo.detachDelete Person (1 : Int64)
    let rels ← runQueryM do
      let c ← match_ (node Company)
      let (w, _) ← match_ (inc c WorksAt (node Person))
      return_ w.since
    return (err, ← Repo.get? Person (1 : Int64), rels)
  check (match err with | some (.constraint _) => true | _ => false) s!"delete error: {err}"
  check p.isNone "person still exists"
  check rels.isEmpty s!"relationships left: {rels}"

-- @tg: verifies:: [[openspec:graph-orm#Node CRUD#Find by predicate]] {level: integration}
def findByPredicate : IO Unit := do
  let found ← withSchema do
    for p in [Person.mk 1 "a" (some 20), Person.mk 2 "b" (some 40), Person.mk 3 "c" none] do Repo.insert p
    Repo.findWhere Person fun p => p.age >. 30
  check (found.map (·.id) == #[2]) s!"found {found}"

/-! ## Relationships -/

private def withAcme {α : Type} (m : LbugM α) : IO α := withSchema do
  Repo.insert ann
  Repo.insert (Company.mk "ACME" 1990)
  m

-- @tg: verifies:: [[openspec:graph-orm#Relationship links#Link and list]] {level: integration}
def linkAndList : IO Unit := do
  let rels ← withAcme do
    Repo.link (1 : Int64) (WorksAt.mk 2020) "ACME"
    Repo.between WorksAt (1 : Int64) "ACME"
  check (rels == #[WorksAt.mk 2020]) s!"rels: {repr rels}"

-- @tg: verifies:: [[openspec:graph-orm#Relationship links#Link with missing endpoint]] {level: integration}
def linkMissingEndpoint : IO Unit := do
  let (err, n) ← withAcme do
    let err ← try Repo.link (1 : Int64) (WorksAt.mk 2020) "Nope"; pure none catch e => pure (some e)
    return (err, (← Repo.outgoing WorksAt (1 : Int64)).size)
  check (match err with | some (.notFound _) => true | _ => false) s!"error: {err}"
  assertEq n 0 "relationships"

-- @tg: verifies:: [[openspec:graph-orm#Relationship links#Unlink]] {level: integration}
def unlinkKeepsNodes : IO Unit := do
  let (rels, p, c) ← withAcme do
    Repo.link (1 : Int64) (WorksAt.mk 2020) "ACME"
    Repo.unlink WorksAt (1 : Int64) "ACME"
    return (← Repo.between WorksAt (1 : Int64) "ACME", ← Repo.get? Person (1 : Int64), ← Repo.get? Company "ACME")
  check rels.isEmpty s!"rels: {repr rels}"
  check (p.isSome && c.isSome) "a node was deleted"

/-! ## Traversal -/

-- @tg: verifies:: [[openspec:graph-orm#Traversal helpers#Outgoing neighbours]] {level: integration}
def outgoingNeighbours : IO Unit := do
  let out ← withAcme do
    Repo.insert (Company.mk "Init" 2001)
    Repo.link (1 : Int64) (WorksAt.mk 2020) "ACME"
    Repo.link (1 : Int64) (WorksAt.mk 2022) "Init"
    Repo.outgoing WorksAt (1 : Int64)
  let got := out.toList.map (fun (c, w) => (c.name, w.since)) |>.mergeSort (fun a b => a.1 ≤ b.1)
  check (got == [("ACME", 2020), ("Init", 2022)]) s!"outgoing: {got}"

-- @tg: verifies:: [[openspec:graph-orm#Traversal helpers#Incoming neighbours]] {level: integration}
def incomingNeighbours : IO Unit := do
  let inc ← withAcme do
    Repo.insert (Person.mk 2 "Bob" none)
    Repo.link (1 : Int64) (WorksAt.mk 2020) "ACME"
    Repo.link (2 : Int64) (WorksAt.mk 2021) "ACME"
    Repo.incoming WorksAt "ACME"
  let ids := inc.toList.map (·.1.id) |>.mergeSort
  check (ids == [1, 2]) s!"incoming: {ids}"

/-! ## Batches -/

def people (n : Nat) (offset : Nat := 0) : Array Person :=
  (Array.range n).map fun i =>
    let id := Int64.ofNat (i + offset)
    ⟨id, s!"p{i + offset}", if i % 3 == 0 then none else some (Int64.ofNat (i % 90))⟩

-- @tg: verifies:: [[openspec:graph-orm#Batched insert#Insert ten thousand nodes]] {level: integration}
def insertTenThousand : IO Unit := do
  let (queries, n) ← withSchema do
    let ((), queries) ← (Repo.insertMany (people 10000) (batchSize := 1000) : CountM Unit).run 0
    return (queries, ← countPersons)
  assertEq queries 10 "queries"
  assertEq n 10000 "persons"

-- @tg: verifies:: [[openspec:graph-orm#Batched insert#Failure rolls back]] {level: integration}
def batchFailureRollsBack : IO Unit := do
  let (err, n) ← withSchema do
    Repo.insertMany (people 5)
    let before ← countPersons
    -- Keys 100…2599, then key 2 again in the third batch.
    let load := people 2500 100 |>.push ⟨2, "dup", none⟩
    let err ← try withTx (Repo.insertMany load (batchSize := 1000)); pure none catch e => pure (some e)
    return (err, (before, ← countPersons))
  check (match err with | some (.constraint _) => true | _ => false) s!"error: {err}"
  assertEq n.2 n.1 "count after failed load"

/-! ## File import -/

-- @tg: verifies:: [[openspec:graph-orm#File import#CSV import]] {level: integration}
def csvImport : IO Unit := do
  IO.FS.createDirAll ".lake/test-tmp"
  let path := ".lake/test-tmp/persons.csv"
  IO.FS.writeFile path "id,name,age\n1,Ann,30\n2,Bob,\n3,Cid,52\n"
  let ps ← withSchema do
    Repo.copyNodes Person path
    runQueryM do
      let p ← match_ (node Person)
      orderBy p.id
      return_ p
  check (ps == #[⟨1, "Ann", some 30⟩, ⟨2, "Bob", none⟩, ⟨3, "Cid", some 52⟩]) s!"persons: {ps}"

def tests : List Test := [
  ⟨"graph-orm: insert then get", insertThenGet⟩,
  ⟨"graph-orm: duplicate insert", duplicateInsert⟩,
  ⟨"graph-orm: upsert overwrites", upsertOverwrites⟩,
  ⟨"graph-orm: get missing", getMissing⟩,
  ⟨"graph-orm: update missing", updateMissing⟩,
  ⟨"graph-orm: delete with relationships", deleteWithRelationships⟩,
  ⟨"graph-orm: find by predicate", findByPredicate⟩,
  ⟨"graph-orm: link and list", linkAndList⟩,
  ⟨"graph-orm: link with missing endpoint", linkMissingEndpoint⟩,
  ⟨"graph-orm: unlink keeps nodes", unlinkKeepsNodes⟩,
  ⟨"graph-orm: outgoing neighbours", outgoingNeighbours⟩,
  ⟨"graph-orm: incoming neighbours", incomingNeighbours⟩,
  ⟨"graph-orm: insert ten thousand nodes", insertTenThousand⟩,
  ⟨"graph-orm: batch failure rolls back", batchFailureRollsBack⟩,
  ⟨"graph-orm: CSV import", csvImport⟩
]

end Tests.ORM
