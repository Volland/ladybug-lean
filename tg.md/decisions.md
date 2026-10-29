---
type: Decision
---
# Decisions

Choices made for the Lean 4 LadybugDB library, with the alternatives rejected. Most were settled in the design interview of 2026-10-29.

## Practical library first

The library is for real Lean programs (agents, tools, knowledge-graph memory) on an embedded graph database, with types checked at compile time. Formal semantics of Cypher and proofs about queries are out of scope for v1.

status:: accepted
date:: 2026-10-29

## Hybrid typed DSL

Queries are values of one typed core: a monadic builder builds them, and a `cypher%` syntax elaborates into the same builder calls. Raw Cypher text stays as an escape hatch.

Rejected: builder only (reads unlike Cypher), typed strings only (no composition), raw strings with decoders only (no checking).

status:: accepted
date:: 2026-10-29

- motivated_by:: [[decisions#Practical library first]]

## Phantom types over an untyped core

The core AST is untyped and stores every value as a parameter; `Expr α` is a phantom wrapper whose combinators enforce types when a query is built.

Rejected: an intrinsically typed GADT, which is heavier for the syntax and the evaluator and fits Cypher's dynamic NULL semantics worse.

status:: accepted
date:: 2026-10-29

- motivated_by:: [[decisions#Hybrid typed DSL]]
- motivated_by:: [[decisions#Two backends one API]]

## Lean structures are the schema

Node and relationship tables are declared as Lean structures, DDL is generated from them, and the database is checked against them at runtime. Rejected: introspecting a database file at compile time, and a separate schema language.

status:: accepted
date:: 2026-10-29

## Table commands generate the metadata

`node_table T (key := k) (label := "L")` and `rel_table R (from := A) (to := B)` generate instances and the `T.Var` companion. A bare `deriving NodeTable` remains as shorthand for the defaults.

status:: accepted
date:: 2026-10-29

- motivated_by:: [[constraints#Deriving takes no arguments]]
- motivated_by:: [[decisions#Lean structures are the schema]]

## Full three-valued logic

Every predicate has type `Expr (Option Bool)`, value nullability is tracked from `Option` fields, OPTIONAL MATCH and aggregates, and WHERE keeps only true rows.

Rejected: ignoring NULL in types, and tracking nullability while letting predicates be plain `Bool`.

status:: accepted
date:: 2026-10-29

## Two backends one API

`MonadGraph` is the main abstraction, with a native backend (`LbugM`) and a pure in-memory backend (`MemM`) that interprets the full v1 AST.

The in-memory backend is user-facing and also the differential-testing oracle. `MonadLbug` carries native-only extras.

status:: accepted
date:: 2026-10-29

- motivated_by:: [[decisions#Practical library first]]

## Runtime monad over ReaderT and ExceptT

`LbugM := ReaderT Connection (ExceptT Ladybug.Error IO)`, with structured errors and transaction brackets that commit, or roll back on error. Rejected: plain IO with string errors, an indexed transaction monad, and a free monad.

status:: accepted
date:: 2026-10-29

## Repository not Hibernate

The ORM offers typed CRUD and merge, relationship links, traversal helpers and bulk loading, as generic functions over the table classes. No identity map, lazy loading, change tracking or migrations.

status:: accepted
date:: 2026-10-29

## Track the latest Ladybug release

The build downloads the official precompiled library at the version in `lbug.lock`; `lake run lbug-update` moves the lock to the latest release.

`LBUG_LIB_DIR` overrides the download. Rejected: a fixed old pin, a local build only, building from source.

status:: accepted
date:: 2026-10-29

- motivated_by:: [[constraints#Storage format changes between releases]] {note: "lock file keeps builds reproducible between deliberate updates"}

## Ownership in C external objects

Each native handle is a Lean external object whose C payload holds a reference to its parent object (result to connection, connection to database), released in the finalizer after the native destroy.

status:: accepted
date:: 2026-10-29

- motivated_by:: [[constraints#Database outlives connections]] {weight: primary}
- motivated_by:: [[constraints#Lean FFI ownership rules]]

## Rows are copied out eagerly

The shim converts each flat tuple into Lean `Value`s before advancing the cursor, so no native value handle reaches Lean.

status:: accepted
date:: 2026-10-29

- motivated_by:: [[constraints#Flat tuple is reused]] {weight: primary}

## Spec first then vertical slices

All seven milestones are specified as OpenSpec changes before any code, then implemented and archived in order: native binding, typed core, syntax, ORM, advanced Cypher, memory backend, platform support.

status:: accepted
date:: 2026-10-29
