## Context

M2's builder and core AST exist. Lean's extensible parser can define a `cypher` syntax category, and an elaborator can turn its syntax trees into terms that build the core AST.

## Goals / Non-Goals

**Goals:**
- Reuse the builder for every typing rule, so the two surfaces cannot drift.
- Errors at Cypher token positions.

**Non-Goals:**
- Parsing Cypher from runtime strings into the typed AST (the raw API covers runtime text).
- Full openCypher grammar; only what the builder covers, extended in M5.

## Decisions

### Elaborate syntax to builder terms
The elaborator does not construct core AST values itself. It translates each clause into the matching builder call (`match_`, `where_`, `return_`…) as a `do` block term and lets Lean's elaborator type-check it. That gives identical ASTs by construction and reuses the builder's instance-based typing rules. Each generated subterm carries the syntax node's source range (`withRef`), so type errors appear at the Cypher token. Alternative rejected: a separate type checker over Cypher syntax, which would duplicate the typing rules and drift from the builder.
- motivated_by:: [[decisions#Hybrid typed DSL]]

### Label registry
`node_table` and `rel_table` register `label ↦ declaration name` in an environment extension. The elaborator resolves `(:Person)` through it and reports unknown labels with "did you mean" suggestions based on edit distance. Property names resolve against the companion structure's fields.

### Parameters
`$ident` resolves to the Lean local `ident`, and `$( term )` to an arbitrary term. Both elaborate to `lit term`. Lean's parser reads both as antiquotations of the `cypherExpr` category, so the elaborator takes the antiquoted term. No new token such as `$(` is declared, because it would break antiquotations in every importing file.

### Keywords
Keywords are non-reserved symbols accepted in upper, lower and capitalized case (`MATCH`, `match`, `Match`), so they don't become reserved Lean tokens (a `match` keyword would break Lean's own `match`). Keywords that start a trailing rule (`AND`, `OR`, `XOR`, `IS`, `IN`, `STARTS`, `ENDS`, `CONTAINS`) also list `ident` among their first tokens, because Lean indexes trailing parsers of identifier tokens under `ident` ([[decisions#Cypher keywords parsed as non-reserved symbols]]). Other casings such as `mAtCh` are not accepted.

### Layout and literals
The first clause may start on the line of `cypher%` or on the next, and later clauses must start at or right of the first clause's column ([[decisions#A query ends where its indentation does]]). Strings are Lean string literals (`"Ann"`), since `'…'` is Lean's character syntax. A path pattern `(a:A)-[:R]->(b:B)` becomes one builder `match_` per step, as the builder writes it, so it prints as consecutive MATCH clauses. CREATE and MERGE properties must be literals or `$parameters`, and missing nullable properties are `none`.

## Risks / Trade-offs

- [New Cypher keywords collide with Lean tokens] → keywords are parsed as identifiers inside the category and are never declared as global tokens.
- [Deep `do` terms elaborate slowly for big queries] → measured in a benchmark test with a 30-clause query; if slow, generate a flat `bind` chain instead of `do`.
