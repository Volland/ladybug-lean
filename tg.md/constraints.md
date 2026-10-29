---
type: Constraint
openspec: [native-library, native-connection]
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

- constrains:: [[decisions#Track the latest Ladybug release]] {strength: should, note: "fetched library is linked through moreLinkLibs"}

## Interpreter cannot run native initializers

When Lean elaborates a module that imports one with `initialize` calling an `@[extern]` function, the interpreter aborts because the native symbol is not loaded. Native setup must therefore happen lazily on first use.

source:: observed with Lean v4.35.0 while building `LadybugNative`

- constrains:: [[decisions#Ownership in C external objects]] {strength: must, note: "external classes are registered on first allocation"}

## Union values hide the active member

A Ladybug union value stores only its active member, and the C API does not say which member of a multi-member union is active, so its tag is known only for single-member unions.

source:: Ladybug `Value::toString` for UNION and the C struct accessors

- constrains:: [[decisions#Rows are copied out eagerly]] {strength: must, note: "union tag is empty when unknown"}

## Empty list parameters need an element type

`lbug_value_create_list` rejects zero elements and Ladybug cannot bind a `LIST(ANY)` parameter, so an empty list parameter must be given a concrete element type.

source:: Ladybug C API `value.cpp` and runtime error "Trying to a create a vector with ANY type"

- constrains:: [[decisions#Values built through exported Lean constructors]] {strength: must, note: "empty lists are sent as INT64[]"}

## Aggregates over no rows are NULL

Ladybug returns NULL for `sum`, `avg`, `min` and `max` over no rows, 0 for `count` and an empty list for `collect`, and `sum` of INT64 values is an INT128.

source:: observed with Ladybug 0.22.1

- constrains:: [[decisions#Full three-valued logic]] {strength: must, note: "sum is typed Option"}

## CREATE takes no property map parameter

Ladybug does not parse `CREATE (n:L $props)`, so a node or relationship created from a Lean value is printed with one parameter per property.

source:: Ladybug 0.22.1 parser error "expected rule oC_SingleQuery"

- constrains:: [[decisions#Phantom types over an untyped core]] {strength: must}

## Trailing parsers of identifiers are indexed under ident

Lean finds the leading parsers of an identifier token by its text only in categories declared with `behavior := symbol` or `both`, and always finds trailing parsers of an identifier token under `ident`.

Keyword operators must therefore list `ident` among their first tokens.

source:: Lean v4.35 `Lean.Parser.indexed` and `trailingLoop`

- constrains:: [[decisions#Cypher keywords parsed as non-reserved symbols]] {strength: must}

## List parameters need one element type

Every element of a Ladybug list value must have the same type, so a batch whose rows mix empty and non-empty lists, or NULL and typed values, is rejected unless the empty lists and NULLs are given a sibling's type.

source:: Ladybug C API `lbug_value_create_list`; observed with UNWIND batches in 0.22.1

- constrains:: [[decisions#Repository not Hibernate]] {strength: must, note: "batches are harmonized before binding"}

## No CALL subqueries

Ladybug 0.22 parses `EXISTS { }` and `COUNT { }` subqueries but not `CALL { }` subqueries, so the typed language offers the first two only.

source:: Ladybug 0.22.1 parser error on `CALL { … }`

- constrains:: [[decisions#Hybrid typed DSL]] {strength: must, note: "no CALL subquery builder or syntax"}

## Timeouts and interrupts are checked between work units

Ladybug checks a query's timeout and interrupt flag only between units of pipeline work and reports both as "Interrupted.", so a single long unit such as one big UNWIND overruns its timeout.

source:: observed with Ladybug 0.22.1

- constrains:: [[decisions#Runtime monad over ReaderT and ExceptT]] {strength: must, note: "the connection records interrupts to tell them from timeouts"}

## Index procedures cannot be prepared

`CALL CREATE_VECTOR_INDEX` and similar procedures expand to several statements, which Ladybug refuses to prepare, and a `CALL … YIELD` clause cannot be followed directly by WHERE.

source:: Ladybug 0.22.1 errors "We do not support prepare multiple statements" and "expected rule oC_SingleQuery"

- constrains:: [[decisions#Phantom types over an untyped core]] {strength: must, note: "queries without parameters run unprepared; WHERE after CALL gets WITH *"}

## Path variables include endpoints

In Ladybug a path variable `p = (a)-[:R*1..3]->(b)` holds every node on the path, while a relationship variable `[e:R*1..3]` holds only the intermediate nodes.

source:: observed with Ladybug 0.22.1

- constrains:: [[decisions#Phantom types over an untyped core]] {strength: must, note: "variable-length matches bind a path variable"}
