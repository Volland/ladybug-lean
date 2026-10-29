## 1. Paths

- [x] 1.1 `Ladybug/Cypher/Advanced.lean`: `Path`, variable-length patterns, `length`/`nodes`/`rels`, annotated `@tg: implements:: [[openspec:cypher-query#Variable-length paths]]`
- [x] 1.2 Shortest and all-shortest patterns, annotated `implements:: [[openspec:cypher-query#Shortest paths]]`

## 2. Subqueries and union

- [x] 2.1 `Ladybug/Cypher/Advanced.lean`: EXISTS and COUNT subqueries (Ladybug has no CALL subqueries), annotated `implements:: [[openspec:cypher-query#Subqueries]]`
- [x] 2.2 `Query.union` and `Query.unionAll`, annotated `implements:: [[openspec:cypher-query#Union]]`
- [x] 2.3 Extend `cypher%` with every construct above, annotated `implements:: [[openspec:cypher-syntax#Advanced clauses in syntax]]`

## 3. Search

- [x] 3.1 `Embedding n` column type, annotated `implements:: [[openspec:graph-search#Embedding columns]]`
- [x] 3.2 Vector index create/drop/query, annotated `implements:: [[openspec:graph-search#Vector index]]`
- [x] 3.3 Full-text index create/drop/query, annotated `implements:: [[openspec:graph-search#Full-text index]]`
- [x] 3.4 Extension install/load with automatic loading, annotated `implements:: [[openspec:graph-search#Extensions]]`

## 4. Native extras

- [x] 4.1 `withTimeout` and `Connection.interrupt`, annotated `implements:: [[openspec:native-connection#Timeouts and interruption]]`

## 5. Tests

- [x] 5.1 Golden and native integration tests for every scenario, each annotated `@tg: verifies::` directly above the test

## 6. Docs and checks

- [x] 6.1 Record the decisions in `tg.md/decisions.md`; update `tg.md/architecture.md` and its `openspec:` frontmatter with `graph-search`
- [x] 6.2 Run `tg check`, `tg ontology check` and `tg trace` with `--gaps` for each touched capability and close every gap
