## 1. Platforms

- [x] 1.1 Platform table for macOS, Linux and Windows and runtime loading of the library (`c/lbug_dyn.h`), annotated `@tg: implements:: [[openspec:native-library#Supported platforms]]`
- [x] 1.2 `.github/workflows/ci.yml` matrix with library cache

## 2. Property tests

- [x] 2.1 Generators and shrinking per column type in `Tests/Property.lean` (own generators instead of Plausible)
- [x] 2.2 Round-trip property on both backends, annotated `implements:: [[openspec:native-connection#Value round-trip property]]`

## 3. Tests

- [x] 3.1 Annotate the CI-run suite and property tests with `@tg: verifies::` for each scenario

## 4. Docs and checks

- [x] 4.1 Record the platform decisions in `tg.md/decisions.md` and `tg.md/constraints.md`; update `tg.md/architecture.md`
- [x] 4.2 Run `tg check`, `tg ontology check` and `tg trace native-library --gaps` / `tg trace native-connection --gaps` and close every gap
