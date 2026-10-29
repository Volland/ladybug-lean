## 1. Paths

- [ ] 1.1 `Ladybug/Cypher/Path.lean`: `Path`, variable-length patterns, `length`/`nodes`/`rels`, annotated `@tg: implements:: [[openspec:cypher-query#Variable-length paths]]`
- [ ] 1.2 Shortest and all-shortest patterns, annotated `implements:: [[openspec:cypher-query#Shortest paths]]`

## 2. Subqueries and union

- [ ] 2.1 `Ladybug/Cypher/Subquery.lean`: EXISTS, COUNT and CALL subqueries, annotated `implements:: [[openspec:cypher-query#Subqueries]]`
- [ ] 2.2 `Query.union` and `Query.unionAll`, annotated `implements:: [[openspec:cypher-query#Union]]`
- [ ] 2.3 Extend `cypher%` with every construct above, annotated `implements:: [[openspec:cypher-syntax#Advanced clauses in syntax]]`

## 3. Search

- [ ] 3.1 `Embedding n` column type, annotated `implements:: [[openspec:graph-search#Embedding columns]]`
- [ ] 3.2 Vector index create/drop/query, annotated `implements:: [[openspec:graph-search#Vector index]]`
- [ ] 3.3 Full-text index create/drop/query, annotated `implements:: [[openspec:graph-search#Full-text index]]`
- [ ] 3.4 Extension install/load with automatic loading, annotated `implements:: [[openspec:graph-search#Extensions]]`

## 4. Native extras

- [ ] 4.1 `withTimeout` and `Connection.interrupt`, annotated `implements:: [[openspec:native-connection#Timeouts and interruption]]`

## 5. Tests

- [ ] 5.1 Golden and native integration tests for every scenario, each annotated `@tg: verifies::` directly above the test

## 6. Docs and checks

- [ ] 6.1 Record the decisions in `tg.md/decisions.md`; update `tg.md/architecture.md` and its `openspec:` frontmatter with `graph-search`
- [ ] 6.2 Run `tg check`, `tg ontology check` and `tg trace` with `--gaps` for each touched capability and close every gap
