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

## Absolute install name instead of rpath

The fetch step rewrote the downloaded macOS library's install name to its absolute path, so executables loaded it without an rpath. Superseded once Linux and Windows were added.

Rejected: rpath link arguments, because a library's `moreLinkArgs` do not reach dependent executables in Lake.

status:: superseded
date:: 2026-10-29

- motivated_by:: [[constraints#External library linking in Lake]] {weight: primary}

## Values built through exported Lean constructors

The C shim builds `Value`s by calling `@[export]`ed Lean constructor functions, and builds native parameters through one extern per kind, so C never depends on the memory layout of a Lean inductive.

Rejected: allocating Lean constructor objects in C, which hard-codes constructor indices and scalar field offsets.

status:: accepted
date:: 2026-10-29

- motivated_by:: [[constraints#Lean FFI ownership rules]]

## Literals typed from the other operand

Binary operators take two independently typed operands related by a `Compat` class, and default instances make an untyped literal take the other operand's type, so `p.age >. 30` checks `30` as an `Int64`.

Rejected: homogeneous operands with coercions, which reject a non-nullable operand compared with a nullable one, or lose nullability in arithmetic.

status:: accepted
date:: 2026-10-29

- motivated_by:: [[decisions#Full three-valued logic]]

## Pattern functions instead of arrow notation

Relationship patterns are built with `out p R (node T)`, `inc …` and `both …` rather than `p -[R]-> T` notation, since a `]-` token would change how every importing file lexes `xs[i]-1`.

The `cypher%` syntax gives the arrow form.

status:: accepted
date:: 2026-10-29

- motivated_by:: [[decisions#Hybrid typed DSL]]

## Cypher keywords parsed as non-reserved symbols

`cypher%` keywords are non-reserved symbols in upper, lower and capitalized case, and keywords that start a trailing rule (`AND`, `IS`, `IN`) also list `ident` among their first tokens, so no Cypher keyword becomes a reserved Lean token.

Rejected: reserved tokens such as `MATCH` or `]-`, which would change how every importing file lexes.

status:: accepted
date:: 2026-10-29

- motivated_by:: [[constraints#Trailing parsers of identifiers are indexed under ident]] {weight: primary}

## A query ends where its indentation does

The first `cypher%` clause may start anywhere, on the same line or the next, and every later clause must start at or right of its column. Text after the query, such as `return q` in a `do` block, is therefore never read as a clause.

status:: accepted
date:: 2026-10-29

## Differential testing against Ladybug

The in-memory evaluator is checked against Ladybug on generated graphs and queries, with counterexamples shrunk by removing nodes and relationships. It found the self-loop and shortest-path semantics that the evaluator now follows.

status:: accepted
date:: 2026-10-29

- motivated_by:: [[decisions#Two backends one API]]
- motivated_by:: [[constraints#Ladybug path semantics]]

## Load Ladybug at runtime

The C shim loads the Ladybug library with `dlopen`/`LoadLibrary` from the absolute path the build fetched (or `LBUG_LIBRARY`) and calls it through pointers typed from `lbug.h`, so nothing links against it.

This avoids rpath, SONAME and import-library issues on every platform, including MinGW linking an MSVC DLL, and works the same in dependent packages.

status:: accepted
date:: 2026-10-29

- supersedes:: [[decisions#Absolute install name instead of rpath]] {since: "M7", reason: "Linux SONAME and Windows import libraries"}
- motivated_by:: [[constraints#External library linking in Lake]]
- motivated_by:: [[constraints#Extensions resolve the library's global symbols]]

## Own generators for property tests

Value round-trip properties use the project's seeded generators and shrinking, as the differential suite does, instead of Plausible.

Lake has no test-only dependencies, so requiring Plausible would make every package that depends on this one fetch it.

status:: accepted
date:: 2026-10-29

## Column writes are cast to the column type

Values written to list and struct columns are wrapped in `CAST(… AS <column type>)`, struct values become literals with one parameter per field, and empty lists are printed inline as `[]`.

An empty list or a NULL struct field has no type of its own, and Ladybug types parameters from their context.

status:: accepted
date:: 2026-10-29

- motivated_by:: [[constraints#Parameter types come from their context]]
- motivated_by:: [[constraints#Empty list parameters need an element type]]

## Spec first then vertical slices

All seven milestones are specified as OpenSpec changes before any code, then implemented and archived in order: native binding, typed core, syntax, ORM, advanced Cypher, memory backend, platform support.

status:: accepted
date:: 2026-10-29
