## 1. Repository operations

- [ ] 1.1 `Ladybug/ORM.lean`: node CRUD, annotated `@tg: implements:: [[openspec:graph-orm#Node CRUD]]`
- [ ] 1.2 Relationship link, list and unlink, annotated `implements:: [[openspec:graph-orm#Relationship links]]`
- [ ] 1.3 Outgoing and incoming neighbours, annotated `implements:: [[openspec:graph-orm#Traversal helpers]]`

## 2. Bulk

- [ ] 2.1 `Ladybug/ORM/Bulk.lean`: batched insert and upsert, annotated `implements:: [[openspec:graph-orm#Batched insert]]`
- [ ] 2.2 CSV and Parquet import on the native backend, annotated `implements:: [[openspec:graph-orm#File import]]`

## 3. Tests

- [ ] 3.1 Native integration tests for every scenario, each annotated `@tg: verifies::` directly above the test

## 4. Docs and checks

- [ ] 4.1 Record the decisions in `tg.md/decisions.md`; update `tg.md/architecture.md` (ORM section) and its `openspec:` frontmatter
- [ ] 4.2 Run `tg check`, `tg ontology check` and `tg trace graph-orm --gaps` and close every gap
