## Why

The builder from M2 is type-safe but reads less like Cypher than Cypher itself. For queries copied from Ladybug's docs or written by people who know Cypher, writing Cypher directly inside Lean, with the same compile-time checks, is the more natural surface. This is the second half of [[decisions#Hybrid typed DSL]].

## What Changes

- A `cypher%` term syntax accepting the Cypher clauses covered by the builder.
- Elaboration that resolves labels to declared tables, checks properties and expression types, infers the result type and produces the same core AST as the equivalent builder query.
- Lean values referenced from inside the Cypher text become parameters.
- Errors that point at the offending Cypher token.

## Capabilities

### New Capabilities
- `cypher-syntax`: writing typed Cypher text directly in Lean source.

### Modified Capabilities

None.

## Impact

- New modules: `Ladybug/Cypher/Syntax.lean` (syntax categories), `Ladybug/Cypher/Elab.lean` (elaborator), and a label registry environment extension populated by `node_table`/`rel_table` in `Ladybug/Schema/Command.lean`.
- Depends on [[openspec:cypher-query#Query builder]] and [[openspec:graph-schema#Node table declaration]].
- Requirements added: [[openspec:cypher-syntax#Embedded Cypher]], [[openspec:cypher-syntax#Same AST as the builder]], [[openspec:cypher-syntax#Schema-checked elaboration]], [[openspec:cypher-syntax#Lean values as parameters]], [[openspec:cypher-syntax#Located errors]].
