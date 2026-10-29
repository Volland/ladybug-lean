import Ladybug

/-!
The Lean snippets shown on the website (`site/`), compiled with the test suite
so the site cannot drift from the library. Each namespace is one page.
-/

namespace Site.Index

open Ladybug

structure Person where
  id   : Int64
  name : String
  age  : Option Int64
  deriving Repr

structure Company where
  name : String

structure WorksAt where
  since : Int64

node_table Person
node_table Company (key := name)
rel_table WorksAt (from := Person) (to := Company)

#guard ddl Person == "CREATE NODE TABLE IF NOT EXISTS Person(id INT64, name STRING, age INT64, PRIMARY KEY(id))"
#guard (TableDecl.ofRel WorksAt).ddl == "CREATE REL TABLE IF NOT EXISTS WorksAt(FROM Person TO Company, since INT64)"

def employees : Query (String × Option String) :=
  cypher% MATCH (p:Person) OPTIONAL MATCH (p)-[:WorksAt]->(c:Company)
          RETURN p.name, c.name ORDER BY p.name

def seniors : Query String := query do
  let p ← match_ (node Person)
  where_ (p.age >. 60)
  return_ p.name

/-- error: unknown property 'nmae' of table Person; did you mean 'name'? -/
#guard_msgs in
example := cypher% MATCH (p:Person) RETURN p.nmae

/-- error: failed to synthesize instance of type class Matchable (PatOut Company.Var WorksAt (NodeRef Person)) -/
#guard_msgs (whitespace := lax, substring := true) in
example : Query String := query do
  let c ← match_ (node Company)
  let _ ← match_ (out c WorksAt (node Person))
  return_ c.name

def demo {m : Type → Type} [MonadGraph m] : m (Array (String × Option String)) := do
  applySchema [.ofNode Person, .ofNode Company, .ofRel WorksAt]
  Repo.insert (Person.mk 1 "Ann" (some 41))
  Repo.insert (Person.mk 2 "Bob" none)
  Repo.insert (Company.mk "ACME")
  Repo.link (1 : Int64) (WorksAt.mk 2020) "ACME"
  runQuery employees

#guard ((demo : MemM _).run' {}).toOption == some #[("Ann", some "ACME"), ("Bob", none)]

end Site.Index

namespace Site.Guide

open Ladybug

structure Person where
  id   : Int64
  name : String
  age  : Option Int64

structure Company where
  name    : String
  founded : Int32

structure WorksAt where
  since : Int64

structure Knows

node_table Person
node_table Company (key := name) (label := "Org")
rel_table WorksAt (from := Person) (to := Company)
rel_table Knows (from := Person) (to := Person)

def schema : Schema := [.ofNode Person, .ofNode Company, .ofRel WorksAt, .ofRel Knows]

def colleagues : Query (String × String × Int64) := query do
  let p ← match_ (node Person)
  let (w, c) ← match_ (out p WorksAt (node Company))
  where_ (w.since >=. 2020 &&. c.founded <. 2000)
  orderBy p.name
  limit 10
  return_ (p.name, c.name, w.since)

#guard colleagues.text == "MATCH (n0:Person) MATCH (n0)-[r1:WorksAt]->(n2:Org) WHERE (r1.since >= $p0) AND (n2.founded < $p1) RETURN n0.name, n2.name, r1.since ORDER BY n0.name LIMIT $p2"

def birthday (pid : Int64) : Statement := stmt do
  let p ← match_ (node Person)
  where_ (p.id ==. lit pid)
  set p.age (p.age +. 1)

example (p : Person.Var) : Expr (Option Bool) := p.age >. 30 ||. p.name ==. lit "Ann"
example (p : Person.Var) : Expr Int64 := coalesce p.age 0
example (p : Person.Var) : Expr Bool := isTrue (p.age >. 30)

def minAge : Int64 := 30

def adults : Query (String × String × Int64) := cypher%
  MATCH (p:Person)-[w:WorksAt]->(c:Org)
  WHERE p.age > $minAge AND c.name STARTS WITH "A"
  RETURN p.name, c.name, w.since ORDER BY w.since DESC LIMIT 5

def repoTour {m : Type → Type} [MonadGraph m] : m Unit := do
  let ann : Person := ⟨1, "Ann", some 30⟩
  Repo.insert ann
  Repo.upsert { ann with name := "Ann B." }
  let _ann? ← Repo.get? Person (1 : Int64)
  let _seniors ← Repo.findWhere Person fun p => p.age >. 60
  Repo.update { ann with age := some 31 }
  Repo.insert (Company.mk "ACME" 1990)
  Repo.link (1 : Int64) (WorksAt.mk 2020) "ACME"
  let _jobs : Array (Company × WorksAt) ← Repo.outgoing WorksAt (1 : Int64)
  let _staff : Array (Person × WorksAt) ← Repo.incoming WorksAt "ACME"
  let _rels ← Repo.between WorksAt (1 : Int64) "ACME"
  Repo.unlink WorksAt (1 : Int64) "ACME"
  Repo.detachDelete Person (1 : Int64)
  Repo.insertMany #[ann] (batchSize := 1000)
  Repo.upsertMany #[ann]
  Repo.linkMany #[((1 : Int64), WorksAt.mk 2020, "ACME")]

#guard ((do applySchema schema; repoTour; Repo.findAll Person : MemM _).run' {}).toOption.map (·.size) == some 1

def friends : Query (String × Int64) := query do
  let p ← match_ (node Person)
  let (path, friend) ← matchPaths p Knows (node Person) (max := 3)
  return_ (friend.name, pathLength path)

def employed : Query String := query do
  let p ← match_ (node Person)
  where_ (← exists_ (discard (match_ (out p WorksAt (node Company)))))
  let reports ← countSub (discard (match_ (inc p Knows (node Person))))
  where_ (reports >. 0)
  return_ p.name

def onboard {m : Type → Type} [MonadGraph m] (p : Person) : m Unit := withTx do
  Repo.upsert p
  Repo.link p.id (WorksAt.mk 2026) "ACME"

def onboarded : MemM (Array Person) := do
  applySchema schema
  Repo.insert (Company.mk "ACME" 1990)
  onboard ⟨3, "Cid", none⟩
  Repo.findAll Person

#guard (onboarded.run' {}).toOption.map (·.size) == some 1

end Site.Guide

namespace Site.Search

open Ladybug

structure Doc where
  id   : Int64
  text : String
  emb  : Embedding 384

node_table Doc

def hits (queryEmbedding : Embedding 384) : QueryM (Ret (String × Float)) := do
  let (d, dist) ← vectorSearch Doc "doc_vec" queryEmbedding (k := 10)
  where_ (d.id >. 100)
  orderBy dist
  return_ (d.text, dist)

def found : QueryM (Ret Int64) := do
  let (d, score) ← ftsSearch Doc "doc_fts" "graph memory"
  orderByDesc score
  return_ d.id

example : Statement := createVectorIndex Doc "doc_vec" "emb" (metric := .cosine)
example : Statement := createFtsIndex Doc "doc_fts" ["text"]

end Site.Search

namespace Site.Book

open Ladybug

structure Person where
  id   : Int64
  name : String
  age  : Option Int64

structure Company where
  name : String

structure WorksAt where
  since : Int64

node_table Person
node_table Company (key := name)
rel_table WorksAt (from := Person) (to := Company)

def schema : Schema := [.ofNode Person, .ofNode Company, .ofRel WorksAt]

def withEmployer : Query (String × Option String) := query do
  let p ← match_ (node Person)
  let (_, c) ← optMatch (out p WorksAt (node Company))
  return_ (p.name, c.name)

def viaBuilder : Query (String × String) := query do
  let p ← match_ (node Person)
  let (_, c) ← match_ (out p WorksAt (node Company))
  return_ (p.name, c.name)

def viaCypher := cypher% MATCH (p:Person)-[:WorksAt]->(c:Company) RETURN p.name, c.name

#guard viaBuilder.print == viaCypher.print

#guard (do applySchema schema; Repo.insert (Person.mk 1 "Ann" none);
           Repo.findAll Person : MemM _).run'.toOption.map (·.size) == some 1

structure Entity where
  name : String

structure Memory where
  id : Int64
  text : String
  embedding : Embedding 4

structure Mentions where
  weight : Option Float

node_table Entity (key := name)
node_table Memory
rel_table Mentions (from := Memory) (to := Entity)

def recallAnn (thought : Embedding 4) : Query (String × Float) := query do
  let (mem, dist) ← vectorSearch Memory "memory_vec" thought 20
  where_ (← exists_ do
    let (_, e) ← match_ (out mem Mentions (node Entity))
    where_ (e.name ==. lit "Ann"))
  orderBy dist
  limit 5
  return_ (mem.text, dist)

end Site.Book
