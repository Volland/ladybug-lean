import Lean

/-!
# Table registry

An environment extension mapping each declared label to its Lean structure and
columns, filled by `node_table`/`rel_table` and read by the `cypher%` elaborator.
-/

namespace Ladybug.Registry

open Lean

structure ColumnEntry where
  name : String
  nullable : Bool
  deriving Inhabited, Repr

structure TableEntry where
  label : String
  declName : Name
  isRel : Bool
  columns : Array ColumnEntry
  /-- Endpoint labels of a relationship table. -/
  src : Option String := none
  dst : Option String := none
  deriving Inhabited, Repr

initialize tableExt : SimplePersistentEnvExtension TableEntry (Std.HashMap String TableEntry) ←
  registerSimplePersistentEnvExtension {
    addEntryFn := fun m e => m.insert e.label e
    addImportedFn := fun arrs => arrs.foldl (fun m a => a.foldl (fun m e => m.insert e.label e) m) {}
  }

def register (e : TableEntry) : CoreM Unit := modifyEnv (tableExt.addEntry · e)

def find? (env : Environment) (label : String) : Option TableEntry :=
  (tableExt.getState env).get? label

def labels (env : Environment) : Array String := (tableExt.getState env).keys.toArray

end Ladybug.Registry
