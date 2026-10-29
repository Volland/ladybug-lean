## 1. State and monad

- [ ] 1.1 `Ladybug/Mem/Graph.lean`: persistent `Graph` with tables, keys and indexes, annotated `@tg: implements:: [[openspec:memory-backend#Pure graph state]]`
- [ ] 1.2 `Ladybug/Mem.lean`: `MemM` and its `MonadGraph` instance with snapshot transactions, annotated `implements:: [[openspec:memory-backend#Snapshot transactions]]`
- [ ] 1.3 Schema application and enforcement, annotated `implements:: [[openspec:memory-backend#Schema enforcement in memory]]`

## 2. Evaluator

- [ ] 2.1 `Ladybug/Mem/Eval.lean`: expressions with three-valued logic, clauses, aggregates, ordering, writes, annotated `implements:: [[openspec:memory-backend#Full AST evaluation]]`
- [ ] 2.2 Paths, shortest paths, subqueries, UNION
- [ ] 2.3 `Ladybug/Mem/Search.lean`: exact vector kNN and BM25 full-text

## 3. Differential testing

- [ ] 3.1 Seeded graph and query generators with shrinking in `Tests/Differential.lean`
- [ ] 3.2 Differential runner comparing both backends, annotated `implements:: [[openspec:memory-backend#Differential conformance]]`

## 4. Tests

- [ ] 4.1 One test per scenario, each annotated `@tg: verifies::` directly above the test, plus native tests pinning Ladybug's implementation-defined behaviour

## 5. Docs and checks

- [ ] 5.1 Record the decisions in `tg.md/decisions.md`; update `tg.md/architecture.md` (Memory backend section) and its `openspec:` frontmatter
- [ ] 5.2 Run `tg check`, `tg ontology check` and `tg trace memory-backend --gaps` and close every gap
