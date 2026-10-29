# memory-backend Specification

## Purpose
A pure in-memory implementation of the graph monad that runs every typed query without the native library and agrees with Ladybug on results.

## Requirements

### Requirement: Pure graph state
The in-memory backend SHALL keep the whole database in a pure Lean value, SHALL run programs written against the graph monad without loading the native library, and SHALL be usable from `#eval` in the editor.

#### Scenario: Eval in the editor
- **WHEN** a module that does not link the native library runs `#eval` on a generic program with the in-memory backend
- **THEN** it prints the program's result

#### Scenario: Same program, two backends
- **WHEN** the generic program from the graph-monad scenario (create two persons, count them) runs on the in-memory backend
- **THEN** it returns 2

### Requirement: Full AST evaluation
The in-memory backend SHALL evaluate every query the typed language can build: all clauses, expressions with Cypher three-valued logic, aggregates with grouping, ORDER BY with NULLs sorted the way Ladybug sorts them, SKIP and LIMIT, CREATE, MERGE, SET, DELETE and DETACH DELETE, UNWIND, bounded variable-length and shortest paths, EXISTS/COUNT/CALL subqueries, UNION and UNION ALL, exact nearest-neighbour vector queries, and full-text queries. Evaluation SHALL always terminate.

#### Scenario: Three-valued logic in memory
- **WHEN** the "Unknown OR true is true" query from the cypher-query spec runs in memory
- **THEN** the same two persons are returned

#### Scenario: Paths in memory
- **WHEN** the "Shortest path" query from the cypher-query spec runs in memory
- **THEN** the path through 2 is returned

#### Scenario: Vector search in memory
- **WHEN** the "Nearest neighbours" query from the graph-search spec runs in memory
- **THEN** the same two docs are returned in the same order

### Requirement: Schema enforcement in memory
The in-memory backend SHALL reject queries on tables that have not been applied, writes that violate primary-key uniqueness, and relationships whose endpoints do not match the declared tables, raising the same error kinds as the native backend.

#### Scenario: Duplicate key in memory
- **WHEN** a person with key 1 is inserted twice in memory
- **THEN** the second insert raises a constraint error

#### Scenario: Unknown table in memory
- **WHEN** `Person` is queried before its schema is applied
- **THEN** a query error is raised

### Requirement: Snapshot transactions
Transactions on the in-memory backend SHALL apply all of their writes on commit and none on error, and read-only transactions SHALL reject writes.

#### Scenario: Rollback in memory
- **WHEN** a transaction creates a node and then raises an error
- **THEN** the node does not exist afterwards

### Requirement: Differential conformance
For randomly generated small graphs and randomly generated well-typed queries, running on the in-memory backend and on Ladybug SHALL give equal results: equal multisets of rows, and equal sequences when the query orders by a total key. Full-text queries SHALL return the same set of matched nodes, with scores compared only for order. A disagreement SHALL be reported with the graph, the printed query and both results.

#### Scenario: Differential run passes
- **WHEN** the differential suite runs 500 generated cases
- **THEN** every case agrees

#### Scenario: Disagreement is reported
- **WHEN** the evaluator is deliberately broken so that comparisons with NULL return true
- **THEN** the suite fails and prints a counterexample with its graph, query text and both results
