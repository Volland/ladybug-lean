import AgentMemory.Schema

/-!
# Remembering and recalling

Every function here is written against `MonadGraph`, so the same code runs on
the native LadybugDB database and on the in-memory graph.
-/

namespace AgentMemory

open Ladybug

variable {m : Type → Type} [MonadGraph m]

/-- Store a memory, link it to the entities it mentions and to the previous memory. -/
def remember (mem : Memory) (mentions : List (String × Float)) (previous : Option Int64 := none) : m Unit :=
  withTx do
    Repo.insert mem
    for (name, w) in mentions do
      Repo.link mem.id (Mentions.mk (some w)) name
    if let some prev := previous then
      Repo.link prev Next.mk mem.id

/-- The `k` memories closest in meaning to `q`, nearest first. -/
def recallSimilar (q : Embedding 4) (k : Nat) : m (Array (String × Float)) :=
  runQueryM do
    let (mem, dist) ← vectorSearch Memory "memory_vec" q k
    orderBy dist
    return_ (mem.text, dist)

/-- The memories that mention an entity, most important first. The query is
plain Cypher, checked against the schema when this file compiles. -/
def about (entity : String) : m (Array (String × Int32)) :=
  runQuery (cypher%
    MATCH (mem:Memory)-[:Mentions]->(e:Entity)
    WHERE e.name = $entity
    RETURN mem.text, mem.importance ORDER BY mem.importance DESC)

/-- Entities reachable from one entity in one or two `Relates` hops. -/
def neighbourhood (entity : String) : m (Array String) :=
  runQueryM do
    let e ← match_ (node Entity)
    let (_, other) ← matchPaths e Relates (node Entity) (max := 2) (dir := .both)
    where_ (e.name ==. lit entity &&. other.name !=. lit entity)
    return_ other.name (distinct := true)

/-- How many steps of the timeline separate two memories. -/
def distance (a b : Int64) : m (Option Int64) := do
  let rows ← runQueryM do
    let x ← match_ (node Memory)
    let (path, y) ← shortestPath x Next (node Memory) (max := 30)
    where_ (x.id ==. lit a &&. y.id ==. lit b)
    return_ (pathLength path)
  return rows[0]?

/-- Entities no memory mentions any more. -/
def forgotten : m (Array String) :=
  runQueryM do
    let e ← match_ (node Entity)
    where_ (Expr.not (← exists_ (discard (match_ (inc e Mentions (node Memory))))))
    return_ e.name

/-- A small history: four memories about a project and the people on it. -/
def seed : m Unit := do
  applySchema schema
  for e in [Entity.mk "Ann" "person", .mk "Bob" "person", .mk "Ladybug" "project", .mk "Lean" "language",
            .mk "Kyiv" "place"] do
    Repo.insert e
  Repo.link "Ann" (Relates.mk "works_on") "Ladybug"
  Repo.link "Bob" (Relates.mk "knows") "Ann"
  Repo.link "Ladybug" (Relates.mk "written_in") "Lean"
  runStmt (createVectorIndex Memory "memory_vec" "embedding")
  let t (d : Int64) : Timestamp := ⟨1790000000000000 + d * 86400000000⟩
  remember ⟨1, "Ann started the Ladybug bindings", 5, t 0, vec [1, 0, 0, 0]⟩ [("Ann", 1.0), ("Ladybug", 0.8)]
  remember ⟨2, "Bob reviewed Ann's first query", 3, t 1, vec [0.8, 0.2, 0, 0]⟩ [("Bob", 1.0), ("Ann", 0.5)] (some 1)
  remember ⟨3, "Typed Cypher compiles in Lean", 8, t 2, vec [0, 1, 0, 0]⟩ [("Lean", 1.0), ("Ladybug", 1.0)] (some 2)
  remember ⟨4, "Meetup in Kyiv about graph memory", 4, t 3, vec [0, 0, 1, 0]⟩ [("Ann", 0.4)] (some 3)

end AgentMemory
