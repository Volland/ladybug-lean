## ADDED Requirements

### Requirement: Value round-trip property
For every column type a table can declare, any generated value of that type, including NULLs, extreme integers, non-ASCII and empty strings, empty lists, nested structs and every float edge case Ladybug stores (infinities, negative zero), SHALL decode to an equal value after it is bound as a parameter, stored in a node and read back, on both the native and in-memory backends.

#### Scenario: Generated round trips
- **WHEN** the property suite runs 200 generated values per column type
- **THEN** every value round-trips on both backends

#### Scenario: Counterexample reported
- **WHEN** a round trip fails
- **THEN** the suite prints the column type and the shrunk value that failed
