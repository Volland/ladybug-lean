import Ladybug
import LadybugNative.FFI
import Std.Data.HashMap

/-!
# Native backend

Databases, connections, Cypher execution with parameters, transactions and the
`LbugM` runtime monad, over the Ladybug C API.

```lean
def main : IO Unit := Ladybug.withDatabase ":memory:" fun db => db.withConnection do
  let rows ← Ladybug.queryAs (String × Int64) "RETURN 'a' AS s, 1 AS n"
  IO.println rows
```
-/

namespace Ladybug

/-- Database options; zero means Ladybug's default. -/
structure Config where
  bufferPoolSize : UInt64 := 0
  maxThreads : UInt64 := 0
  readOnly : Bool := false
  maxDbSize : UInt64 := 0
  deriving Repr, Inhabited

/-- IO that fails with a `Ladybug.Error`. -/
abbrev LbugIO := ExceptT Error IO

/-- The Ladybug library version, e.g. `"0.22.1"`. -/
def version : IO String := FFI.version

/-- The storage version of the linked library. -/
def storageVersion : IO Nat := return (← FFI.storageVersion).toNat

structure Database where
  raw : FFI.Database
  path : String
  config : Config

/-- Read `N` from Ladybug's "Database file version: N" message. -/
private def fileVersionOf (msg : String) : Option Nat :=
  match msg.splitOn "Database file version: " with
  | [_, rest] => (rest.takeWhile Char.isDigit).toString.toNat?
  | _ => none

-- @tg: implements:: [[openspec:native-connection#Open database]]
-- @tg: implements:: [[openspec:native-library#Storage version check]]
/-- Open a database at `path`, or an in-memory one for `":memory:"`. A database
written by another storage version is refused with `.storageMismatch`, and its
files are left untouched. -/
def Database.open (path : String) (config : Config := {}) : LbugIO Database := do
  match ← FFI.dbOpen path config.bufferPoolSize config.maxThreads config.readOnly config.maxDbSize with
  | .ok raw => return ⟨raw, path, config⟩
  | .error msg =>
    if (msg.splitOn "different version").length > 1 then
      throw (.storageMismatch (fileVersionOf msg) (← storageVersion) msg)
    throw (.open msg)

structure Connection where
  raw : FFI.Connection
  database : Database
  /-- Whether a transaction bracket is open on this connection. -/
  inTx : IO.Ref Bool
  /-- Prepared statements of typed queries, by query text. -/
  stmtCache : IO.Ref (Std.HashMap String FFI.Prepared)

def Database.connect (db : Database) : LbugIO Connection := do
  match ← FFI.connOpen db.raw with
  | .ok raw => return ⟨raw, db, ← IO.mkRef false, ← IO.mkRef {}⟩
  | .error msg => throw (.open msg)

/-- All rows of one statement's result. -/
structure ResultSet where
  columns : Array String
  rows : Array (Array Value)
  deriving Inhabited

def ResultSet.toRows (r : ResultSet) : Array Row := r.rows.map (⟨r.columns, ·⟩)

/-- The Ladybug message for a missing parameter is "Parameter x not found." -/
private def missingParam? (msg : String) : Option String :=
  match msg.splitOn "Parameter " with
  | [_, rest] => match rest.splitOn " not found" with
    | [name, _] => some name
    | _ => none
  | _ => none

private def queryError (msg : String) : Error :=
  match missingParam? msg with
  | some p => .bind p msg
  | none => .query msg

private partial def drain (r : FFI.Result) : LbugIO ResultSet := do
  let columns ← FFI.resultColumns r
  let rec loop (acc : Array (Array Value)) : LbugIO (Array (Array Value)) := do
    match ← FFI.resultNext r with
    | .error msg => throw (.query msg)
    | .ok none => return acc
    | .ok (some row) => loop (acc.push row)
  return ⟨columns, ← loop #[]⟩

/-- Every statement's result of a (possibly multi-statement) query, in order. -/
private partial def drainAll (r : FFI.Result) : LbugIO (Array ResultSet) := do
  let first ← drain r
  match ← FFI.resultNextResult r with
  | none => return #[first]
  | some (.error msg) => throw (queryError msg)
  | some (.ok next) => return #[first] ++ (← drainAll next)

/-! ## Parameters -/

/-- Encode a value as a native parameter. Nodes, relationships and paths cannot
be parameters. -/
partial def toNative : Value → Except String FFI.NValue
  | .null => .ok (FFI.nvNull ())
  | .bool b => .ok (FFI.nvBool b)
  | .int8 v => .ok (FFI.nvInt8 v) | .int16 v => .ok (FFI.nvInt16 v)
  | .int32 v => .ok (FFI.nvInt32 v) | .int64 v => .ok (FFI.nvInt64 v)
  | .uint8 v => .ok (FFI.nvUInt8 v) | .uint16 v => .ok (FFI.nvUInt16 v)
  | .uint32 v => .ok (FFI.nvUInt32 v) | .uint64 v => .ok (FFI.nvUInt64 v)
  | .int128 v =>
    let lo := UInt64.ofNat (v % 18446744073709551616).toNat
    let hi := Int64.ofInt (v / 18446744073709551616)
    .ok (FFI.nvInt128 lo hi)
  | .float v => .ok (FFI.nvFloat v)
  | .double v => .ok (FFI.nvDouble v)
  | .decimal d =>
    let digits := d.toList.filter Char.isDigit
    let scale := match d.splitOn "." with | [_, frac] => frac.length | _ => 0
    .ok (FFI.nvDecimal d (UInt32.ofNat (max digits.length 1)) (UInt32.ofNat scale))
  | .string s => .ok (FFI.nvString s)
  | .blob b => .ok (FFI.nvBlob b)
  | .uuid u => .ok (FFI.nvUuid u)
  | .date d => .ok (FFI.nvDate d)
  | .timestamp t => .ok (FFI.nvTimestamp t)
  | .timestampNs t => .ok (FFI.nvTimestampNs t)
  | .timestampMs t => .ok (FFI.nvTimestampMs t)
  | .timestampSec t => .ok (FFI.nvTimestampSec t)
  | .timestampTz t => .ok (FFI.nvTimestampTz t)
  | .interval m d u => .ok (FFI.nvInterval m d u)
  | .internalId i => .ok (FFI.nvInternalId i.table i.offset)
  | .list xs | .array xs => do FFI.nvList (← xs.mapM toNative)
  | .struct fs => do FFI.nvStruct (fs.map (·.1)) (← fs.mapM (toNative ·.2))
  | .map es => do FFI.nvMap (← es.mapM (toNative ·.1)) (← es.mapM (toNative ·.2))
  | .union _ v => toNative v
  | v => .error s!"a {v.kind} value cannot be a query parameter"

/-- Named query parameters. -/
abbrev Params := Array (String × Value)

/-- A named parameter from any encodable Lean value. -/
def param {α : Type} [ToValue α] (name : String) (x : α) : String × Value := (name, toValue x)

/-! ## Prepared statements -/

structure Prepared where
  raw : FFI.Prepared
  conn : Connection
  text : String

namespace Connection

def prepare (c : Connection) (text : String) : LbugIO Prepared := do
  match ← FFI.connPrepare c.raw text with
  | .ok raw => return ⟨raw, c, text⟩
  | .error msg => throw (.prepare msg)

-- @tg: implements:: [[openspec:native-connection#Run Cypher text]]
/-- Run Cypher text with one or more statements and return every statement's result. -/
def queryAll (c : Connection) (text : String) : LbugIO (Array ResultSet) := do
  match ← FFI.connQuery c.raw text with
  | .ok r => drainAll r
  | .error msg => throw (queryError msg)

end Connection

-- @tg: implements:: [[openspec:native-connection#Prepared parameters]]
/-- Bind parameters to a native statement and run it on a connection. -/
def executeRaw (conn : FFI.Connection) (stmt : FFI.Prepared) (params : Params) : LbugIO ResultSet := do
  for (name, v) in params do
    let nv ← match toNative v with
      | .ok nv => pure nv
      | .error msg => throw (Error.bind name msg)
    match ← FFI.stmtBind stmt name nv with
    | .ok () => pure ()
    | .error msg => throw (.bind name msg)
  match ← FFI.connExecute conn stmt with
  | .ok r => drain r
  | .error msg => throw (queryError msg)

/-- Bind the parameters and run the statement. Values are always sent as
parameters, never spliced into the text. -/
def Prepared.execute (p : Prepared) (params : Params := #[]) : LbugIO ResultSet :=
  executeRaw p.conn.raw p.raw params

namespace Connection

/-- Run a query and return the last statement's result. With parameters the
text must be a single statement. -/
def query (c : Connection) (text : String) (params : Params := #[]) : LbugIO ResultSet := do
  if params.isEmpty then
    let all ← c.queryAll text
    return all.back?.getD default
  (← c.prepare text).execute params

def exec (c : Connection) (text : String) (params : Params := #[]) : LbugIO Unit :=
  discard <| c.query text params

end Connection

/-! ## The runtime monad -/

/-- The native runtime monad: a connection, `Ladybug.Error`s and IO. -/
abbrev LbugM := ReaderT Connection (ExceptT Error IO)

/-- Run Cypher text on the current connection; the last statement's result. -/
def queryRaw (text : String) (params : Params := #[]) : LbugM ResultSet := do
  (← read).query text params

/-- Run Cypher text and decode every row of the last statement's result. -/
def queryAs (α : Type) [FromRow α] (text : String) (params : Params := #[]) : LbugM (Array α) := do
  let rs ← queryRaw text params
  rs.toRows.mapM fun r => match FromRow.decode r with
    | .ok a => pure a
    | .error e => throw e

/-- Run Cypher text for its effect. -/
def exec (text : String) (params : Params := #[]) : LbugM Unit := do
  (← read).exec text params

-- @tg: implements:: [[openspec:native-connection#Transactions]]
/-- Run `body` in a transaction that commits when it succeeds and rolls back
when it fails with a `Ladybug.Error` or an IO error. Nested brackets on one
connection are rejected. -/
def lbugWithTx {α : Type} (mode : TxMode) (body : LbugM α) : LbugM α := fun c => ExceptT.mk do
  let rollback : IO Unit := do discard (c.exec "ROLLBACK").run; c.inTx.set false
  if ← c.inTx.get then
    return .error (.transaction "a transaction is already open on this connection")
  let begin := match mode with
    | .readWrite => "BEGIN TRANSACTION"
    | .readOnly => "BEGIN TRANSACTION READ ONLY"
  if let .error e ← (c.exec begin).run then
    return .error (.transaction e.message)
  c.inTx.set true
  let res ← try (body c).run catch ioe => do rollback; throw ioe
  match res with
  | .error e => rollback; return .error e
  | .ok a =>
    match ← (c.exec "COMMIT").run with
    | .ok () => c.inTx.set false; return .ok a
    | .error e => rollback; return .error (.transaction e.message)

/-! ## Entry points -/

/-- Fail in `IO` with the error's message. -/
def LbugIO.toIO {α : Type} (m : LbugIO α) : IO α := do
  match ← m.run with
  | .ok a => return a
  | .error e => throw (IO.userError (toString e))

def Database.withConnection {α : Type} (db : Database) (m : LbugM α) : LbugIO α := do
  m (← db.connect)

/-- Open a database, run `f`, and fail in `IO` on any `Ladybug.Error`. -/
def withDatabase {α : Type} (path : String) (f : Database → LbugIO α) (config : Config := {}) : IO α :=
  LbugIO.toIO do f (← Database.open path config)

end Ladybug
