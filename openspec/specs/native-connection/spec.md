# native-connection Specification

## Purpose
Safe access to a Ladybug database from Lean through the native library: databases, connections, Cypher execution with parameters, the value model, row decoding, transactions and errors.

## Requirements

### Requirement: Open database
The library SHALL open an on-disk database at a path, an in-memory database for the path `:memory:`, and a read-only database when asked, and SHALL open any number of connections to one database.

#### Scenario: In-memory database
- **WHEN** `:memory:` is opened and a connection runs `RETURN 1 AS x`
- **THEN** the result has one row whose column `x` is 1

#### Scenario: On-disk persistence
- **WHEN** a node is created in an on-disk database, the database is closed and reopened
- **THEN** the node is returned by a query on the reopened database

#### Scenario: Read-only rejects writes
- **WHEN** a database is opened read-only and a connection runs a CREATE statement
- **THEN** the statement fails with a query error and the database is unchanged

### Requirement: Handle lifetimes
No sequence of operations on the safe API SHALL cause use-after-free or a crash: a connection SHALL keep its database alive, and a query result or prepared statement SHALL keep its connection alive, regardless of the order in which Lean drops references.

#### Scenario: Database dropped before connection
- **WHEN** the last Lean reference to a database is dropped while a connection to it is still used to run queries
- **THEN** the queries succeed and the database is released only after the connection is released

#### Scenario: Many short-lived results
- **WHEN** ten thousand queries are run in a loop and their results are discarded
- **THEN** the program completes without a crash and memory use stays bounded

### Requirement: Run Cypher text
A connection SHALL execute a Cypher text containing one or more statements and return every row of every statement's result, with column names, in order.

#### Scenario: Multiple statements
- **WHEN** the text `CREATE NODE TABLE P(id INT64, PRIMARY KEY(id)); CREATE (:P {id: 1}); MATCH (p:P) RETURN p.id` is executed
- **THEN** the last statement's result has one row with value 1, and the earlier statements succeed

#### Scenario: Syntax error
- **WHEN** the text `MATC (n) RETURN n` is executed
- **THEN** a query error is raised carrying Ladybug's message

### Requirement: Prepared parameters
The library SHALL prepare a Cypher statement once and execute it many times with named parameters bound from Lean values, and SHALL never splice parameter values into the Cypher text.

#### Scenario: Bind scalar and nested parameters
- **WHEN** `RETURN $a + 1 AS x, $xs AS xs, $s AS s` is executed with `a := 41`, `xs := [1,2,3]` and `s := {name: "x", n: 2}`
- **THEN** the row decodes to `42`, `#[1,2,3]` and a struct with fields `name = "x"` and `n = 2`

#### Scenario: Injection-shaped string is data
- **WHEN** a parameter holds the string `"x'}) DETACH DELETE n //"` and is returned
- **THEN** it is returned unchanged and no data is modified

#### Scenario: Missing parameter
- **WHEN** a prepared statement referencing `$a` is executed without binding `a`
- **THEN** a bind error is raised before execution

### Requirement: Value model
Every value Ladybug can return SHALL be represented as a Lean `Value`, including NULL, booleans, all signed and unsigned integer widths, int128, float, double, decimal, string, blob, UUID, date, timestamps (all precisions and with time zone), interval, internal ID, list, array, struct, map, union, node, relationship and recursive relationship (path) values. Values SHALL be copied out of the native result so they remain valid after the result is released.

#### Scenario: Round trip of every scalar kind
- **WHEN** a query returns one literal or cast of each scalar kind
- **THEN** each decodes to the matching `Value` constructor with the same content

#### Scenario: Node and relationship values
- **WHEN** `MATCH (a)-[r]->(b) RETURN a, r, b` returns a row
- **THEN** `a` and `b` decode to node values with ID, label and properties, and `r` decodes to a relationship value with ID, label, source ID, destination ID and properties

#### Scenario: Path values
- **WHEN** a variable-length match returns a path
- **THEN** it decodes to a path value with its nodes and relationships in order

#### Scenario: Values outlive the result
- **WHEN** rows are collected into an array and the query result is released
- **THEN** every value in the array is still readable and correct

### Requirement: Row decoding
The library SHALL decode result rows into Lean types through type classes: scalars, `Option` (NULL as `none`), tuples, `Array`/`List`, `Value` itself, and user structures by column name. A value that does not match the requested type SHALL raise a decode error naming the column, the expected type and the actual value kind.

#### Scenario: Decode tuple rows
- **WHEN** `RETURN 'a' AS s, 1 AS n` is queried as `String × Int64`
- **THEN** the result is `#[("a", 1)]`

#### Scenario: NULL into Option and into a non-Option
- **WHEN** `RETURN NULL AS x` is queried once as `Option Int64` and once as `Int64`
- **THEN** the first returns `#[none]` and the second raises a decode error for column `x`

#### Scenario: Decode structure by column names
- **WHEN** a structure with fields `name : String` and `age : Int64` is derived as a row type and `RETURN 30 AS age, 'b' AS name` is queried as it
- **THEN** the result is one structure with `name = "b"` and `age = 30`

### Requirement: Transactions
The native runtime SHALL provide read-write and read-only transaction brackets on a connection that commit when the body succeeds and roll back when the body raises an error, and SHALL reject nested transaction brackets on the same connection.

#### Scenario: Commit on success
- **WHEN** a node is created inside a read-write transaction bracket that completes normally
- **THEN** the node is visible to a new connection afterwards

#### Scenario: Roll back on error
- **WHEN** a node is created inside a read-write transaction bracket that then raises an error
- **THEN** the error propagates and the node is not visible afterwards

#### Scenario: Nested bracket rejected
- **WHEN** a transaction bracket is opened inside another on the same connection
- **THEN** a transaction error is raised and the outer transaction rolls back

### Requirement: Structured errors
Every failure SHALL be reported as a `Ladybug.Error` distinguishing at least: database open, storage mismatch, query, prepare, bind, decode, transaction, and native-call failures, each carrying a human-readable message, and the runtime monad SHALL let callers catch and inspect these errors.

#### Scenario: Catch a query error
- **WHEN** a failing query runs inside `try ... catch` in the runtime monad
- **THEN** the handler receives a query error whose message is Ladybug's error text
