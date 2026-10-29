## 1. Core AST and printer

- [x] 1.1 `Ladybug/Cypher/Core.lean`: untyped expressions, patterns, clauses, queries, parameters
- [x] 1.2 `Ladybug/Cypher/Print.lean`: deterministic printer and parameter map, annotated `@tg: implements:: [[openspec:cypher-query#Printing]]`

## 2. Schema

- [x] 2.1 `Ladybug/Schema.lean`: `ColumnType`, `NodeTable`, `RelTable`, `Schema`, DDL generation, annotated `implements:: [[openspec:graph-schema#DDL generation]]`
- [x] 2.2 `Ladybug/Schema/Command.lean`: `node_table` and `rel_table` commands generating instances and companions, annotated with `[[openspec:graph-schema#Node table declaration]]` and `[[openspec:graph-schema#Relationship table declaration]]`

## 3. Typed language

- [x] 3.1 `Ladybug/Cypher/Expr.lean`: phantom `Expr`, `Nullable`/`Lift`, operators, predicates, functions, annotated `implements:: [[openspec:cypher-query#Typed expressions]]` and `[[openspec:cypher-query#Three-valued logic]]`
- [x] 3.2 Aggregates, annotated `implements:: [[openspec:cypher-query#Aggregation]]`
- [x] 3.3 `Ladybug/Cypher/Builder.lean`: `QueryM`, clauses, `Returnable`, `query`/`stmt`, annotated `implements:: [[openspec:cypher-query#Query builder]]` and `[[openspec:cypher-query#Result typing]]`

## 4. Graph monad

- [x] 4.1 `Ladybug/Graph.lean`: `MonadGraph`, `TxMode`, `SchemaDiff`, annotated `implements:: [[openspec:graph-monad#Backend-independent execution]]`
- [x] 4.2 `Ladybug/Native/Graph.lean`: `LbugM` instance with prepared-statement cache and schema verification, annotated `implements:: [[openspec:graph-monad#Native backend]]` and `[[openspec:graph-schema#Schema verification]]`

## 5. Tests

- [x] 5.1 Golden printer tests and compile-time rejection tests (`#guard_msgs`) in `Tests/Cypher.lean`
- [x] 5.2 Native integration tests for every scenario of `graph-schema`, `cypher-query` and `graph-monad`, each annotated `@tg: verifies::` directly above the test

## 6. Docs and checks

- [x] 6.1 Record the design's decisions in `tg.md/decisions.md` with typed edges
- [x] 6.2 Update `tg.md/architecture.md` (Typed core section) and add the three capabilities to its `openspec:` frontmatter
- [x] 6.3 Run `tg check`, `tg ontology check` and `tg trace <capability> --gaps` for each capability and close every gap
