## Purpose

One backend-independent interface for running typed queries, statements, schema setup and transactions, so the same program runs on the native database or on the in-memory backend.

## ADDED Requirements

### Requirement: Backend-independent execution
Code written against the graph-monad interface SHALL be able to run a typed query and get its decoded rows, run a statement and get the number of affected rows where the backend reports it, apply and verify a schema, and run a body in a read-write or read-only transaction, without naming a backend.

#### Scenario: Generic function runs on the native backend
- **WHEN** a function polymorphic in the backend creates two persons and counts them, and is run on the native backend
- **THEN** it returns 2

#### Scenario: Read-only transaction rejects writes
- **WHEN** a create query runs inside a read-only transaction
- **THEN** a transaction or query error is raised and nothing is written

### Requirement: Native backend
The native runtime monad from M1 SHALL implement the graph-monad interface by printing each query, preparing it (caching prepared statements per connection by query text), binding its parameter map and decoding its rows with the query's result type.

#### Scenario: Prepared statement reuse
- **WHEN** the same typed query runs 100 times on one connection with different parameters
- **THEN** it is prepared once and every run returns the right rows
