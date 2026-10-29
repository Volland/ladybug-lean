## 1. Registry and syntax

- [ ] 1.1 Label registry environment extension populated by `node_table`/`rel_table`
- [ ] 1.2 `Ladybug/Cypher/Syntax.lean`: `cypher` syntax category for clauses, patterns and expressions, annotated `@tg: implements:: [[openspec:cypher-syntax#Embedded Cypher]]`

## 2. Elaboration

- [ ] 2.1 `Ladybug/Cypher/Elab.lean`: translate clauses to builder terms with source ranges, annotated `implements:: [[openspec:cypher-syntax#Same AST as the builder]]`, `[[openspec:cypher-syntax#Schema-checked elaboration]]` and `[[openspec:cypher-syntax#Located errors]]`
- [ ] 2.2 `$x` and `$(e)` parameters, annotated `implements:: [[openspec:cypher-syntax#Lean values as parameters]]`

## 3. Tests

- [ ] 3.1 AST-equality tests (syntax vs builder) and `#guard_msgs` rejection tests in `Tests/Syntax.lean`, one per scenario, each annotated `@tg: verifies::`
- [ ] 3.2 Elaboration-time benchmark with a 30-clause query

## 4. Docs and checks

- [ ] 4.1 Record the decisions in `tg.md/decisions.md`; update `tg.md/architecture.md` (Syntax section) and its `openspec:` frontmatter
- [ ] 4.2 Run `tg check`, `tg ontology check` and `tg trace cypher-syntax --gaps` and close every gap
