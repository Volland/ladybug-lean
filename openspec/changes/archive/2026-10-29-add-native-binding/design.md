## Context

The Ladybug C API (`lbug.h`, ~181 functions in v0.22.1) uses small handle structs filled through out-parameters (`lbug_database`, `lbug_connection`, `lbug_query_result`, `lbug_flat_tuple`, `lbug_value`). A spike confirmed that a Lake package on Lean v4.35.0 can compile a C shim against the release header, link the release `liblbug` (install name `@rpath/liblbug.0.dylib`) and run a query. Lifecycle rules from the Ladybug sources bind the design: see [[constraints#Database outlives connections]], [[constraints#Flat tuple is reused]] and [[constraints#Transactions are Cypher statements]].

## Goals / Non-Goals

**Goals:**
- A memory-safe native API where no drop order can crash.
- One pure value model and one decoding layer that the in-memory backend (M6) will reuse unchanged.
- Reproducible builds while tracking the latest Ladybug release.

**Non-Goals:**
- `#eval` of native queries inside the editor (pure code runs in the editor through the in-memory backend instead).
- Arrow export, extension loading and query interruption (added with `MonadLbug` extras in M5).
- Linux and Windows (M7); M1 targets macOS arm64 and keeps platform logic in one table.

## Decisions

### Ownership lives in C external objects
Each handle is a Lean external object whose C payload stores a `lean_object*` reference to its parent: a connection holds its database, a prepared statement and a query result hold their connection. The finalizer destroys the native handle and then `lean_dec`s the parent. Alternative rejected: pairing handles in Lean structures (`structure Stmt where db; stmt`) as leansqlite does, which still lets a raw handle escape and outlive its parent, and is the source of the finalizer races go-ladybug had to fix.
- motivated_by:: [[constraints#Database outlives connections]]
- motivated_by:: [[constraints#Lean FFI ownership rules]]

### Rows are copied out eagerly
The shim walks each flat tuple and converts it to a Lean `Value` tree before advancing the cursor, so no `lbug_value` handle is ever exposed to Lean. Alternative rejected: lazy value handles, which would need a parent pointer per value and break when `get_next` reuses the tuple.
- motivated_by:: [[constraints#Flat tuple is reused]]

### Conversion happens in C, through exported Lean constructors
A single C function walks a native value and builds the Lean `Value` by calling `@[export]`ed constructor functions (`lean_lbug_mk_int64`, `lean_lbug_mk_node`, …), so the C side never depends on Lean's object layout. Alternatives rejected: one `@[extern]` getter per kind called from Lean, which costs a boundary crossing per value and duplicates the type switch; and allocating Lean constructors directly in C, which hard-codes constructor indices and scalar offsets.
- motivated_by:: [[decisions#Values built through exported Lean constructors]]

### Pure core, native edge
`Ladybug.Value`, `Ladybug.Error` and `Ladybug.Decode` are pure modules with no `@[extern]`, so the in-memory backend and DSL can use them without the native library. Only `Ladybug.FFI` and `Ladybug.Native` depend on the shim, and they live in a separate `lean_lib`. This follows lean-linq's driver split.

### Version lock, fetched by the lakefile
`lbug.lock` holds one line, the Ladybug version. A custom target reads it and downloads `liblbug-<platform>.tar.gz` from the GitHub release into `.lake/lbug/<version>/<platform>/` with `curl` and `tar` if that directory is missing. `lake run lbug-update` queries the GitHub latest-release API and rewrites the lock. `LBUG_LIB_DIR` replaces the download with a copy of a local build in `.lake/lbug/override/`. The library is attached to the `LadybugNative` library as a `moreLinkLibs` `Dynlib`, and the shim as `moreLinkObjs`, so both propagate to every executable that imports it. On macOS the fetch step rewrites the library's install name to its absolute path, because a library's `moreLinkArgs` (and so an rpath) do not reach dependent executables ([[decisions#Absolute install name instead of rpath]]). Alternatives rejected: vendoring a header (drifts from the downloaded library, and the `lbug_value_get_blob` signature already changed between 0.11 and 0.22), and building Ladybug from source (very slow first build, needs a C++ toolchain).
- motivated_by:: [[decisions#Track the latest Ladybug release]]

### Errors are values in `ExceptT`
`LbugM := ReaderT Connection (ExceptT Ladybug.Error IO)`. Shim functions return `IO (Except String α)`: Ladybug failures come back as data, and the Lean wrapper maps them to the right `Ladybug.Error` constructor (open, prepare, query, bind…). `IO` errors are reserved for the shim's own failures, such as out of memory.

### Transactions are a bracket over Cypher statements
`withTx` and `withReadTx` run `BEGIN TRANSACTION` / `BEGIN TRANSACTION READ ONLY`, then `COMMIT`, or `ROLLBACK` on any error, and rethrow. A per-connection flag (an `IO.Ref` in the connection wrapper) rejects nested brackets.
- motivated_by:: [[constraints#Transactions are Cypher statements]]

### Storage check before open
Ladybug itself refuses to open a database written by another storage version and reports it in the open error. `Database.open` recognises that error and returns `.storageMismatch` carrying the linked `lbug_get_storage_version()` and Ladybug's message. We do not parse Ladybug's file format ourselves, since it is internal and changes between releases.

## Risks / Trade-offs

- [Ladybug changes its C API on update] → the shim compiles against the downloaded header, so an incompatible change fails the build loudly, never at runtime; CI builds against the lock file only.
- [Constructor indices of `Value` drift from the C code] → a single test decodes every kind and fails on mismatch; the C file names each index next to its Lean constructor.
- [Finalizers run on any thread] → every `lbug_*_destroy` is called from finalizers only, and Ladybug handles are documented thread-safe for destruction.
- [The interpreter cannot run a native `initialize`] → external classes are registered lazily on the first allocation, and no module runs native code at import time ([[constraints#Interpreter cannot run native initializers]]).
- [Union tags and empty-list types are not available from the C API] → the tag is empty for multi-member unions, and an empty list parameter is sent as `INT64[]` ([[constraints#Union values hide the active member]], [[constraints#Empty list parameters need an element type]]).
- [Download needs network on first build] → `LBUG_LIB_DIR` override for offline builds.
- [Ladybug's mismatch message wording changes] → the recognition is a substring match covered by a test that opens a database file written by an older storage version; if it stops matching, the error degrades to `.open` with the same message.
