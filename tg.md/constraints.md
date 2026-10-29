---
type: Constraint
---
# Constraints

Rules this project did not choose: behaviour of LadybugDB, of Lean's runtime and of its build tool that the design has to respect.

## Database outlives connections

A Ladybug connection stores a raw pointer to its database, so destroying a database before all of its connections, prepared statements and query results are destroyed is undefined behaviour.

source:: Ladybug sources (`main/connection.h`) and the Rust binding's `Connection<'a>` lifetime

- constrains:: [[decisions#Ownership in C external objects]] {strength: must}

## Flat tuple is reused

`lbug_query_result_get_next` refills one flat tuple per result, and values read from it are borrowed from the tuple and the result, so they are invalid after the next call or after the result is destroyed.

source:: Ladybug C API (`c_api/flat_tuple.cpp`) and go-ladybug's finalizer race tests

- constrains:: [[decisions#Rows are copied out eagerly]] {strength: must}

## Transactions are Cypher statements

The C API has no transaction functions: transactions are the Cypher statements `BEGIN TRANSACTION [READ ONLY]`, `COMMIT` and `ROLLBACK` on one connection, and anything outside them auto-commits.

source:: Ladybug docs, `concurrency.md` and the C API header

- constrains:: [[decisions#Runtime monad over ReaderT and ExceptT]] {strength: must, note: "transaction brackets issue BEGIN/COMMIT/ROLLBACK"}

## One writer at a time

One process may hold one read-write database object, or several read-only ones, and only one write transaction can be active at a time, while many read transactions can run concurrently.

source:: Ladybug docs, `concurrency.md`

- constrains:: [[decisions#Two backends one API]] {strength: must, note: "MemM must reject a second concurrent writer the same way"}

## Storage format changes between releases

Ladybug changes its on-disk storage version between releases and refuses to open files written by another storage version.

source:: Ladybug release notes; local build 0.11.2.2 reports storage version 39

- constrains:: [[decisions#Track the latest Ladybug release]] {strength: must}

## Lean FFI ownership rules

Lean external objects are reference counted. Arguments are owned unless marked `@&`, return values are owned, and a finalizer may run on whichever thread drops the last reference, so every native destroy must be safe from any thread.

source:: Lean reference manual, Foreign Function Interface; `lean.h` v4.35

- constrains:: [[decisions#Ownership in C external objects]] {strength: must}

## Deriving takes no arguments

Lean 4 `deriving` clauses cannot take per-type arguments, so a deriving handler cannot be told a table's key, label or relationship endpoints.

source:: Lean 4 deriving handler API

- constrains:: [[decisions#Table commands generate the metadata]] {strength: must}

## External library linking in Lake

Lake's `extern_lib` is deprecated in favour of custom targets with `moreLinkObjs`/`moreLinkLibs`, and linking a prebuilt shared library needs explicit `-L`, `-l` and rpath arguments.

source:: Lake README for v4.35; lean4 `tests/lake/examples/ffi`

- constrains:: [[decisions#Track the latest Ladybug release]] {strength: should, note: "fetched library is linked with -L, -l and rpath"}
