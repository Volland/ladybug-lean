/-!
# Errors

Every failure the library reports, on any backend.
-/

namespace Ladybug

-- @tg: implements:: [[openspec:native-connection#Structured errors]]
inductive Error where
  /-- The database could not be opened. -/
  | «open» (msg : String)
  /-- The database files were written by another storage version. -/
  | storageMismatch (fileVersion : Option Nat) (linkedVersion : Nat) (msg : String)
  /-- A statement failed while compiling or running. -/
  | query (msg : String)
  /-- A statement could not be prepared. -/
  | prepare (msg : String)
  /-- A parameter could not be bound, or is missing. -/
  | bind (param : String) (msg : String)
  /-- A result column does not decode to the requested type. -/
  | decode (column : String) (expected : String) (actual : String)
  /-- A transaction bracket was misused, or BEGIN/COMMIT failed. -/
  | transaction (msg : String)
  /-- A primary-key or other constraint was violated. -/
  | constraint (msg : String)
  /-- An entity addressed by key does not exist. -/
  | notFound (msg : String)
  /-- A query ran longer than its timeout. -/
  | timeout (msg : String)
  /-- A query was interrupted from another task. -/
  | interrupted (msg : String)
  /-- The native library failed outside a query. -/
  | native (msg : String)
  /-- An error raised by user code. -/
  | custom (msg : String)
  deriving Repr, BEq, Inhabited

namespace Error

protected def toString : Error → String
  | .open m => s!"cannot open database: {m}"
  | .storageMismatch f l m =>
    let file := f.map toString |>.getD "unknown"
    s!"storage version mismatch (database file {file}, linked library {l}): {m}"
  | .query m => s!"query failed: {m}"
  | .prepare m => s!"prepare failed: {m}"
  | .bind p m => s!"cannot bind parameter ${p}: {m}"
  | .decode c e a => s!"column {c}: expected {e}, got {a}"
  | .transaction m => s!"transaction error: {m}"
  | .constraint m => s!"constraint violated: {m}"
  | .notFound m => s!"not found: {m}"
  | .timeout m => s!"timeout: {m}"
  | .interrupted m => s!"interrupted: {m}"
  | .native m => s!"native error: {m}"
  | .custom m => m

instance : ToString Error := ⟨Error.toString⟩

/-- The message as reported by Ladybug or user code, without the kind prefix. -/
def message : Error → String
  | .open m | .storageMismatch _ _ m | .query m | .prepare m | .bind _ m | .transaction m
  | .constraint m | .notFound m | .timeout m | .interrupted m | .native m | .custom m => m
  | .decode c e a => s!"column {c}: expected {e}, got {a}"

end Error

end Ladybug
