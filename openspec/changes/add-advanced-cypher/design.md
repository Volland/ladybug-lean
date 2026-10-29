## Context

The core AST, builder, printer and syntax from M2–M3 cover fixed-length patterns. Ladybug writes recursive patterns as `-[:R*1..3]->`, `-[:R* SHORTEST 1..10]->` and `-[:R* ALL SHORTEST 1..10]->`. Vector and full-text search are procedures from the `vector` and `fts` extensions: `CREATE_VECTOR_INDEX`, `QUERY_VECTOR_INDEX`, `CREATE_FTS_INDEX`, `QUERY_FTS_INDEX`, and the matching `DROP_*`.

## Goals / Non-Goals

**Goals:**
- Typed paths and typed procedure results, with the same AST in builder and syntax.

**Non-Goals:**
- Generic `CALL proc() YIELD` with user-declared signatures (deferred past v1).
- Arrow export (there is no Arrow library for Lean to hand the data to).

## Decisions

### Paths as a typed structure
`Path N R` is a structure with `nodes : Array N` and `rels : Array R`, decoded from Ladybug's recursive-rel value. A variable-length match returns `PathVar N R` (an expression of type `Path N R`) together with the end-node companion. Bounds are `Nat` arguments, and an `upper` argument is required, which enforces the "unbounded rejected" scenario by construction.

### Subqueries reuse QueryM
`exists_ (body : QueryM Unit) : QueryM (Expr (Option Bool))` runs the body builder in a nested scope that shares the fresh-name and parameter counters, so outer variables keep their names and parameters stay unique. `COUNT { }` and `CALL { }` follow the same pattern.

### Union as a Query combinator
`Query.union (a b : Query α)`, and the `all` variant, require both queries to share `α` and their column-name lists, checked when the query is built by comparing `Returnable` column names. That is a compile-time check because the names are part of the `Ret` index.

### Search procedures as typed clauses
`vectorSearch (T) (index) (q : Embedding n) (k) : QueryM (T.Var × Expr Double)` appends `CALL QUERY_VECTOR_INDEX('<T>', '<index>', $p, k) RETURN node, distance`, binding the companion to `node`. The table and index names are identifiers from the declaration, printed as string literals, the only non-parameter literals besides COPY paths; they are validated as identifiers. Index creation and dropping are statements. The native backend runs `INSTALL x; LOAD x` once per connection on first use, remembering this in the connection state.

### Embedding as a subtype
`Embedding n := { a : FloatArray // a.size = n }`, which maps to `FLOAT[n]`. The column stores Float32. Lean's `FloatArray` is Float64, and narrowing happens at bind time.

### Timeouts
`withTimeout (ms) (body)` calls `lbug_connection_set_query_timeout` before and resets it after. `Connection.interrupt` calls `lbug_connection_interrupt`. Ladybug's interrupted/timeout messages map to `.interrupted` and `.timeout`.

## Risks / Trade-offs

- [Extensions are downloaded by Ladybug at INSTALL time] → tests run INSTALL once and cache it; if offline, the search tests are skipped with a clear message, never silently passed.
- [Float32 narrowing changes values slightly] → decoded embeddings compare with a tolerance in tests; the docs say the column stores Float32.
