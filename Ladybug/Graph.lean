import Ladybug.Cypher.Builder

/-!
# The graph monad

`MonadGraph` runs typed queries, statements, schema setup and transactions on
any backend: the native database (`LbugM`) or the in-memory graph. Code written
against it does not name a backend:

```lean
def countPersons [MonadGraph m] : m Int64 := do
  let rows ← runQuery (query do let p ← match_ (node Person); return_ (Expr.count p.id))
  return rows[0]!
```
-/

namespace Ladybug

inductive TxMode where
  | readWrite
  | readOnly
  deriving Repr, BEq, Inhabited

-- @tg: implements:: [[openspec:graph-monad#Backend-independent execution]]
class MonadGraph (m : Type → Type) extends Monad m, MonadExceptOf Error m where
  runQuery {α : Type} : Query α → m (Array α)
  runStmt : Statement → m Unit
  /-- Run the body in a transaction: commit on success, roll back on error. -/
  withTxMode {α : Type} : TxMode → m α → m α
  /-- Create every table of the schema that does not exist yet. -/
  applySchema : Schema → m Unit
  /-- Differences between the schema and the database; empty when they match. -/
  verifySchema : Schema → m (Array SchemaDiff)

export MonadGraph (runQuery runStmt applySchema verifySchema)

variable {m : Type → Type} {α : Type}

def withTx [MonadGraph m] (body : m α) : m α := MonadGraph.withTxMode .readWrite body
def withReadTx [MonadGraph m] (body : m α) : m α := MonadGraph.withTxMode .readOnly body

/-- Build and run a query in one step. -/
def runQueryM [MonadGraph m] [FromRow α] (q : QueryM (Ret α)) : m (Array α) := runQuery (query q)

/-- Build and run a statement in one step. -/
def runStmtM [MonadGraph m] (s : QueryM Unit) : m Unit := runStmt (stmt s)

end Ladybug
