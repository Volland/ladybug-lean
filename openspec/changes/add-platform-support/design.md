## Context

Release artifacts exist for every target: `liblbug-linux-x86_64.tar.gz`, `liblbug-osx-arm64.tar.gz` and `liblbug-windows-x86_64.zip`. Lean on Windows uses its bundled clang targeting the MinGW-w64 ABI, while the Ladybug DLL is built with MSVC. Ladybug's API is plain C, so the import library and the DLL are ABI-compatible at the C boundary.

## Goals / Non-Goals

**Goals:**
- One platform table in the lakefile, mapping (OS, arch) to the asset name, library file names and link flags.

**Non-Goals:**
- Linux and macOS aarch64/x86_64 variants beyond those three (the table makes adding them a one-line change).
- Static linking.

## Decisions

### Platform table
| Platform | Asset | Link | Runtime lookup |
|---|---|---|---|
| macOS arm64 | `liblbug-osx-arm64.tar.gz` | `-L<dir> -llbug` | `-Wl,-rpath,<dir>` |
| Linux x86_64 | `liblbug-linux-x86_64.tar.gz` | `-L<dir> -llbug` | `-Wl,-rpath,<dir>` |
| Windows x86_64 | `liblbug-windows-x86_64.zip` | `<dir>/lbug_shared.lib` | DLL copied next to each built executable |

Windows has no rpath, so a post-link step copies the DLL into `.lake/build/bin`.

### CI
GitHub Actions matrix on `macos-14`, `ubuntu-latest` and `windows-latest`, with elan installed from `lean-toolchain`, `.lake/lbug` cached by lock-file hash, and `lake build` followed by `lake exe tests`.

### Property tests with Plausible
Use Plausible, Lean's property-testing library, with `Arbitrary` instances for each column type and `Shrinkable` for counterexamples. Each property runs on both backends in one test.

## Risks / Trade-offs

- [MinGW clang cannot link the MSVC import library] → fall back to generating a MinGW import library from the DLL with `llvm-dlltool` (bundled with Lean's clang) at fetch time.
- [Ladybug release assets are renamed] → the platform table is the only place names appear; the fetch error says which asset was missing.
