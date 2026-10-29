import Tests.Fixtures

/-!
Compile-time scenarios. Each `#guard_msgs` fails the build if the declaration
is accepted or rejected with a different message; each `example` fails it if
the type does not check.
-/

namespace Tests.Compile

open Ladybug Tests.Fixtures

/-! ## graph-schema -/

structure WithFunction where
  id : Int64
  f : Nat → Nat

-- @tg: verifies:: [[openspec:graph-schema#Node table declaration#Unsupported field type rejected]] {level: unit}
/-- error: node_table Tests.Compile.WithFunction: field 'f' has type Nat → Nat, which is not a column type (no Ladybug.CypherType instance) -/
#guard_msgs (whitespace := lax) in
node_table WithFunction

structure WithoutKey where
  name : String

-- @tg: verifies:: [[openspec:graph-schema#Node table declaration#Missing key rejected]] {level: unit}
/-- error: node_table Tests.Compile.WithoutKey: a key is required; add a field `id` or write `node_table Tests.Compile.WithoutKey (key := <field>)` -/
#guard_msgs (whitespace := lax) in
node_table WithoutKey

/-! ## cypher-query -/

-- @tg: verifies:: [[openspec:cypher-query#Typed expressions#Property access is typed]] {level: unit}
example (p : Person.Var) : Expr String := p.name
example (p : Person.Var) : Expr (Option Int64) := p.age

-- @tg: verifies:: [[openspec:cypher-query#Typed expressions#Ill-typed comparison rejected]] {level: unit}
/-- error: failed to synthesize instance of type class Expr.LitFor String Int64 -/
#guard_msgs (whitespace := lax, substring := true) in
example (p : Person.Var) : Expr (Option Bool) := p.name ==. lit (5 : Int64)

-- @tg: verifies:: [[openspec:cypher-query#Three-valued logic#Coalesce removes nullability]] {level: unit}
example (p : Person.Var) : Expr Int64 := coalesce p.age 0

-- @tg: verifies:: [[openspec:cypher-query#Query builder#Wrong endpoint rejected]] {level: unit}
/-- error: failed to synthesize instance of type class Matchable (PatOut Company.Var WorksAt (NodeRef Person)) -/
#guard_msgs (whitespace := lax, substring := true) in
example : Statement := stmt do
  let c ← match_ (node Company)
  let _ ← match_ (out c WorksAt (node Person))

-- @tg: verifies:: [[openspec:cypher-query#Query builder#Optional match makes properties nullable]] {level: unit}
example : Query (String × Option String) := query do
  let p ← match_ (node Person)
  let (_, c) ← optMatch (out p WorksAt (node Company))
  return_ (p.name, c.name)

-- @tg: verifies:: [[openspec:cypher-query#Aggregation#Empty aggregate types]] {level: unit}
example : Query (Option Int64) := query do
  let p ← match_ (node Person)
  return_ (Expr.max p.age)

-- @tg: verifies:: [[openspec:cypher-query#Result typing#Return a tuple]] {level: unit}
example : Query (String × Option Int64) := query do
  let p ← match_ (node Person)
  return_ (p.name, p.age)

end Tests.Compile
