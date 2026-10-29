## 1. Registry and syntax

- [x] 1.1 Label registry environment extension populated by `node_table`/`rel_table`
- [x] 1.2 `Ladybug/Cypher/Syntax.lean`: `cypher` syntax category for clauses, patterns and expressions, annotated `@tg: implements:: [[openspec:cypher-syntax#Embedded Cypher]]`

## 2. Elaboration

- [x] 2.1 `Ladybug/Cypher/Elab.lean`: translate clauses to builder terms with source ranges, annotated `implements:: [[openspec:cypher-syntax#Same AST as the builder]]`, `[[openspec:cypher-syntax#Schema-checked elaboration]]` and `[[openspec:cypher-syntax#Located errors]]`
- [x] 2.2 `$x` and `$(e)` parameters, annotated `implements:: [[openspec:cypher-syntax#Lean values as parameters]]`

## 3. Tests

- [x] 3.1 AST-equality tests (syntax vs builder) and `#guard_msgs` rejection tests in `Tests/Syntax.lean`, one per scenario, each annotated `@tg: verifies::`
- [x] 3.2 Elaboration-time benchmark with a 30-clause query (`Tests/Syntax.lean#longQuery`; the module elaborates in about 2.3 s)

## 4. Docs and checks

- [x] 4.1 Record the decisions in `tg.md/decisions.md`; update `tg.md/architecture.md` (Syntax section) and its `openspec:` frontmatter
- [x] 4.2 Run `tg check`, `tg ontology check` and `tg trace cypher-syntax --gaps` and close every gap
