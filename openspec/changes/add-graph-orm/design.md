## Context

M2 provides table metadata classes (`NodeTable`, `RelTable`), value encoding to and from properties, the builder, and `MonadGraph`. The ORM is generic code over those classes. Nothing is generated per table beyond what M2's commands already produce.

## Goals / Non-Goals

**Goals:**
- Every operation is one generic function over `[MonadGraph m] [NodeTable α]`, implemented with the builder, so it runs on both backends.

**Non-Goals:**
- Identity map, lazy loading, change tracking, migrations ([[decisions#Repository not Hibernate]]).

## Decisions

### Generic functions, not generated code
`insert [NodeTable α] (x : α) : m Unit` builds `CREATE (n:L $props)` from `NodeTable.label` and the `ToValue` struct of `x`. `get? (key : NodeTable.Key α)` matches on the key column. Alternative rejected: generating `Person.insert` and similar functions in the `node_table` command, which multiplies generated code and hides the logic from the reader.

### Not-found and constraint errors
`update` and `link` use `MATCH … SET … RETURN count(*)` and raise `.notFound` when the count is 0. Duplicate keys surface as Ladybug errors, which the native backend maps to `.constraint` by recognising Ladybug's primary-key violation message. The in-memory backend raises `.constraint` itself.

### Batches through UNWIND
`insertMany` sends `UNWIND $rows AS row CREATE (n:L) SET n = row`, or the per-column form if Ladybug lacks map assignment, with `rows` as a list-of-struct parameter. Batching bounds the parameter size. File import prints `COPY L FROM '<path>'` with the path as a string literal, the one place literal text is printed, because COPY does not accept parameters. The path is escaped, and is rejected if it contains a quote.

## Risks / Trade-offs

- [Upsert semantics differ between MERGE+SET and delete+create] → upsert is `MERGE (n:L {key: $k}) SET n.p1 = $p1, …`, so relationships survive and every non-key property is overwritten, including setting a column to NULL when the field is `none`.
- [The COPY path is literal text] → the path is quoted and validated; it is never derived from row data.
