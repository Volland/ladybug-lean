import Ladybug.Decode
import Ladybug.Cypher.Print

/-!
# Schema

Column types, the classes that describe node and relationship tables, and DDL
generation. Tables are declared from Lean structures with the `node_table` and
`rel_table` commands in `Ladybug.Schema.Command`.
-/

namespace Ladybug

inductive ColumnType where
  | bool | int8 | int16 | int32 | int64 | uint8 | uint16 | uint32 | uint64 | int128
  | float | double | string | blob | uuid | date | timestamp | interval
  | list (elem : ColumnType)
  /-- A fixed-size list, `FLOAT[n]`. -/
  | array (elem : ColumnType) (size : Nat)
  | struct (fields : List (String × ColumnType))
  deriving Repr, BEq, Inhabited

/-- The type as written in Ladybug DDL and reported by `table_info`. -/
partial def ColumnType.ddl : ColumnType → String
  | .bool => "BOOL" | .int8 => "INT8" | .int16 => "INT16" | .int32 => "INT32" | .int64 => "INT64"
  | .uint8 => "UINT8" | .uint16 => "UINT16" | .uint32 => "UINT32" | .uint64 => "UINT64"
  | .int128 => "INT128" | .float => "FLOAT" | .double => "DOUBLE" | .string => "STRING"
  | .blob => "BLOB" | .uuid => "UUID" | .date => "DATE" | .timestamp => "TIMESTAMP"
  | .interval => "INTERVAL"
  | .list e => e.ddl ++ "[]"
  | .array e n => s!"{e.ddl}[{n}]"
  | .struct fs => "STRUCT(" ++ ", ".intercalate (fs.map fun (k, t) => s!"{Cypher.quoteIdent k} {t.ddl}") ++ ")"

instance : ToString ColumnType := ⟨ColumnType.ddl⟩

/-- Lean types that can be stored in a column. `Option α` is a nullable column of `α`. -/
class CypherType (α : Type) where
  colType : ColumnType
  nullable : Bool := false

instance : CypherType Bool := ⟨.bool, false⟩
instance : CypherType Int8 := ⟨.int8, false⟩
instance : CypherType Int16 := ⟨.int16, false⟩
instance : CypherType Int32 := ⟨.int32, false⟩
instance : CypherType Int64 := ⟨.int64, false⟩
instance : CypherType UInt8 := ⟨.uint8, false⟩
instance : CypherType UInt16 := ⟨.uint16, false⟩
instance : CypherType UInt32 := ⟨.uint32, false⟩
instance : CypherType UInt64 := ⟨.uint64, false⟩
instance : CypherType Int := ⟨.int128, false⟩
instance : CypherType Float32 := ⟨.float, false⟩
instance : CypherType Float := ⟨.double, false⟩
instance : CypherType String := ⟨.string, false⟩
instance : CypherType ByteArray := ⟨.blob, false⟩
instance : CypherType Uuid := ⟨.uuid, false⟩
instance : CypherType Date := ⟨.date, false⟩
instance : CypherType Timestamp := ⟨.timestamp, false⟩
instance : CypherType Interval := ⟨.interval, false⟩
instance {α : Type} [CypherType α] : CypherType (Option α) := ⟨CypherType.colType α, true⟩
instance {α : Type} [CypherType α] : CypherType (Array α) := ⟨.list (CypherType.colType α), false⟩
instance {α : Type} [CypherType α] : CypherType (List α) := ⟨.list (CypherType.colType α), false⟩

/-- The result type of a projection function; lets generated code name a
field's type without printing it. -/
abbrev FieldType {σ τ : Type} (_ : σ → τ) : Type := τ

structure Column where
  name : String
  type : ColumnType
  nullable : Bool
  deriving Repr, BEq, Inhabited

def Column.of (name : String) (α : Type) [CypherType α] : Column :=
  ⟨name, CypherType.colType α, CypherType.nullable α⟩

/-- A Lean structure stored as a node table. -/
class NodeTable (α : Type) where
  label : String
  key : String
  columns : Array Column

/-- A Lean structure stored as a relationship table from `src` to `dst` nodes. -/
class RelTable (ρ : Type) (src dst : outParam Type) where
  label : String
  columns : Array Column

/-- A table in a schema, independent of its Lean type. -/
inductive TableDecl where
  | node (label key : String) (columns : Array Column)
  | rel (label src dst : String) (columns : Array Column)
  deriving Repr, Inhabited

def TableDecl.label : TableDecl → String
  | .node l .. | .rel l .. => l

def TableDecl.ofNode (α : Type) [NodeTable α] : TableDecl :=
  .node (NodeTable.label α) (NodeTable.key α) (NodeTable.columns α)

def TableDecl.ofRel (ρ : Type) {σ τ : Type} [RelTable ρ σ τ] [NodeTable σ] [NodeTable τ] : TableDecl :=
  .rel (RelTable.label ρ) (NodeTable.label σ) (NodeTable.label τ) (RelTable.columns ρ)

private def columnsDDL (cs : Array Column) : List String :=
  cs.toList.map fun c => s!"{Cypher.quoteIdent c.name} {c.type.ddl}"

-- @tg: implements:: [[openspec:graph-schema#DDL generation]]
def TableDecl.ddl : TableDecl → String
  | .node l k cs =>
    let parts := columnsDDL cs ++ [s!"PRIMARY KEY({Cypher.quoteIdent k})"]
    s!"CREATE NODE TABLE IF NOT EXISTS {Cypher.quoteIdent l}(" ++ ", ".intercalate parts ++ ")"
  | .rel l s d cs =>
    let parts := s!"FROM {Cypher.quoteIdent s} TO {Cypher.quoteIdent d}" :: columnsDDL cs
    s!"CREATE REL TABLE IF NOT EXISTS {Cypher.quoteIdent l}(" ++ ", ".intercalate parts ++ ")"

/-- The DDL of a node table. -/
def ddl (α : Type) [NodeTable α] : String := (TableDecl.ofNode α).ddl

/-- A set of tables. -/
abbrev Schema := List TableDecl

/-- DDL statements for a schema: node tables first, then relationship tables. -/
def Schema.ddl (s : Schema) : List String :=
  let nodes := s.filter fun | .node .. => true | _ => false
  let rels := s.filter fun | .rel .. => true | _ => false
  (nodes ++ rels).map TableDecl.ddl

/-- A difference between a declared schema and a database. -/
inductive SchemaDiff where
  | missingTable (label : String)
  | missingProperty (table property : String)
  | extraProperty (table property : String)
  | typeMismatch (table property expected actual : String)
  | keyMismatch (table expected actual : String)
  | endpointMismatch (table expected actual : String)
  | kindMismatch (table expected actual : String)
  deriving Repr, BEq, Inhabited

instance : ToString SchemaDiff where
  toString
    | .missingTable t => s!"table {t} is missing"
    | .missingProperty t p => s!"{t}.{p} is missing"
    | .extraProperty t p => s!"{t}.{p} is not declared"
    | .typeMismatch t p e a => s!"{t}.{p}: declared {e}, database has {a}"
    | .keyMismatch t e a => s!"{t}: declared key {e}, database key {a}"
    | .endpointMismatch t e a => s!"{t}: declared {e}, database {a}"
    | .kindMismatch t e a => s!"{t}: declared {e} table, database has {a}"

end Ladybug
