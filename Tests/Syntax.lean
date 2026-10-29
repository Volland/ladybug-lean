import Tests.Framework
import Tests.Fixtures

/-!
Tests for the `cypher-syntax` capability. Compile-time scenarios are checked
while this module builds; the rest run in the test executable.
-/

namespace Tests.Syntax

open Ladybug Tests.Fixtures

/-! ## Compile-time scenarios -/

-- @tg: verifies:: [[openspec:cypher-syntax#Embedded Cypher#Read query]] {level: unit}
example : Query String := cypher% MATCH (p:Person) WHERE p.age > 30 RETURN p.name

-- @tg: verifies:: [[openspec:cypher-syntax#Embedded Cypher#Statement]] {level: unit}
example : Statement := cypher% MATCH (p:Person) SET p.age = 1

-- @tg: verifies:: [[openspec:cypher-syntax#Embedded Cypher#Lowercase keywords]] {level: unit}
example : Query Person := cypher% match (p:Person) return p

-- @tg: verifies:: [[openspec:cypher-syntax#Schema-checked elaboration#Unknown label]] {level: unit}
/-- error: unknown node label 'Persn'; did you mean 'Person'? -/
#guard_msgs in
example := cypher% MATCH (p:Persn) RETURN p

-- @tg: verifies:: [[openspec:cypher-syntax#Schema-checked elaboration#Unknown property]] {level: unit}
/-- error: unknown property 'nmae' of table Person; did you mean 'name'? -/
#guard_msgs in
example := cypher% MATCH (p:Person) RETURN p.nmae

-- @tg: verifies:: [[openspec:cypher-syntax#Schema-checked elaboration#Inferred tuple type]] {level: unit}
example : Query (String × Option String) :=
  cypher% MATCH (p:Person) OPTIONAL MATCH (p)-[:WorksAt]->(c:Company) RETURN p.name, c.name

def textLocal : String := "x"

-- @tg: verifies:: [[openspec:cypher-syntax#Lean values as parameters#Wrongly typed local]] {level: unit}
/-- error: failed to synthesize instance of type class Expr.LitFor (Option Int64) String -/
#guard_msgs (whitespace := lax, substring := true) in
example := cypher% MATCH (p:Person) WHERE p.age > $textLocal RETURN p

-- @tg: verifies:: [[openspec:cypher-syntax#Located errors#Error position]] {level: unit}
/--
@ +2:26...32
error: unknown property 'nmae' of table Person; did you mean 'name'?
-/
#guard_msgs (positions := true) in
example := cypher% MATCH (p:Person)
                   RETURN p.nmae

-- An unsupported construct points at the raw-text API.
/-- error: cypher%: function percentileCont is not supported; use the raw-text API (`queryRaw`) for it -/
#guard_msgs in
example := cypher% MATCH (p:Person) RETURN percentileCont(p.age)

/-- A long query, to keep an eye on elaboration time. -/
def longQuery := cypher%
  MATCH (p:Person) MATCH (p)-[:WorksAt]->(c:Company) MATCH (p)-[:Knows]->(q:Person)
  MATCH (q)-[:WorksAt]->(d:Company) MATCH (q)-[:Knows]->(r:Person) MATCH (r)-[:WorksAt]->(e:Company)
  WHERE p.age > 20 AND q.age > 21 AND r.age > 22
  WHERE c.name <> d.name OR d.name <> e.name
  WHERE p.id <> q.id WHERE q.id <> r.id WHERE p.id <> r.id
  WHERE p.name STARTS WITH "a" WHERE q.name ENDS WITH "b" WHERE r.name CONTAINS "c"
  WHERE c.founded > 1900 WHERE d.founded > 1901 WHERE e.founded > 1902
  WHERE p.age IS NOT NULL WHERE q.age IS NOT NULL WHERE r.age IS NOT NULL
  WHERE p.id IN [1, 2, 3] WHERE q.id IN [4, 5, 6] WHERE r.id IN [7, 8, 9]
  WITH p, c, count(q) AS n
  WHERE n > 0
  RETURN p.name, c.name, n ORDER BY n DESC LIMIT 10

/-! ## Runtime scenarios -/

-- @tg: verifies:: [[openspec:cypher-syntax#Same AST as the builder#Equivalent queries print identically]] {level: unit}
def equivalentQueries : IO Unit := do
  let viaSyntax := cypher% MATCH (p:Person)-[:WorksAt]->(c:Company) RETURN p.name, c.name
  let viaBuilder : Query (String × String) := query do
    let p ← match_ (node Person)
    let (_, c) ← match_ (out p WorksAt (node Company))
    return_ (p.name, c.name)
  check (viaSyntax.print == viaBuilder.print) s!"{viaSyntax.text}\n vs {viaBuilder.text}"
  let s2 := cypher% MATCH (p:Person) WHERE p.age > 30 OR p.name = "nulled" RETURN p.name ORDER BY p.name LIMIT 5
  let b2 : Query String := query do
    let p ← match_ (node Person)
    where_ (p.age >. 30 ||. p.name ==. lit "nulled")
    orderBy p.name
    limit 5
    return_ p.name
  check (s2.print == b2.print) s!"{s2.text}\n vs {b2.text}"

-- @tg: verifies:: [[openspec:cypher-syntax#Lean values as parameters#Local becomes a parameter]] {level: unit}
def localBecomesParameter : IO Unit := do
  let minAge : Int64 := 30
  let q := cypher% MATCH (p:Person) WHERE p.age > $minAge RETURN p.name
  let (text, params) := q.print
  check ((text.splitOn "$p0").length > 1) s!"text: {text}"
  check (params == #[("p0", .int64 30)]) s!"params: {params}"

/-- A `cypher%` query runs on the native backend like its builder form. -/
def runsNatively : IO Unit := do
  let rows ← inMem do
    applySchema schema
    runStmt (cypher% CREATE (p:Person {id: 1, name: "Ann", age: 41}))
    runStmt (cypher% CREATE (p:Person {id: 2, name: "Bob"}))
    runStmt (cypher% CREATE (c:Company {name: "ACME", founded: 1990}))
    runStmt (cypher% MATCH (p:Person), (c:Company) WHERE p.id = 1 CREATE (p)-[:WorksAt {since: 2020}]->(c))
    runQuery (cypher% MATCH (p:Person) OPTIONAL MATCH (p)-[w:WorksAt]->(c:Company)
                      RETURN p.name, c.name, w.since ORDER BY p.id)
  check (rows == #[("Ann", some "ACME", some 2020), ("Bob", none, none)]) s!"rows: {rows}"

def tests : List Test := [
  ⟨"cypher-syntax: equivalent queries print identically", equivalentQueries⟩,
  ⟨"cypher-syntax: local becomes a parameter", localBecomesParameter⟩,
  ⟨"cypher-syntax: runs on the native backend", runsNatively⟩
]

end Tests.Syntax
