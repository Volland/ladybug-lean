## ADDED Requirements

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
