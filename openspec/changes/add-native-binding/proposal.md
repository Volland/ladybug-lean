## Why

There is no way to use LadybugDB (or any graph database) from Lean 4. Every later layer of this library — typed Cypher, the ORM, the in-memory backend's differential tests — needs a safe, memory-correct native binding first, so this is milestone M1.

## What Changes

- Fetch the official precompiled `liblbug` for the host platform at build time, at a version recorded in a lock file, with an override for a local build.
- A C shim and `@[extern]` layer over the Ladybug C API, with reference-counted handles whose lifetimes cannot outlive their parents.
- A safe native API: open a database, open connections, run Cypher text, prepare and bind parameters, iterate results.
- A Lean `Value` model of every Ladybug value kind, copied out of the native result eagerly.
- `FromValue` / `FromRow` / `ToValue` classes for decoding rows into Lean types and binding Lean values as parameters.
- `LbugM`, the native runtime monad, with structured `Ladybug.Error`, and `withTx` / `withReadTx` transaction brackets.
- A storage-version check when a database is opened.

## Capabilities

### New Capabilities
- `native-library`: obtaining, pinning, linking and version-checking the Ladybug shared library.
- `native-connection`: databases, connections, raw and prepared Cypher execution, values, row decoding, transactions and errors on the native backend.

### Modified Capabilities

None.

## Impact

- New files: `lakefile.lean`, `lean-toolchain` (v4.35.0), `lbug.lock`, `c/lbug_shim.c`, `Ladybug/Value.lean`, `Ladybug/Error.lean`, `Ladybug/Decode.lean`, `Ladybug/FFI.lean`, `Ladybug/Native.lean`, `Ladybug.lean`, tests under `Tests/`.
- New external dependency: LadybugDB release artifacts from `github.com/LadybugDB/ladybug/releases` (network access on first build).
- tg.md: adds `tg.md/architecture.md`, `tg.md/decisions.md`, `tg.md/constraints.md`. The constraints that bind this area are the Ladybug lifecycle rules ([[constraints#Database outlives connections]], [[constraints#Flat tuple is reused]]), [[constraints#Transactions are Cypher statements]] and [[constraints#Lean FFI ownership rules]].
- Requirements added: [[openspec:native-library#Pinned library version]], [[openspec:native-library#Library override]], [[openspec:native-library#Storage version check]], [[openspec:native-connection#Open database]], [[openspec:native-connection#Handle lifetimes]], [[openspec:native-connection#Run Cypher text]], [[openspec:native-connection#Prepared parameters]], [[openspec:native-connection#Value model]], [[openspec:native-connection#Row decoding]], [[openspec:native-connection#Transactions]], [[openspec:native-connection#Structured errors]].
