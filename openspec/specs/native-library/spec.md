# native-library Specification

## Purpose
How the Lean package obtains, pins, links and validates the native Ladybug shared library on each supported platform.

## Requirements

### Requirement: Pinned library version
The build SHALL download the official precompiled Ladybug shared library and header for the host platform at the exact version recorded in the repository lock file, and SHALL NOT change that version unless the lock file changes. An explicit update command SHALL resolve the latest Ladybug release and rewrite the lock file.

#### Scenario: First build fetches the locked version
- **WHEN** a clean checkout is built and the lock file names version V
- **THEN** the library for V is downloaded once into the build directory and the native API reports version V at runtime

#### Scenario: Rebuild does not re-download
- **WHEN** the library for the locked version is already present in the build directory
- **THEN** the build performs no network access for it

#### Scenario: Update resolves latest
- **WHEN** the update command runs and the latest Ladybug release is newer than the lock file
- **THEN** the lock file is rewritten to the latest version and the next build fetches it

### Requirement: Library override
The build SHALL use a locally provided Ladybug library directory instead of downloading when the `LBUG_LIB_DIR` environment variable names a directory containing the shared library and `lbug.h`.

#### Scenario: Local build is used
- **WHEN** `LBUG_LIB_DIR` points to a directory with a Ladybug build
- **THEN** the program links against that library and no download happens

### Requirement: Executables find the library at runtime
Executables and test programs built by the package SHALL locate the Ladybug shared library at runtime without the user setting a library search path.

#### Scenario: Run built executable directly
- **WHEN** a test executable built by the package is run from a shell with no library path variables set
- **THEN** it loads Ladybug and runs a query successfully

### Requirement: Storage version check
Opening a database SHALL fail with a storage-mismatch error, without modifying the files, when an existing database was written by a Ladybug storage version different from the linked library's.

#### Scenario: Incompatible database file
- **WHEN** a database directory created by a different storage version is opened
- **THEN** the open fails with a storage-mismatch error naming both versions

#### Scenario: Compatible or new database
- **WHEN** a new path or a database created by the same storage version is opened
- **THEN** the open succeeds

### Requirement: Supported platforms
The package SHALL build, link and pass its full test suite on macOS arm64, Linux x86_64 and Windows x86_64, using the official Ladybug release library for each platform, and continuous integration SHALL run the suite on all three for every push to `main` and every pull request.

#### Scenario: Linux build
- **WHEN** the package is built and tested on Linux x86_64 from a clean checkout
- **THEN** the build fetches the Linux library and every test passes

#### Scenario: Windows build
- **WHEN** the package is built and tested on Windows x86_64 from a clean checkout
- **THEN** the build fetches the Windows library, the test executable finds the DLL next to itself, and every test passes

#### Scenario: CI matrix
- **WHEN** a pull request is opened
- **THEN** CI runs the build and test suite on all three platforms and reports each result
