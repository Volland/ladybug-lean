## 1. Repository operations

- [x] 1.1 `Ladybug/ORM.lean`: node CRUD, annotated `@tg: implements:: [[openspec:graph-orm#Node CRUD]]`
- [x] 1.2 Relationship link, list and unlink, annotated `implements:: [[openspec:graph-orm#Relationship links]]`
- [x] 1.3 Outgoing and incoming neighbours, annotated `implements:: [[openspec:graph-orm#Traversal helpers]]`

## 2. Bulk

- [x] 2.1 `Ladybug/ORM.lean` (batches section): batched insert, upsert and `linkMany`, annotated `implements:: [[openspec:graph-orm#Batched insert]]`
- [x] 2.2 CSV and Parquet import on the native backend (`Repo.copyNodes`/`copyRels` in `LadybugNative/Graph.lean`), annotated `implements:: [[openspec:graph-orm#File import]]`

## 3. Tests

- [x] 3.1 Native integration tests for every scenario, each annotated `@tg: verifies::` directly above the test

## 4. Docs and checks

- [x] 4.1 Record the decisions in `tg.md/decisions.md`; update `tg.md/architecture.md` (ORM section) and its `openspec:` frontmatter
- [x] 4.2 Run `tg check`, `tg ontology check` and `tg trace graph-orm --gaps` and close every gap
