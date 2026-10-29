import Ladybug.Mem.Eval
import Ladybug.Graph

/-!
# The in-memory backend

`MemM` runs any `MonadGraph` program on a pure `Graph` value, without the
native library, so it works in `#eval`:

```lean
#eval (do applySchema schema; Repo.insert ann; Repo.findAll Person : MemM _).run' {}
```
-/

namespace Ladybug

open Cypher

structure MemState where
  graph : Mem.Graph := {}
  tx : Option TxMode := none
  faults : Mem.Faults := {}
  deriving Inhabited

/-- A graph program on an in-memory graph. -/
abbrev MemM := StateT MemState (Except Error)

namespace MemM

variable {α : Type}

/-- Run on a graph and return the result. -/
def run' (m : MemM α) (g : Mem.Graph := {}) (faults : Mem.Faults := {}) : Except Error α :=
  (m.run { graph := g, faults }).map (·.1)

/-- Run on a graph and return the result and the final graph. -/
def runWithGraph (m : MemM α) (g : Mem.Graph := {}) : Except Error (α × Mem.Graph) :=
  (m.run { graph := g }).map fun (a, s) => (a, s.graph)

private def evalCore (q : Core.Query) : MemM Mem.Result := fun s => do
  let st : Mem.EvalState := { graph := s.graph, faults := s.faults, readOnly := s.tx == some .readOnly }
  let (r, st') ← (Mem.evalQuery q).run st
  return (r, { s with graph := st'.graph })

private def diffTable (g : Mem.Graph) (d : TableDecl) : Array SchemaDiff := Id.run do
  let some actual := g.table? d.label | return #[.missingTable d.label]
  let cols (t : TableDecl) := match t with | .node _ _ cs | .rel _ _ _ cs => cs
  let mut diffs := #[]
  match d, actual with
  | .node l k _, .node _ k' _ => if k != k' then diffs := diffs.push (.keyMismatch l k k')
  | .rel l s t _, .rel _ s' t' _ =>
    if s != s' || t != t' then diffs := diffs.push (.endpointMismatch l s!"FROM {s} TO {t}" s!"FROM {s'} TO {t'}")
  | .node l .., _ => return #[.kindMismatch l "NODE" "REL"]
  | .rel l .., _ => return #[.kindMismatch l "REL" "NODE"]
  for c in cols d do
    match (cols actual).find? (·.name == c.name) with
    | none => diffs := diffs.push (.missingProperty d.label c.name)
    | some c' => unless c'.type == c.type do diffs := diffs.push (.typeMismatch d.label c.name c.type.ddl c'.type.ddl)
  for c in cols actual do
    unless (cols d).any (·.name == c.name) do diffs := diffs.push (.extraProperty d.label c.name)
  return diffs

end MemM

-- @tg: implements:: [[openspec:memory-backend#Snapshot transactions]]
-- @tg: implements:: [[openspec:memory-backend#Schema enforcement in memory]]
instance : MonadGraph MemM where
  runQuery q := do
    let r ← MemM.evalCore q.core
    r.rows.mapM fun vs => match q.decode ⟨r.columns, vs⟩ with
      | .ok a => pure a
      | .error e => throw e
  runStmt s := discard (MemM.evalCore s.core)
  withTxMode mode body := do
    let saved ← get
    if saved.tx.isSome then throw (.transaction "a transaction is already open")
    modify fun _ => { saved with tx := some mode }
    try
      let a ← body
      modify fun s => { s with tx := none }
      return a
    catch e =>
      modify fun _ => { saved with tx := none }
      throw e
  applySchema s := do
    let nodes := s.filter fun | .node .. => true | _ => false
    let rels := s.filter fun | .rel .. => true | _ => false
    modify fun st => { st with graph := (nodes ++ rels).foldl Mem.Graph.addTable st.graph }
  verifySchema s := do
    let g := (← get).graph
    return s.toArray.flatMap (MemM.diffTable g)

end Ladybug
