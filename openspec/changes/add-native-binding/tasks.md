## 1. Build and native library

- [ ] 1.1 Add `lean-toolchain` (v4.35.0), `lbug.lock` and `lakefile.lean` with the fetch target, `LBUG_LIB_DIR` override, shim target, `LadybugCore` and `LadybugNative` libraries and test executable
- [ ] 1.2 Add `lake run lbug-update` script that resolves the latest release and rewrites `lbug.lock`
- [ ] 1.3 Annotate the fetch target with `@tg: implements:: [[openspec:native-library#Pinned library version]]`, the override with `[[openspec:native-library#Library override]]` and the link args with `[[openspec:native-library#Executables find the library at runtime]]`

## 2. Pure core

- [ ] 2.1 `Ladybug/Value.lean`: the `Value` inductive and supporting scalar types, annotated `implements:: [[openspec:native-connection#Value model]]`
- [ ] 2.2 `Ladybug/Error.lean`: `Ladybug.Error`, annotated `implements:: [[openspec:native-connection#Structured errors]]`
- [ ] 2.3 `Ladybug/Decode.lean`: `FromValue`, `ToValue`, `FromRow` with instances for scalars, Option, tuples, Array/List, Value, and a `deriving FromRow` handler for structures, annotated `implements:: [[openspec:native-connection#Row decoding]]`

## 3. Native shim and safe API

- [ ] 3.1 `c/lbug_shim.c`: external classes for database, connection, prepared statement, query result with parent references; value conversion to `Value`; parameter binding from `Value`
- [ ] 3.2 `Ladybug/FFI.lean`: `@[extern]` declarations, annotated `implements:: [[openspec:native-connection#Handle lifetimes]]`
- [ ] 3.3 `Ladybug/Native.lean`: `Database.open`, `Connection`, `query`, `prepare`/`execute`, `LbugM`, `withTx`/`withReadTx`, annotated with `[[openspec:native-connection#Open database]]`, `[[openspec:native-connection#Run Cypher text]]`, `[[openspec:native-connection#Prepared parameters]]`, `[[openspec:native-connection#Transactions]]`
- [ ] 3.4 Storage version check on open, annotated `implements:: [[openspec:native-library#Storage version check]]`

## 4. Tests

- [ ] 4.1 Test harness executable `Tests/Main.lean` with a tiny assertion helper
- [ ] 4.2 One test per scenario of `native-connection` and `native-library`, each annotated `@tg: verifies:: [[openspec:<capability>#<Requirement>#<Scenario>]]` directly above it

## 5. Docs and checks

- [ ] 5.1 Record decisions and constraints in `tg.md/decisions.md` and `tg.md/constraints.md` with typed edges
- [ ] 5.2 Update `tg.md/architecture.md` (Native layer section) and list both capabilities in its `openspec:` frontmatter
- [ ] 5.3 Run `tg check`, `tg ontology check`, `tg trace native-library --gaps` and `tg trace native-connection --gaps` and close every gap
