## Why

After M1, queries are untyped strings: a misspelled label, a property of the wrong type or a forgotten NULL surfaces only at runtime. M2 adds the typed core that the rest of the library builds on: graph schemas declared as Lean structures, a typed Cypher AST built in a monad, and one abstraction for running it.

## What Changes

- Node and relationship tables declared from Lean structures, with generated DDL and a runtime check against the database catalog.
- A typed expression language over a single untyped Cypher core AST: property access by dot notation, operators, literals that become parameters, aggregates, and full three-valued logic.
- A monadic query builder for the core clauses: MATCH, OPTIONAL MATCH, WHERE, WITH, RETURN, ORDER BY, SKIP, LIMIT, CREATE, MERGE, SET, DELETE, DETACH DELETE, UNWIND.
- A deterministic printer from the core AST to Cypher text and a parameter map.
- `MonadGraph`, the backend-independent class for running typed queries and transactions, with its native instance on `LbugM`.

## Capabilities

### New Capabilities
- `graph-schema`: declaring node and relationship tables in Lean, generating DDL and verifying it against a database.
- `cypher-query`: the typed query language: expressions, NULL semantics, the builder, the printer and result typing.
- `graph-monad`: running typed queries and transactions against any backend.

### Modified Capabilities

None.

## Impact

- New modules: `Ladybug/Schema.lean`, `Ladybug/Schema/Command.lean`, `Ladybug/Cypher/Core.lean` (untyped AST), `Ladybug/Cypher/Expr.lean`, `Ladybug/Cypher/Builder.lean`, `Ladybug/Cypher/Print.lean`, `Ladybug/Graph.lean` (`MonadGraph`), and the native instance in `Ladybug/Native/Graph.lean`.
- Depends on [[openspec:native-connection#Row decoding]] and [[openspec:native-connection#Prepared parameters]] from M1.
- Bound by [[decisions#Hybrid typed DSL]], [[decisions#Lean structures are the schema]], [[decisions#Full three-valued logic]] and [[decisions#Two backends one API]].
- Requirements added: [[openspec:graph-schema#Node table declaration]], [[openspec:graph-schema#Relationship table declaration]], [[openspec:graph-schema#DDL generation]], [[openspec:graph-schema#Schema verification]], [[openspec:cypher-query#Typed expressions]], [[openspec:cypher-query#Three-valued logic]], [[openspec:cypher-query#Query builder]], [[openspec:cypher-query#Aggregation]], [[openspec:cypher-query#Printing]], [[openspec:cypher-query#Result typing]], [[openspec:graph-monad#Backend-independent execution]], [[openspec:graph-monad#Native backend]].
