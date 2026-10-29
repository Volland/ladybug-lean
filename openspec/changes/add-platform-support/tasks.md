## 1. Platforms

- [ ] 1.1 Extend the lakefile platform table for Linux x86_64 and Windows x86_64 (DLL copy, import library fallback), annotated `@tg: implements:: [[openspec:native-library#Supported platforms]]`
- [ ] 1.2 `.github/workflows/ci.yml` matrix with library cache

## 2. Property tests

- [ ] 2.1 Add Plausible; `Arbitrary`/`Shrinkable` instances per column type in `Tests/Property.lean`
- [ ] 2.2 Round-trip property on both backends, annotated `implements:: [[openspec:native-connection#Value round-trip property]]`

## 3. Tests

- [ ] 3.1 Annotate the CI-run suite and property tests with `@tg: verifies::` for each scenario

## 4. Docs and checks

- [ ] 4.1 Record the platform decisions in `tg.md/decisions.md` and `tg.md/constraints.md`; update `tg.md/architecture.md`
- [ ] 4.2 Run `tg check`, `tg ontology check` and `tg trace native-library --gaps` / `tg trace native-connection --gaps` and close every gap
