import Tests.Framework
import Tests.Fixtures
import Tests.Compile

/-! Runtime tests for `graph-schema`, `cypher-query` and `graph-monad`. -/

namespace Tests.Typed

open Ladybug Tests.Fixtures

/-- Run a graph program on a fresh in-memory database with the test schema. -/
def withSchema {α : Type} (m : LbugM α) : IO α := inMem do
  applySchema schema
  m

def persons : List Person := [⟨1, "young", some 20⟩, ⟨2, "old", some 40⟩, ⟨3, "nulled", none⟩]

def insertPersons : LbugM Unit := for p in persons do runStmtM (discard (create p))

def names (q : Query String) : LbugM (List String) := do
  return (← runQuery q).toList.mergeSort

/-! ## graph-schema -/

-- @tg: verifies:: [[openspec:graph-schema#Node table declaration#Default label and key]] {level: unit}
def defaultLabelAndKey : IO Unit := do
  assertEq (NodeTable.label Person) "Person" "label"
  assertEq (NodeTable.key Person) "id" "key"
  let age := (NodeTable.columns Person).find? (·.name == "age")
  check (age == some ⟨"age", .int64, true⟩) s!"age column: {repr age}"

-- @tg: verifies:: [[openspec:graph-schema#Node table declaration#Custom key and label]] {level: unit}
def customKeyAndLabel : IO Unit := do
  assertEq (NodeTable.label Firm) "Org" "label"
  assertEq (NodeTable.key Firm) "name" "key"

-- @tg: verifies:: [[openspec:graph-schema#Relationship table declaration#Relationship with property]] {level: unit}
def relWithProperty : IO Unit := do
  assertEq (RelTable.label WorksAt) "WorksAt" "label"
  assertEq (TableDecl.ofRel WorksAt).ddl
    "CREATE REL TABLE IF NOT EXISTS WorksAt(FROM Person TO Company, since INT64)" "ddl"

-- @tg: verifies:: [[openspec:graph-schema#Relationship table declaration#Property-less relationship]] {level: unit}
def propertyLessRel : IO Unit := do
  assertEq (RelTable.columns Knows).size 0 "columns"
  assertEq (TableDecl.ofRel Knows).ddl "CREATE REL TABLE IF NOT EXISTS Knows(FROM Person TO Person)" "ddl"

-- @tg: verifies:: [[openspec:graph-schema#DDL generation#Node DDL text]] {level: unit}
def nodeDDL : IO Unit :=
  assertEq (ddl Person)
    "CREATE NODE TABLE IF NOT EXISTS Person(id INT64, name STRING, age INT64, PRIMARY KEY(id))" "ddl"

-- @tg: verifies:: [[openspec:graph-schema#DDL generation#Apply schema twice]] {level: integration}
def applySchemaTwice : IO Unit := do
  let n ← inMem do
    applySchema schema
    applySchema schema
    return (← queryRaw "CALL show_tables() RETURN name").rows.size
  assertEq n 4 "tables"

-- @tg: verifies:: [[openspec:graph-schema#Schema verification#Matching database]] {level: integration}
def verifyMatching : IO Unit := do
  let diffs ← withSchema (verifySchema schema)
  check diffs.isEmpty s!"diffs: {diffs.toList.map toString}"

-- @tg: verifies:: [[openspec:graph-schema#Schema verification#Type mismatch reported]] {level: integration}
def verifyTypeMismatch : IO Unit := do
  let diffs ← inMem do
    exec "CREATE NODE TABLE Person(id INT64, name STRING, age STRING, PRIMARY KEY(id))"
    verifySchema [.ofNode Person]
  check (diffs == #[.typeMismatch "Person" "age" "INT64" "STRING"]) s!"diffs: {diffs.toList.map toString}"

/-! ## cypher-query -/

-- @tg: verifies:: [[openspec:cypher-query#Typed expressions#Embedded value becomes a parameter]] {level: unit}
def valueBecomesParameter : IO Unit := do
  let q : Query String := query do
    let p ← match_ (node Person)
    where_ (p.name ==. lit "Ann")
    return_ p.name
  let (text, params) := q.print
  check ((text.splitOn "$p0").length > 1 && (text.splitOn "Ann").length == 1) s!"text: {text}"
  check (params == #[("p0", .string "Ann")]) s!"params: {params}"

-- @tg: verifies:: [[openspec:cypher-query#Three-valued logic#Unknown filters out the row]] {level: integration}
def unknownFiltersOut : IO Unit := do
  let ns ← withSchema do
    insertPersons
    names <| query do
      let p ← match_ (node Person)
      where_ (p.age >. 30)
      return_ p.name
  assertEq ns ["old"] "names"

-- @tg: verifies:: [[openspec:cypher-query#Three-valued logic#Unknown OR true is true]] {level: integration}
def unknownOrTrue : IO Unit := do
  let ns ← withSchema do
    insertPersons
    names <| query do
      let p ← match_ (node Person)
      where_ (p.age >. 30 ||. p.name ==. lit "nulled")
      return_ p.name
  assertEq ns ["nulled", "old"] "names"

-- @tg: verifies:: [[openspec:cypher-query#Three-valued logic#Coalesce removes nullability]] {level: integration}
def coalesceValue : IO Unit := do
  let ages ← withSchema do
    insertPersons
    runQueryM do
      let p ← match_ (node Person)
      where_ (p.name ==. lit "nulled")
      return_ (coalesce p.age 0)
  assertEq ages #[0] "ages"

-- @tg: verifies:: [[openspec:cypher-query#Query builder#Relationship pattern]] {level: unit}
def relationshipPattern : IO Unit := do
  let q : Query (String × String) := query do
    let p ← match_ (node Person)
    let (_, c) ← match_ (out p WorksAt (node Company))
    return_ (p.name, c.name)
  assertEq q.text "MATCH (n0:Person) MATCH (n0)-[r1:WorksAt]->(n2:Company) RETURN n0.name, n2.name" "text"

-- @tg: verifies:: [[openspec:cypher-query#Query builder#Optional match makes properties nullable]] {level: integration}
def optionalMatchNull : IO Unit := do
  let rows ← withSchema do
    insertPersons
    runStmtM (discard (create (Company.mk "ACME" 1990)))
    runStmtM do
      let p ← match_ (node Person)
      where_ (p.id ==. 2)
      let c ← match_ (node Company)
      discard (createRel p (WorksAt.mk 2020) c)
    runQueryM do
      let p ← match_ (node Person)
      let (_, c) ← optMatch (out p WorksAt (node Company))
      orderBy p.id
      return_ (p.name, c.name)
  check (rows == #[("young", none), ("old", some "ACME"), ("nulled", none)]) s!"rows: {rows}"

-- @tg: verifies:: [[openspec:cypher-query#Query builder#Create from a value]] {level: integration}
def createFromValue : IO Unit := do
  let ps ← withSchema do
    runStmtM (discard (create (Person.mk 1 "Ann" none)))
    runQueryM do
      let p ← match_ (node Person)
      return_ p
  check (ps == #[⟨1, "Ann", none⟩]) s!"persons: {ps}"

-- @tg: verifies:: [[openspec:cypher-query#Aggregation#Group by]] {level: integration}
def groupBy : IO Unit := do
  let rows ← withSchema do
    insertPersons
    for c in [Company.mk "A" 1, Company.mk "B" 2] do runStmtM (discard (create c))
    for (pid, cname) in [(1, "A"), (2, "A"), (3, "B")] do
      runStmtM do
        let p ← match_ (node Person)
        where_ (p.id ==. lit (pid : Int64))
        let c ← match_ (node Company)
        where_ (c.name ==. lit cname)
        discard (createRel p (WorksAt.mk 2020) c)
    runQueryM do
      let p ← match_ (node Person)
      let (_, c) ← match_ (out p WorksAt (node Company))
      orderBy c.name
      return_ (c.name, Expr.count p.id)
  check (rows == #[("A", 2), ("B", 1)]) s!"rows: {rows}"

-- @tg: verifies:: [[openspec:cypher-query#Aggregation#Empty aggregate types]] {level: integration}
def emptyAggregate : IO Unit := do
  let rows ← withSchema <| runQueryM do
    let p ← match_ (node Person)
    return_ (Expr.max p.age, Expr.count p.id)
  check (rows == #[(none, 0)]) s!"rows: {rows}"

-- @tg: verifies:: [[openspec:cypher-query#Printing#Deterministic text]] {level: unit}
def deterministicText : IO Unit := do
  let q : Query String := query do
    let p ← match_ (node Person)
    where_ (p.age >. 30 &&. p.name !=. lit "x")
    return_ p.name
  check (q.print == q.print) "prints differ"

-- @tg: verifies:: [[openspec:cypher-query#Printing#Quoted identifier]] {level: unit}
def quotedIdentifier : IO Unit := do
  let q : Query Int64 := query do
    let l ← match_ (node Labelled)
    return_ l.id
  assertEq q.text "MATCH (n0:`My Label`) RETURN n0.id" "text"

-- @tg: verifies:: [[openspec:cypher-query#Result typing#Return a whole node]] {level: integration}
def returnWholeNode : IO Unit := do
  let ps ← withSchema do
    insertPersons
    runQueryM do
      let p ← match_ (node Person)
      orderBy p.id
      return_ p
  check (ps.toList == persons) s!"persons: {ps}"

-- @tg: verifies:: [[openspec:cypher-query#Result typing#Return a tuple]] {level: integration}
def returnTuple : IO Unit := do
  let rows ← withSchema do
    insertPersons
    runQueryM do
      let p ← match_ (node Person)
      orderBy p.id
      return_ (p.name, p.age)
  check (rows == #[("young", some 20), ("old", some 40), ("nulled", none)]) s!"rows: {rows}"

/-! ## graph-monad -/

/-- Written against the interface only. -/
def createTwoAndCount {m : Type → Type} [MonadGraph m] : m Int64 := do
  runStmtM (discard (create (Person.mk 1 "a" none)))
  runStmtM (discard (create (Person.mk 2 "b" none)))
  let n ← runQueryM do
    let p ← match_ (node Person)
    return_ (Expr.count p.id)
  return n[0]!

-- @tg: verifies:: [[openspec:graph-monad#Backend-independent execution#Generic function runs on the native backend]] {level: integration}
def genericOnNative : IO Unit := do
  assertEq (← withSchema createTwoAndCount) 2 "count"

-- @tg: verifies:: [[openspec:graph-monad#Backend-independent execution#Read-only transaction rejects writes]] {level: integration}
def readOnlyTxRejects : IO Unit := do
  let (failed, n) ← withSchema do
    let failed ← try
        withReadTx (runStmtM (discard (create (Person.mk 1 "a" none))))
        pure false
      catch _ => pure true
    let n ← runQueryM do
      let p ← match_ (node Person)
      return_ (Expr.count p.id)
    return (failed, n)
  check failed "write in read-only transaction succeeded"
  assertEq n #[0] "count"

-- @tg: verifies:: [[openspec:graph-monad#Native backend#Prepared statement reuse]] {level: integration}
def preparedReuse : IO Unit := do
  let (before, after, ok) ← withSchema do
    insertPersons
    let c ← read
    let before ← c.cachedStatements
    let mut ok := true
    for i in [0:100] do
      let pid := (i % 3 + 1 : Nat)
      let ns ← runQueryM do
        let p ← match_ (node Person)
        where_ (p.id ==. lit (Int64.ofNat pid))
        return_ p.id
      ok := ok && ns == #[Int64.ofNat pid]
    return (before, ← c.cachedStatements, ok)
  check ok "wrong rows"
  assertEq (after - before) 1 "statements prepared"

def tests : List Test := [
  ⟨"graph-schema: default label and key", defaultLabelAndKey⟩,
  ⟨"graph-schema: custom key and label", customKeyAndLabel⟩,
  ⟨"graph-schema: relationship with property", relWithProperty⟩,
  ⟨"graph-schema: property-less relationship", propertyLessRel⟩,
  ⟨"graph-schema: node DDL text", nodeDDL⟩,
  ⟨"graph-schema: apply schema twice", applySchemaTwice⟩,
  ⟨"graph-schema: verify matching database", verifyMatching⟩,
  ⟨"graph-schema: verify reports type mismatch", verifyTypeMismatch⟩,
  ⟨"cypher-query: embedded value becomes a parameter", valueBecomesParameter⟩,
  ⟨"cypher-query: unknown filters out the row", unknownFiltersOut⟩,
  ⟨"cypher-query: unknown OR true is true", unknownOrTrue⟩,
  ⟨"cypher-query: coalesce removes nullability", coalesceValue⟩,
  ⟨"cypher-query: relationship pattern", relationshipPattern⟩,
  ⟨"cypher-query: optional match yields none", optionalMatchNull⟩,
  ⟨"cypher-query: create from a value", createFromValue⟩,
  ⟨"cypher-query: group by", groupBy⟩,
  ⟨"cypher-query: empty aggregate", emptyAggregate⟩,
  ⟨"cypher-query: deterministic text", deterministicText⟩,
  ⟨"cypher-query: quoted identifier", quotedIdentifier⟩,
  ⟨"cypher-query: return a whole node", returnWholeNode⟩,
  ⟨"cypher-query: return a tuple", returnTuple⟩,
  ⟨"graph-monad: generic function on the native backend", genericOnNative⟩,
  ⟨"graph-monad: read-only transaction rejects writes", readOnlyTxRejects⟩,
  ⟨"graph-monad: prepared statement reuse", preparedReuse⟩
]

end Tests.Typed
