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
`Path N R` is a structure with `nodes : Array N` and `rels : Array R`, decoded from Ladybug's recursive-rel value. A variable-length match binds a path variable, `p = (a)-[r:R*1..2]->(b)`, because a path variable's nodes include both endpoints while a relationship variable's include only the intermediate ones. It returns an `Expr (Path N R)` together with the end-node companion. Bounds are `Nat` arguments and `max` has no default, which enforces the "unbounded rejected" scenario by construction. Variable-length patterns require a relationship table from a node table to itself (`RelTable ρ σ σ`), so every node on the path has one type.

### Subqueries reuse QueryM
`exists_ (body : QueryM Unit) : QueryM (Expr Bool)` runs the body builder in a nested scope that shares the fresh-name counter, so outer variables keep their names, and keeps only the MATCH and WHERE clauses it emitted. `countSub` does the same for `COUNT { }`. Ladybug has no `CALL { }` subqueries ([[constraints#No CALL subqueries]]).

### Union as a Query combinator
`Query.union (a b : Query α)` and `Query.unionAll` require both queries to share `α`, which the type checker enforces. Ladybug also requires equal column names, so the union aliases every returned item of both parts as `c0, c1, …`.

### Search procedures as typed clauses
`vectorSearch (T) (index) (q : Embedding n) (k) : QueryM (T.Var × Expr Float)` appends `CALL QUERY_VECTOR_INDEX('<T>', '<index>', $p, $k) YIELD node AS n₁, distance AS v₂`, binding the companion to the fresh `n₁`, so several searches can appear in one query. The table and index names are identifiers from the declaration, printed as string literals, the only non-parameter literals besides COPY paths; they are validated as identifiers. Index creation and dropping are statements. The native backend runs `INSTALL x; LOAD x` once per connection on first use, remembering this in the connection state.

### Embedding as a subtype
`Embedding n := { a : FloatArray // a.size = n }`, which maps to `FLOAT[n]`. The column stores Float32. Lean's `FloatArray` is Float64, and narrowing happens at bind time.

### Timeouts
`withTimeout (ms) (body)` calls `lbug_connection_set_query_timeout` before and resets it after. `Connection.interrupt` calls `lbug_connection_interrupt`. Ladybug reports both as "Interrupted.", and only between units of pipeline work, so the connection records whether it was interrupted and the error becomes `.interrupted` or, inside `withTimeout`, `.timeout` ([[constraints#Timeouts and interrupts are checked between work units]]).

## Risks / Trade-offs

- [Extensions are downloaded by Ladybug at INSTALL time] → tests run INSTALL once and cache it; if offline, the search tests are skipped with a clear message, never silently passed.
- [Float32 narrowing changes values slightly] → decoded embeddings compare with a tolerance in tests; the docs say the column stores Float32.
