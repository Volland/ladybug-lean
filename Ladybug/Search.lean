import Ladybug.Cypher.Builder

/-!
# Vector and full-text search

```lean
structure Doc where
  id : Int64
  text : String
  emb : Embedding 3

node_table Doc

runStmt (createVectorIndex Doc "doc_vec" "emb")
let hits ← runQueryM do
  let (d, dist) ← vectorSearch Doc "doc_vec" q (k := 5)
  return_ (d.id, dist)
```
The native backend loads the `vector` and `fts` extensions on first use.
-/

namespace Ladybug

open Cypher

variable {α V O : Type} {n : Nat}

/-- A fixed-length vector stored in a `FLOAT[n]` column. -/
structure Embedding (n : Nat) where
  data : Array Float32
  size_eq : data.size = n

instance : Repr (Embedding n) := ⟨fun e _ => repr e.data⟩
instance : Inhabited (Embedding n) := ⟨⟨Array.replicate n 0, Array.size_replicate⟩⟩
instance : BEq (Embedding n) := ⟨fun a b => a.data == b.data⟩

-- @tg: implements:: [[openspec:graph-search#Embedding columns]]
/-- An embedding from exactly `n` floats, or `none` for any other length. -/
def Embedding.ofArray? (xs : Array Float) : Option (Embedding n) :=
  let data := xs.map Float.toFloat32
  if h : data.size = n then some ⟨data, h⟩ else none

instance : CypherType (Embedding n) := ⟨.array .float n, false⟩

instance : ToValue (Embedding n) := ⟨fun e => .array (e.data.map .float)⟩

instance : FromValue (Embedding n) where
  typeName := s!"Embedding {n}"
  fromValue? v := do
    let xs ← match v with | .array xs | .list xs => some xs | _ => none
    let fs ← xs.mapM fun | .float f => some f | .double d => some d.toFloat32 | _ => none
    if h : fs.size = n then some ⟨fs, h⟩ else none

inductive Metric where
  | cosine | l2 | l2sq | dotProduct
  deriving Repr, BEq, Inhabited

def Metric.text : Metric → String
  | .cosine => "cosine" | .l2 => "l2" | .l2sq => "l2sq" | .dotProduct => "dotproduct"

private def callStmt (proc : String) (args : List Core.Expr) (named : List (String × Core.Expr) := []) : Statement :=
  ⟨⟨#[.call proc args named []]⟩⟩

-- @tg: implements:: [[openspec:graph-search#Vector index]]
/-- Create a vector index on an embedding column. -/
def createVectorIndex (α : Type) [NodeTable α] (index column : String) (metric : Metric := .cosine) : Statement :=
  callStmt "CREATE_VECTOR_INDEX" [.name (NodeTable.label α), .name index, .name column]
    [("metric", .name metric.text)]

def dropVectorIndex (α : Type) [NodeTable α] (index : String) : Statement :=
  callStmt "DROP_VECTOR_INDEX" [.name (NodeTable.label α), .name index]

/-- The `k` nodes nearest to `q`, with their distances; the query vector is a parameter. -/
def vectorSearch (α : Type) [NodeTable α] [HasVar α V O] (index : String) (q : Embedding n) (k : Nat) :
    QueryM (V × Expr Float) := do
  let nv ← QueryM.fresh "n"
  let dv ← QueryM.fresh "v"
  QueryM.emit (.call "QUERY_VECTOR_INDEX"
    [.name (NodeTable.label α), .name index, .value (toValue q), .value (.int64 (Int64.ofNat k))] []
    [("node", nv), ("distance", dv)])
  return (HasVar.mkVar α nv, ⟨.var dv⟩)

-- @tg: implements:: [[openspec:graph-search#Full-text index]]
/-- Create a full-text index over string columns. -/
def createFtsIndex (α : Type) [NodeTable α] (index : String) (columns : List String) : Statement :=
  callStmt "CREATE_FTS_INDEX" [.name (NodeTable.label α), .name index, .list (columns.map .name)]

def dropFtsIndex (α : Type) [NodeTable α] (index : String) : Statement :=
  callStmt "DROP_FTS_INDEX" [.name (NodeTable.label α), .name index]

/-- The nodes matching a text query, with their relevance scores. -/
def ftsSearch (α : Type) [NodeTable α] [HasVar α V O] (index : String) (q : String) :
    QueryM (V × Expr Float) := do
  let nv ← QueryM.fresh "n"
  let sv ← QueryM.fresh "v"
  QueryM.emit (.call "QUERY_FTS_INDEX" [.name (NodeTable.label α), .name index, .value (.string q)] []
    [("node", nv), ("score", sv)])
  return (HasVar.mkVar α nv, ⟨.var sv⟩)

/-- The extensions a query needs, by the procedures it calls. -/
def Cypher.Core.Query.extensions (q : Core.Query) : List String :=
  let procs := q.clauses.toList.filterMap fun | .call p .. => some p | _ => none
  (if procs.any (fun p => (p.splitOn "VECTOR_INDEX").length > 1) then ["vector"] else []) ++
  (if procs.any (fun p => (p.splitOn "FTS_INDEX").length > 1) then ["fts"] else [])

end Ladybug
