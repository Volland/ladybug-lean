import LadybugNative.Connection

/-!
# The native graph backend

`LbugM` as a `MonadGraph`: typed queries are printed, prepared once per
connection and query text, bound and decoded.
-/

namespace Ladybug

/-- Prepare `text` on the connection, reusing an earlier prepared statement. -/
def Connection.cachedPrepare (c : Connection) (text : String) : LbugIO FFI.Prepared := do
  if let some p := (← c.stmtCache.get).get? text then return p
  let p ← c.prepare text
  c.stmtCache.modify (·.insert text p.raw)
  return p.raw

/-- How many typed-query statements this connection has prepared. -/
def Connection.cachedStatements (c : Connection) : IO Nat := return (← c.stmtCache.get).size

private def runCore (core : Cypher.Core.Query) : LbugM ResultSet := do
  let c ← read
  let (text, params) := Cypher.print core
  executeRaw c.raw (← c.cachedPrepare text) params

private def decodeRows {α : Type} (decode : Row → Except Error α) (rs : ResultSet) : LbugM (Array α) :=
  rs.toRows.mapM fun r => match decode r with
    | .ok a => pure a
    | .error e => throw e

/-- Quote a table name inside a Cypher string literal (catalog procedures take names as strings). -/
private def strLit (s : String) : String := "'" ++ (s.replace "\\" "\\\\" |>.replace "'" "\\'") ++ "'"

/-- Normalize a type name for comparison: upper case, no spaces. -/
private def normType (s : String) : String := (String.ofList (s.toList.filter (· != ' '))).toUpper

private def columnDiffs (label : String) (declared : Array Column) (key : Option String) : LbugM (Array SchemaDiff) := do
  let rows ← queryRaw s!"CALL table_info({strLit label}) RETURN *"
  let col (name : String) : Option Nat := rows.columns.findIdx? (· == name)
  let some nameIdx := col "name" | throw (.query "table_info: no name column")
  let some typeIdx := col "type" | throw (.query "table_info: no type column")
  let pkIdx := col "primary key"
  let actual := rows.rows.map fun r =>
    let name := match r[nameIdx]? with | some (.string s) => s | _ => ""
    let ty := match r[typeIdx]? with | some (.string s) => s | _ => ""
    let pk := match pkIdx.bind (r[·]?) with | some (.bool b) => b | _ => false
    (name, ty, pk)
  let mut diffs := #[]
  for c in declared do
    match actual.find? (·.1 == c.name) with
    | none => diffs := diffs.push (.missingProperty label c.name)
    | some (_, ty, _) =>
      unless normType ty == normType c.type.ddl do
        diffs := diffs.push (.typeMismatch label c.name c.type.ddl ty)
  for (name, _, _) in actual do
    unless declared.any (·.name == name) do diffs := diffs.push (.extraProperty label name)
  if let some k := key then
    let dbKey := (actual.find? (·.2.2)).map (·.1) |>.getD ""
    unless dbKey == k do diffs := diffs.push (.keyMismatch label k dbKey)
  return diffs

-- @tg: implements:: [[openspec:graph-schema#Schema verification]]
def lbugVerifySchema (s : Schema) : LbugM (Array SchemaDiff) := do
  let tables ← queryRaw "CALL show_tables() RETURN name, type"
  let kinds := tables.rows.filterMap fun r => match r with
    | #[.string n, .string t] => some (n, t)
    | _ => none
  let mut diffs := #[]
  for d in s do
    match kinds.find? (·.1 == d.label), d with
    | none, _ => diffs := diffs.push (.missingTable d.label)
    | some (_, kind), .node label key cols =>
      if kind != "NODE" then diffs := diffs.push (.kindMismatch label "NODE" kind)
      else diffs := diffs ++ (← columnDiffs label cols (some key))
    | some (_, kind), .rel label src dst cols =>
      if kind != "REL" then diffs := diffs.push (.kindMismatch label "REL" kind)
      else
        diffs := diffs ++ (← columnDiffs label cols none)
        let conn ← queryRaw s!"CALL show_connection({strLit label}) RETURN *"
        let actual := conn.rows.map fun (r : Array Value) => match (r[0]? : Option Value), (r[1]? : Option Value) with
          | some (.string a), some (.string b) => s!"FROM {a} TO {b}"
          | _, _ => "?"
        let expected := s!"FROM {src} TO {dst}"
        unless actual.contains expected do
          diffs := diffs.push (.endpointMismatch label expected (", ".intercalate actual.toList))
  return diffs

private def copyInto (label path : String) : LbugM Unit := do
  if path.contains '\'' then throw (.custom s!"COPY paths cannot contain a quote: {path}")
  let opts := if path.endsWith ".csv" then " (header=true)" else ""
  exec s!"COPY {Cypher.quoteIdent label} FROM {strLit path}{opts}"

-- @tg: implements:: [[openspec:graph-orm#File import]]
/-- Load a node table from a CSV file with a header row, or a Parquet file,
whose columns are the table's. COPY takes no parameters, so the path is quoted
into the text and must not contain a quote. -/
def Repo.copyNodes (α : Type) [NodeTable α] (path : String) : LbugM Unit := copyInto (NodeTable.label α) path

/-- Load a relationship table from a CSV or Parquet file whose first two columns
are the source and destination keys. -/
def Repo.copyRels (ρ : Type) {σ τ : Type} [RelTable ρ σ τ] (path : String) : LbugM Unit :=
  copyInto (RelTable.label ρ) path

-- @tg: implements:: [[openspec:graph-monad#Native backend]]
instance : MonadGraph LbugM where
  runQuery q := do decodeRows q.decode (← runCore q.core)
  runStmt s := discard (runCore s.core)
  withTxMode := lbugWithTx
  applySchema s := for d in s.ddl do exec d
  verifySchema := lbugVerifySchema

end Ladybug
