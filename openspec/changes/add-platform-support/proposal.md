## Why

M1–M6 are built and tested on macOS arm64 only. Agents and servers usually run on Linux, and the platform list chosen for v1 includes Windows. Each platform links the native library differently. M7 also adds property-based round-trip tests, which give the value model the broad coverage the per-scenario tests cannot.

## What Changes

- Fetch and link the official Ladybug library on Linux x86_64 and Windows x86_64 in addition to macOS arm64.
- Continuous integration that builds and runs the whole test suite on all three platforms.
- Property-based tests that round-trip generated values of every supported type through bind, store and decode on both backends.

## Capabilities

### New Capabilities

None.

### Modified Capabilities
- `native-library`: adds the supported-platform requirement.
- `native-connection`: adds the value round-trip property requirement.

## Impact

- `lakefile.lean` platform table; `.github/workflows/ci.yml`; `Tests/Property.lean` with generators.
- Depends on [[openspec:native-library#Pinned library version]] and [[openspec:native-connection#Value model]].
- Requirements added: [[openspec:native-library#Supported platforms]], [[openspec:native-connection#Value round-trip property]].
