## Why

Most application code does the same few things with declared tables: store a value, fetch it by key, change it, delete it, link two nodes, follow links, and load many values at once. Writing a query for each is noise. M4 adds a small repository layer, generated from the table declarations, that works on every backend.

## What Changes

- Typed CRUD for node tables: insert, upsert (merge on key), get by key, find all, find by predicate, update, delete, detach delete.
- Typed relationships: link two nodes with a relationship value, unlink, and list relationships between two nodes.
- Traversal helpers: outgoing and incoming neighbours through a relationship table, with their relationship values.
- Bulk load: insert many values in batches through parameter lists, and load node or relationship tables from CSV or Parquet files.
- Every operation is written once against `MonadGraph`.

## Capabilities

### New Capabilities
- `graph-orm`: repository-style operations on declared node and relationship tables.

### Modified Capabilities

None.

## Impact

- New module: `Ladybug/ORM.lean`; native file import in `LadybugNative/Graph.lean`.
- Depends on [[openspec:cypher-query#Query builder]] and [[openspec:graph-monad#Backend-independent execution]].
- Bound by [[decisions#Repository not Hibernate]].
- Requirements added: [[openspec:graph-orm#Node CRUD]], [[openspec:graph-orm#Relationship links]], [[openspec:graph-orm#Traversal helpers]], [[openspec:graph-orm#Batched insert]], [[openspec:graph-orm#File import]].
