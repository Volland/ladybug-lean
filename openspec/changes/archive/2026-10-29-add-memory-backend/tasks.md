## 1. State and monad

- [x] 1.1 `Ladybug/Mem/Graph.lean`: persistent `Graph` with tables, keys and indexes, annotated `@tg: implements:: [[openspec:memory-backend#Pure graph state]]`
- [x] 1.2 `Ladybug/Mem.lean`: `MemM` and its `MonadGraph` instance with snapshot transactions, annotated `implements:: [[openspec:memory-backend#Snapshot transactions]]`
- [x] 1.3 Schema application and enforcement, annotated `implements:: [[openspec:memory-backend#Schema enforcement in memory]]`

## 2. Evaluator

- [x] 2.1 `Ladybug/Mem/Eval.lean`: expressions with three-valued logic, clauses, aggregates, ordering, writes, annotated `implements:: [[openspec:memory-backend#Full AST evaluation]]`
- [x] 2.2 Paths, shortest paths, subqueries, UNION
- [x] 2.3 Exact vector kNN and BM25 full-text (Porter stemmer and BM25 in `Ladybug/Mem/Graph.lean`, procedures in `Ladybug/Mem/Eval.lean`)

## 3. Differential testing

- [x] 3.1 Seeded graph and query generators with shrinking in `Tests/Differential.lean`
- [x] 3.2 Differential runner comparing both backends, annotated `implements:: [[openspec:memory-backend#Differential conformance]]`

## 4. Tests

- [x] 4.1 One test per scenario, each annotated `@tg: verifies::` directly above the test, plus native tests pinning Ladybug's implementation-defined behaviour

## 5. Docs and checks

- [x] 5.1 Record the decisions in `tg.md/decisions.md`; update `tg.md/architecture.md` (Memory backend section) and its `openspec:` frontmatter
- [x] 5.2 Run `tg check`, `tg ontology check` and `tg trace memory-backend --gaps` and close every gap
