import Tests.Framework
import Tests.Fixtures
import Tests.Typed
import Tests.Advanced
import Tests.MemEval

/-! Tests for the `memory-backend` capability. -/

namespace Tests.Memory

open Ladybug Tests.Fixtures

def mem {α : Type} (m : MemM α) : IO α := do
  match m.run' {} with
  | .ok a => return a
  | .error e => fail (toString e)

def memWithSchema {α : Type} (m : MemM α) : IO α := mem do applySchema schema; m

-- @tg: verifies:: [[openspec:memory-backend#Pure graph state#Same program, two backends]] {level: unit}
def sameProgram : IO Unit := do
  assertEq (← memWithSchema Tests.Typed.createTwoAndCount) 2 "count"

-- @tg: verifies:: [[openspec:memory-backend#Full AST evaluation#Three-valued logic in memory]] {level: unit}
def threeValuedLogic : IO Unit := do
  let ns ← memWithSchema do
    for p in Tests.Typed.persons do Repo.insert p
    let rows ← runQueryM do
      let p ← match_ (node Person)
      where_ (p.age >. 30 ||. p.name ==. lit "nulled")
      return_ p.name
    return rows.toList.mergeSort
  assertEq ns ["nulled", "old"] "names"

-- @tg: verifies:: [[openspec:memory-backend#Full AST evaluation#Paths in memory]] {level: unit}
def pathsInMemory : IO Unit := do
  let rows ← memWithSchema do
    for i in [1, 2, 3, 4, 5] do Repo.insert (Person.mk i s!"p{i}" none)
    for (a, b) in [((1 : Int64), (2 : Int64)), (2, 4), (1, 3), (3, 5), (5, 4)] do Repo.link a Knows.mk b
    runQueryM do
      let a ← match_ (node Person)
      let (path, b) ← shortestPath a Knows (node Person) (max := 5)
      where_ (a.id ==. 1 &&. b.id ==. 4)
      return_ path
  match rows with
  | #[(path : Path Person Knows)] => assertEq (path.nodes.map (·.id)) #[1, 2, 4] "nodes"
  | _ => fail s!"rows: {rows.size}"

-- @tg: verifies:: [[openspec:memory-backend#Full AST evaluation#Vector search in memory]] {level: unit}
def vectorInMemory : IO Unit := do
  let rows ← mem do
    applySchema [.ofNode Tests.Advanced.Doc]
    for d in Tests.Advanced.docs do Repo.insert d
    runStmt (createVectorIndex Tests.Advanced.Doc "doc_vec" "emb")
    runQueryM do
      let (d, dist) ← vectorSearch Tests.Advanced.Doc "doc_vec" (Tests.Advanced.emb [1, 0, 0]) 2
      orderBy dist
      return_ d.id
  assertEq rows #[1, 3] "nearest"

-- @tg: verifies:: [[openspec:memory-backend#Schema enforcement in memory#Duplicate key in memory]] {level: unit}
def duplicateKey : IO Unit := do
  let r := (do applySchema schema; Repo.insert (Person.mk 1 "a" none); Repo.insert (Person.mk 1 "b" none) : MemM Unit).run' {}
  check (match r with | .error (.constraint _) => true | _ => false) "duplicate key accepted"

-- @tg: verifies:: [[openspec:memory-backend#Schema enforcement in memory#Unknown table in memory]] {level: unit}
def unknownTable : IO Unit := do
  let r := (Repo.findAll Person : MemM _).run' {}
  check (match r with | .error (.query _) => true | _ => false) "query on an unapplied table succeeded"

-- @tg: verifies:: [[openspec:memory-backend#Snapshot transactions#Rollback in memory]] {level: unit}
def rollback : IO Unit := do
  let n ← memWithSchema do
    try withTx (do Repo.insert (Person.mk 1 "a" none); throw (.custom "boom")) catch _ => pure ()
    return (← Repo.findAll Person).size
  assertEq n 0 "persons after rollback"

/-- Ladybug's implementation-defined behaviour that the evaluator copies. If a
Ladybug upgrade changes one of these, this test fails and the evaluator must
follow (see tg.md constraints). -/
def pinnedBehaviour : IO Unit := do
  let rows ← inMem do
    applySchema schema
    for i in [1, 2] do Repo.insert (Person.mk i s!"p{i}" (if i == 1 then some 3 else none))
    Repo.link (1 : Int64) Knows.mk (2 : Int64)
    Repo.link (2 : Int64) Knows.mk (1 : Int64)
    Repo.link (1 : Int64) Knows.mk (1 : Int64)
    let raw (q : String) : LbugM String := do return toString (← queryRaw q).rows
    return #[
      ← raw "MATCH (p:Person) RETURN p.age ORDER BY p.age",
      ← raw "MATCH (p:Person) RETURN p.age ORDER BY p.age DESC",
      ← raw "RETURN 3 IN [1, NULL], -7 / 2, -7 % 2",
      ← raw "MATCH (a:Person)-[:Knows*3..3]->(b:Person) WHERE a.id = 2 RETURN count(*)",
      ← raw "MATCH (a:Person)-[:Knows]-(b:Person) WHERE a.id = 1 AND b.id = 1 RETURN count(*)",
      ← raw "MATCH p = (a:Person)-[:Knows* SHORTEST 1..3]->(b:Person) WHERE a.id = 1 AND b.id = 1 RETURN count(*)"]
  let expected := #["#[#[3], #[NULL]]", "#[#[NULL], #[3]]", "#[#[false, -3, -1]]", "#[#[3]]", "#[#[2]]", "#[#[0]]"]
  for (got, want) in rows.zip expected do
    assertEq got want "pinned behaviour"

def tests : List Test := [
  ⟨"memory-backend: Ladybug behaviour the evaluator copies", pinnedBehaviour⟩,
  ⟨"memory-backend: same program, two backends", sameProgram⟩,
  ⟨"memory-backend: three-valued logic", threeValuedLogic⟩,
  ⟨"memory-backend: paths", pathsInMemory⟩,
  ⟨"memory-backend: vector search", vectorInMemory⟩,
  ⟨"memory-backend: duplicate key", duplicateKey⟩,
  ⟨"memory-backend: unknown table", unknownTable⟩,
  ⟨"memory-backend: rollback", rollback⟩
]

end Tests.Memory
