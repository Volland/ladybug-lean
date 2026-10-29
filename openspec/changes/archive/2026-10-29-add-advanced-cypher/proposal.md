## Why

Graph and agent-memory workloads need more than fixed-length patterns: they follow chains of relationships, find shortest connections, combine result sets, and retrieve by similarity or by text. M5 completes the v1 Cypher surface so that these queries are typed too, in the builder and in `cypher%`.

## What Changes

- Variable-length relationship patterns with bounds, and shortest / all-shortest paths, returning typed path values.
- Subqueries: `EXISTS { }` and `COUNT { }` (Ladybug has no `CALL { }` subqueries).
- `UNION` and `UNION ALL` of queries with the same result type.
- Fixed-dimension embedding columns, vector index creation and nearest-neighbour queries.
- Full-text index creation and queries.
- Extension installation and loading, query timeouts and interruption on the native backend.

## Capabilities

### New Capabilities
- `graph-search`: vector and full-text indexes and queries, and the extensions they need.

### Modified Capabilities

- `cypher-query`: adds variable-length paths, shortest paths, EXISTS/COUNT subqueries and UNION.
- `cypher-syntax`: adds the same constructs to `cypher%`.
- `native-connection`: adds query timeouts and interruption.

## Impact

- New modules: `Ladybug/Cypher/Advanced.lean`, `Ladybug/Search.lean`; extensions to `Ladybug/Cypher/Core.lean`, `Print.lean`, `Syntax.lean` and `Elab.lean`; `LadybugNative/Connection.lean` gains extensions, timeouts and interruption.
- Depends on [[openspec:cypher-query#Query builder]] and [[openspec:cypher-syntax#Embedded Cypher]].
- Requirements added: [[openspec:cypher-query#Variable-length paths]], [[openspec:cypher-query#Shortest paths]], [[openspec:cypher-query#Subqueries]], [[openspec:cypher-query#Union]], [[openspec:cypher-syntax#Advanced clauses in syntax]], [[openspec:graph-search#Embedding columns]], [[openspec:graph-search#Vector index]], [[openspec:graph-search#Full-text index]], [[openspec:graph-search#Extensions]], [[openspec:native-connection#Timeouts and interruption]].
