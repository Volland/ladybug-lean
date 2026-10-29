## Why

Programs written against `MonadGraph` can only run where the native library is present, so they can't be run with `#eval` in the editor or unit-tested cheaply. And nothing independently checks that the typed layer means the same thing as Ladybug. A pure in-memory backend that interprets the full v1 AST solves both, and acts as a differential-testing oracle against Ladybug ([[decisions#Two backends one API]]).

## What Changes

- `Graph`: a pure value holding node tables, relationship tables and indexes.
- `MemM`: a `MonadGraph` instance over `Graph` state with snapshot transactions.
- An evaluator for the whole v1 core AST: every clause, expression, aggregate, path pattern, subquery, UNION, vector query (exact) and full-text query.
- Schema enforcement in memory: declared tables, primary-key uniqueness, endpoint types.
- A differential test suite that runs generated queries on generated graphs on both backends and compares the results.

## Capabilities

### New Capabilities
- `memory-backend`: the pure in-memory graph backend and its conformance with Ladybug.

### Modified Capabilities

None.

## Impact

- New modules: `Ladybug/Mem/Graph.lean`, `Ladybug/Mem/Eval.lean`, `Ladybug/Mem.lean`; tests `Tests/Memory.lean`, `Tests/MemEval.lean` and `Tests/Differential.lean` with generators.
- Depends on [[openspec:graph-monad#Backend-independent execution]] and the core AST of [[openspec:cypher-query#Query builder]], [[openspec:cypher-query#Subqueries]] and [[openspec:graph-search#Vector index]].
- Requirements added: [[openspec:memory-backend#Pure graph state]], [[openspec:memory-backend#Full AST evaluation]], [[openspec:memory-backend#Schema enforcement in memory]], [[openspec:memory-backend#Snapshot transactions]], [[openspec:memory-backend#Differential conformance]].
