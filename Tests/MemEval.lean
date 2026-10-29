import Tests.Fixtures

/-!
Compile-time evaluation of a graph program on the in-memory backend. This
module imports only the pure `Ladybug` library, so `#guard` runs it in the
editor's interpreter without the native library.
-/

namespace Tests.MemEval

open Ladybug Tests.Fixtures

def countAfterInserts {m : Type → Type} [MonadGraph m] : m Int64 := do
  applySchema schema
  Repo.insert (Person.mk 1 "a" none)
  Repo.insert (Person.mk 2 "b" none)
  return (← runQueryM do let p ← match_ (node Person); return_ (Expr.count p.id))[0]!

-- @tg: verifies:: [[openspec:memory-backend#Pure graph state#Eval in the editor]] {level: unit}
#guard match (countAfterInserts : MemM Int64).run' {} with
  | .ok 2 => true
  | _ => false

end Tests.MemEval
