---
type: Concept
openspec: [native-library, native-connection, graph-schema, cypher-query, graph-monad, cypher-syntax, graph-orm, graph-search, memory-backend]
---
# Architecture

The library is a stack of layers, each usable alone: a native binding, a pure value and decoding core, a typed Cypher core, a syntax, an ORM and two backends behind one monad class.

## Layers

From the bottom: native library and C shim, the pure value model, the typed Cypher core and schema, then the syntax, the ORM and the backends on top.

| Layer | Modules | Library | Milestone |
|---|---|---|---|
| Native library | `lakefile.lean`, `lbug.lock`, `c/lbug_shim.c` | build | M1 |
| Values and decoding | `Ladybug.Value`, `Ladybug.Error`, `Ladybug.Decode`, `Ladybug.Decode.Derive` | `Ladybug` | M1 |
| Native API | `LadybugNative.FFI`, `LadybugNative` | `LadybugNative` | M1 |
| Schema | `Ladybug.Schema`, `Ladybug.Schema.Command` | `Ladybug` | M2 |
| Typed Cypher | `Ladybug.Cypher.*` | `Ladybug` | M2, M3, M5 |
| Graph monad | `Ladybug.Graph`, `LadybugNative.Graph` | both | M2 |
| ORM | `Ladybug.ORM`, `Ladybug.ORM.Bulk` | `Ladybug` | M4 |
| Search | `Ladybug.Search` | `Ladybug` | M5 |
| Memory backend | `Ladybug.Mem.*` | `Ladybug` | M6 |

- defines:: [[decisions#Two backends one API]]

## Native layer

The C shim wraps Ladybug's C API in reference-counted external objects whose children keep their parents alive, and copies every result row into a Lean `Value` before advancing the cursor.

`LadybugNative` adds `Database.open`, `Connection.query`/`prepare`, and the `LbugM` monad with `query`, `queryAs`, `exec` and the `withTx`/`withReadTx` brackets (`Ladybug.withTxMode` in `LadybugNative.lean`). Decoding is shared with every backend through `FromValue`/`FromRow` (`Ladybug.FromRow` in `Ladybug/Decode.lean`).

- defines:: [[decisions#Ownership in C external objects]]
- defines:: [[decisions#Rows are copied out eagerly]]

## Pure core

The `Ladybug` library has no native dependency: values, decoding, schema, the typed Cypher language, the ORM and the in-memory backend all run in the editor with `#eval`.

- defines:: [[decisions#Phantom types over an untyped core]]

## Milestones

Each milestone is one OpenSpec change under `openspec/changes/`, implemented and archived in order.

1. `add-native-binding`: native library, connections, values, decoding, transactions.
2. `add-typed-cypher`: schema commands, typed expressions, builder, printer, `MonadGraph`.
3. `add-cypher-syntax`: `cypher%`.
4. `add-graph-orm`: CRUD, links, traversal, bulk load.
5. `add-advanced-cypher`: paths, subqueries, UNION, vector and full-text search, timeouts.
6. `add-memory-backend`: in-memory evaluator and differential tests.
7. `add-platform-support`: Linux, Windows, CI, property tests.
