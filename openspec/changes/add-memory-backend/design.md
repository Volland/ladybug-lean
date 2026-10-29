## Context

The core AST is untyped and every value is a `Value` ([[decisions#Phantom types over an untyped core]]), so the evaluator is an interpreter from core AST to rows of `Value`s. It decodes with the same `FromRow` as the native backend, which keeps the two backends' decoding identical by construction.

## Goals / Non-Goals

**Goals:**
- Clear, obviously correct semantics over speed: the evaluator is a reference model.
- Termination by construction.

**Non-Goals:**
- Performance on large graphs, concurrency, persistence.
- Matching Ladybug's approximate (HNSW) vector results on large data; conformance is checked on small data, where HNSW is exact in practice.
- Matching full-text scores exactly.

## Decisions

### Rows as environments
Evaluation is a fold over clauses on `Array Env`, where `Env` maps variable names to `Value`. MATCH extends each env with every binding of the pattern, OPTIONAL MATCH extends with NULLs when there are none, WHERE filters on `== some true`, WITH and RETURN project, and aggregates group by the non-aggregate projections. This is the textbook semantics of Cypher's driving table, and it makes each clause one small function.

### Termination
Pattern matching enumerates edges in bounded depth (upper bounds are mandatory), subqueries recurse on structurally smaller ASTs, and UNWIND iterates over finite lists, so `eval` is structurally recursive with no `partial`.

### NULL ordering and comparison semantics follow Ladybug, tested
Where openCypher leaves behaviour to the implementation (NULL position in ORDER BY, comparing values of different types, integer overflow), the evaluator copies Ladybug's observed behaviour. Each such rule is pinned by a native test so a Ladybug upgrade that changes it is detected.

### Full-text scoring
BM25 with k1 = 1.2 and b = 0.75 over a tokenizer that lowercases and splits on non-alphanumerics, with Ladybug's default English stopword list and a Porter stemmer. Conformance compares the matched sets and their order only.

### Differential generator
A seeded generator builds small graphs (at most 8 nodes per table, 3 tables) over a fixed test schema, and queries from a grammar of builder combinators that are well-typed by construction. Shrinking removes clauses and nodes until the disagreement disappears, then reports the last failing case.

### Transactions as snapshots
`MemM := StateT Graph (ExceptT Ladybug.Error Id)` plus a transaction mode flag. `withTx` saves the `Graph`, runs the body, and restores the saved value on error. Since `Graph` is persistent, saving it is O(1).

## Risks / Trade-offs

- [The evaluator copies a Ladybug bug] → a disagreement with openCypher semantics is recorded as a `-contradicts::` edge in tg.md with the Ladybug issue, instead of being silently copied.
- [The differential suite is slow] → 500 cases by default, configurable through an environment variable; CI runs 500.
