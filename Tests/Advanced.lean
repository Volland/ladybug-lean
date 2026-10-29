import Tests.Framework
import Tests.Fixtures

/-! Tests for paths, subqueries, unions, search, timeouts and interruption. -/

namespace Tests.Advanced

open Ladybug Tests.Fixtures

structure Doc where
  id : Int64
  txt : String
  emb : Embedding 3

node_table Doc

def withSchema {α : Type} (m : LbugM α) : IO α := inMem do
  applySchema schema
  m

def persons (ids : List Int64) : LbugM Unit := for i in ids do Repo.insert (Person.mk i s!"p{i}" none)

def knows (edges : List (Int64 × Int64)) : LbugM Unit := for (a, b) in edges do Repo.link a Knows.mk b

/-! ## Variable-length and shortest paths -/

-- @tg: verifies:: [[openspec:cypher-query#Variable-length paths#Friends within three hops]] {level: integration}
def friendsWithinHops : IO Unit := do
  let ids ← withSchema do
    persons [1, 2, 3, 4]
    knows [(1, 2), (2, 3), (3, 4)]
    runQueryM do
      let a ← match_ (node Person)
      let (_, b) ← matchPaths a Knows (node Person) (max := 2)
      where_ (a.id ==. 1)
      return_ b.id (distinct := true)
  assertEq (ids.toList.mergeSort) [2, 3] "reachable"

-- @tg: verifies:: [[openspec:cypher-query#Variable-length paths#Path decoding]] {level: integration}
def pathDecoding : IO Unit := do
  let rows ← withSchema do
    persons [1, 2, 3, 4]
    knows [(1, 2), (2, 3), (3, 4)]
    runQueryM do
      let a ← match_ (node Person)
      let (path, b) ← matchPaths a Knows (node Person) (max := 2)
      where_ (a.id ==. 1 &&. b.id ==. 3)
      return_ (path, pathLength path)
  match rows with
  | #[(path, len)] =>
    assertEq (path.nodes.map (·.id)) #[1, 2, 3] "nodes"
    assertEq path.rels.size 2 "rels"
    assertEq len 2 "length"
  | _ => fail s!"rows: {rows.size}"

-- @tg: verifies:: [[openspec:cypher-query#Shortest paths#Shortest path]] {level: integration}
def shortest : IO Unit := do
  let rows ← withSchema do
    persons [1, 2, 3, 4, 5]
    knows [(1, 2), (2, 4), (1, 3), (3, 5), (5, 4)]
    runQueryM do
      let a ← match_ (node Person)
      let (path, b) ← shortestPath a Knows (node Person) (max := 5)
      where_ (a.id ==. 1 &&. b.id ==. 4)
      return_ (path, pathLength path)
  match rows with
  | #[(path, len)] =>
    assertEq (path.nodes.map (·.id)) #[1, 2, 4] "nodes"
    assertEq len 2 "length"
  | _ => fail s!"rows: {rows.size}"

-- @tg: verifies:: [[openspec:cypher-query#Shortest paths#All shortest]] {level: integration}
def allShortest : IO Unit := do
  let rows ← withSchema do
    persons [1, 2, 3, 4]
    knows [(1, 2), (2, 4), (1, 3), (3, 4)]
    runQueryM do
      let a ← match_ (node Person)
      let (path, b) ← allShortestPaths a Knows (node Person) (max := 5)
      where_ (a.id ==. 1 &&. b.id ==. 4)
      return_ path
  let middles := rows.toList.filterMap (fun (p : Path Person Knows) => p.nodes[1]?.map (·.id)) |>.mergeSort
  assertEq middles [2, 3] "paths through"

/-! ## Subqueries -/

-- @tg: verifies:: [[openspec:cypher-query#Subqueries#Exists filter]] {level: integration}
def existsFilter : IO Unit := do
  let ids ← withSchema do
    persons [1, 2, 3]
    Repo.insert (Company.mk "ACME" 1990)
    Repo.link (2 : Int64) (WorksAt.mk 2020) "ACME"
    runQueryM do
      let p ← match_ (node Person)
      where_ (← exists_ (discard (match_ (out p WorksAt (node Company)))))
      return_ p.id
  assertEq ids #[2] "employed"

-- @tg: verifies:: [[openspec:cypher-query#Subqueries#Count subquery]] {level: integration}
def countSubquery : IO Unit := do
  let rows ← withSchema do
    persons [1, 2, 3]
    knows [(1, 2), (1, 3), (2, 3)]
    runQueryM do
      let p ← match_ (node Person)
      let n ← countSub (discard (match_ (out p Knows (node Person))))
      orderBy p.id
      return_ (p.id, n)
  check (rows == #[(1, 2), (2, 1), (3, 0)]) s!"rows: {rows}"

/-! ## Union -/

def letters (xs : List String) : Query String := query do
  let x ← unwind (Expr.list (xs.map lit))
  return_ x

-- @tg: verifies:: [[openspec:cypher-query#Union#Union removes duplicates]] {level: integration}
def unionDuplicates : IO Unit := do
  let (u, ua) ← inMem do
    let u ← runQuery ((letters ["a", "b"]).union (letters ["b", "c"]))
    let ua ← runQuery ((letters ["a", "b"]).unionAll (letters ["b", "c"]))
    return (u, ua)
  assertEq u.toList.mergeSort ["a", "b", "c"] "UNION"
  assertEq ua.toList.mergeSort ["a", "b", "b", "c"] "UNION ALL"

-- @tg: verifies:: [[openspec:cypher-query#Union#Mismatched result types rejected]] {level: unit}
/-- error: failed to synthesize instance of type class Returnable (Expr Int64) String -/
#guard_msgs (whitespace := lax, substring := true) in
example : Query String := (letters ["a"]).union (query do let p ← match_ (node Person); return_ p.id)

-- @tg: verifies:: [[openspec:cypher-query#Variable-length paths#Unbounded pattern rejected]] {level: unit}
/-- error: Application type mismatch: The argument fun max => -/
#guard_msgs (whitespace := lax, substring := true) in
example : Statement := stmt do
  let a ← match_ (node Person)
  discard (matchPaths a Knows (node Person))

/-! ## cypher% -/

-- @tg: verifies:: [[openspec:cypher-syntax#Advanced clauses in syntax#Variable-length in syntax]] {level: unit}
def variableLengthSyntax : IO Unit := do
  let viaSyntax : Query Int64 := cypher% MATCH (a:Person)-[:Knows*1..2]->(b:Person) WHERE a.id = 1 RETURN b.id
  let viaBuilder : Query Int64 := query do
    let a ← match_ (node Person)
    let (_, b) ← matchPaths a Knows (node Person) (max := 2)
    where_ (a.id ==. 1)
    return_ b.id
  check (viaSyntax.print == viaBuilder.print) s!"{viaSyntax.text}\n vs {viaBuilder.text}"

-- @tg: verifies:: [[openspec:cypher-syntax#Advanced clauses in syntax#Union in syntax]] {level: unit}
/-- error: failed to synthesize instance of type class Returnable (Expr Int64) String -/
#guard_msgs (whitespace := lax, substring := true) in
example := cypher% MATCH (p:Person) RETURN p.name UNION MATCH (p:Person) RETURN p.id

/-- More `cypher%` forms: paths, shortest paths, subqueries, UNION ALL and search calls. -/
example : Query (Path Person Knows) := cypher% MATCH p = (a:Person)-[:Knows* SHORTEST 1..4]->(b:Person) RETURN p
example : Query Int64 := cypher% MATCH (p:Person) WHERE EXISTS { MATCH (p)-[:WorksAt]->(c:Company) WHERE c.founded > 1900 } RETURN p.id
example : Query (Int64 × Int64) := cypher% MATCH (p:Person) RETURN p.id, COUNT { MATCH (p)-[:Knows]->(q:Person) }
example : Query String := cypher% MATCH (p:Person) RETURN p.name UNION ALL MATCH (c:Company) RETURN c.name
example (q : Embedding 3) : Query (Int64 × Float) :=
  cypher% CALL QUERY_VECTOR_INDEX("Doc", "doc_vec", $q, 2) YIELD node AS d, distance AS dist RETURN d.id, dist

/-! ## Search -/

def emb (xs : List Float) : Embedding 3 := (Embedding.ofArray? xs.toArray).get!

def docs : List Doc := [⟨1, "graph databases are fast", emb [1, 0, 0]⟩, ⟨2, "lean is a prover", emb [0, 1, 0]⟩,
  ⟨3, "graph theory", emb [0.9, 0.1, 0]⟩]

def withDocs {α : Type} (m : LbugM α) : IO α := inMem do
  applySchema [.ofNode Doc]
  for d in docs do Repo.insert d
  m

-- @tg: verifies:: [[openspec:graph-search#Embedding columns#Embedding column DDL]] {level: unit}
def embeddingDDL : IO Unit := do
  check (((ddl Doc).splitOn "emb FLOAT[3]").length > 1) s!"ddl: {ddl Doc}"

-- @tg: verifies:: [[openspec:graph-search#Embedding columns#Wrong length]] {level: unit}
def embeddingWrongLength : IO Unit :=
  check (Embedding.ofArray? (n := 3) #[1, 2, 3, 4]).isNone "a 4-element embedding of size 3 was built"

-- @tg: verifies:: [[openspec:graph-search#Vector index#Nearest neighbours]] {level: integration}
def nearestNeighbours : IO Unit := do
  let rows ← withDocs do
    runStmt (createVectorIndex Doc "doc_vec" "emb")
    runQueryM do
      let (d, dist) ← vectorSearch Doc "doc_vec" (emb [1, 0, 0]) 2
      orderBy dist
      return_ d.id
  assertEq rows #[1, 3] "nearest"

-- @tg: verifies:: [[openspec:graph-search#Vector index#Filtered vector search]] {level: integration}
def filteredVectorSearch : IO Unit := do
  let rows ← withDocs do
    runStmt (createVectorIndex Doc "doc_vec" "emb")
    runQueryM do
      let (d, _) ← vectorSearch Doc "doc_vec" (emb [1, 0, 0]) 2
      where_ (d.id >. 1)
      return_ d.id
  assertEq rows #[3] "filtered"

-- @tg: verifies:: [[openspec:graph-search#Full-text index#Keyword search]] {level: integration}
def keywordSearch : IO Unit := do
  let rows ← withDocs do
    runStmt (createFtsIndex Doc "doc_fts" ["txt"])
    runQueryM do
      let (d, score) ← ftsSearch Doc "doc_fts" "graph"
      orderByDesc score
      return_ (d.id, score)
  assertEq (rows.toList.map (·.1) |>.mergeSort) [1, 3] "matches"
  check (rows.all (·.2 > 0)) s!"scores: {rows}"

-- @tg: verifies:: [[openspec:graph-search#Extensions#Automatic loading]] {level: integration}
def automaticLoading : IO Unit := do
  let rows ← withDocs do
    runStmt (createVectorIndex Doc "doc_vec" "emb")
    runQuery (cypher% CALL QUERY_VECTOR_INDEX("Doc", "doc_vec", $(emb [0, 1, 0]), 1) YIELD node AS d, distance AS dist
                      RETURN d.id)
  assertEq rows #[2] "nearest"

/-! ## Timeouts and interruption -/

private def slowSetup : LbugM Unit := do
  exec "CREATE NODE TABLE N(id INT64, PRIMARY KEY(id))"
  exec "UNWIND range(1, 40000) AS i CREATE (:N {id: i})"

private def slowQuery : LbugM Unit :=
  discard (queryRaw "MATCH (a:N), (b:N) WHERE (a.id * b.id) % 7 = 3 RETURN count(*)")

-- @tg: verifies:: [[openspec:native-connection#Timeouts and interruption#Timeout]] {level: integration}
def timeout : IO Unit := do
  let (err, after) ← inMem do
    slowSetup
    let err ← try withTimeout 50 slowQuery; pure none catch e => pure (some e)
    return (err, ← queryAs Int64 "RETURN 1")
  check (match err with | some (.timeout _) => true | _ => false) s!"error: {err}"
  assertEq after #[1] "next query"

-- @tg: verifies:: [[openspec:native-connection#Timeouts and interruption#Interrupt from another task]] {level: integration}
def interruptFromTask : IO Unit := do
  let err ← inMem do
    slowSetup
    let c ← read
    let task ← IO.asTask (do IO.sleep 100; c.interrupt)
    let err ← try slowQuery; pure none catch e => pure (some e)
    discard (IO.wait task)
    return err
  check (match err with | some (.interrupted _) => true | _ => false) s!"error: {err}"

def tests : List Test := [
  ⟨"cypher-query: friends within hops", friendsWithinHops⟩,
  ⟨"cypher-query: path decoding", pathDecoding⟩,
  ⟨"cypher-query: shortest path", shortest⟩,
  ⟨"cypher-query: all shortest paths", allShortest⟩,
  ⟨"cypher-query: exists filter", existsFilter⟩,
  ⟨"cypher-query: count subquery", countSubquery⟩,
  ⟨"cypher-query: union removes duplicates", unionDuplicates⟩,
  ⟨"cypher-syntax: variable-length in syntax", variableLengthSyntax⟩,
  ⟨"graph-search: embedding column DDL", embeddingDDL⟩,
  ⟨"graph-search: embedding of wrong length", embeddingWrongLength⟩,
  ⟨"graph-search: nearest neighbours", nearestNeighbours⟩,
  ⟨"graph-search: filtered vector search", filteredVectorSearch⟩,
  ⟨"graph-search: keyword search", keywordSearch⟩,
  ⟨"graph-search: automatic extension loading", automaticLoading⟩,
  ⟨"native-connection: timeout", timeout⟩,
  ⟨"native-connection: interrupt from another task", interruptFromTask⟩
]

end Tests.Advanced
