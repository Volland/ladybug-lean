import AgentMemory.Memory

/-!
# Checked while compiling

Everything in this file runs when the file is built: `#guard` evaluates the
memory functions on the in-memory backend, and `#guard_msgs` pins the errors
for queries that do not fit the schema. If the library, the schema or the
queries change behaviour, the build fails.
-/

namespace AgentMemory.Checks

open Ladybug AgentMemory

/-- Run on a fresh in-memory graph with the example history. -/
def onSeed {α : Type} (prog : MemM α) : Except Error α := (do seed; prog).run' {}

#guard (onSeed (about "Ann")).toOption == some #[("Ann started the Ladybug bindings", 5),
  ("Meetup in Kyiv about graph memory", 4), ("Bob reviewed Ann's first query", 3)]

#guard ((onSeed (neighbourhood "Ann")).toOption).map (·.toList.mergeSort) == some ["Bob", "Ladybug", "Lean"]

#guard (onSeed (distance 1 4)).toOption == some (some 3)

#guard (onSeed forgotten).toOption == some #["Kyiv"]

#guard ((onSeed (recallSimilar (vec [1, 0, 0, 0]) 2)).toOption).map (·.map (·.1)) ==
  some #["Ann started the Ladybug bindings", "Bob reviewed Ann's first query"]

/-! Queries that do not fit the schema are rejected before anything runs. -/

/-- error: unknown property 'importanse' of table Memory; did you mean 'importance'? -/
#guard_msgs in
example := cypher% MATCH (mem:Memory) RETURN mem.importanse

/-- error: unknown node label 'Memroy'; did you mean 'Memory'? -/
#guard_msgs in
example := cypher% MATCH (mem:Memroy) RETURN mem.text

-- `Mentions` goes from a memory to an entity, not the other way round.
/-- error: failed to synthesize instance of type class Matchable (PatOut Entity.Var Mentions (NodeRef Memory)) -/
#guard_msgs (whitespace := lax, substring := true) in
example : Query String := query do
  let e ← match_ (node Entity)
  let (_, mem) ← match_ (out e Mentions (node Memory))
  return_ mem.text

-- Importance is an `Int32`: comparing it with a string is a type error.
/-- error: failed to synthesize instance of type class Expr.LitFor Int32 String -/
#guard_msgs (whitespace := lax, substring := true) in
example : Query String := query do
  let mem ← match_ (node Memory)
  where_ (mem.importance >. lit "high")
  return_ mem.text

-- An optional match makes every property nullable, and the result type says so.
example : Query (String × Option String) :=
  cypher% MATCH (mem:Memory) OPTIONAL MATCH (mem)-[:Mentions]->(e:Entity) RETURN mem.text, e.kind

end AgentMemory.Checks
