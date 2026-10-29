# graph-orm Specification

## Purpose
Repository-style operations on declared node and relationship tables (create, read, update, delete, link, traverse and bulk load), the same on every backend.

## Requirements

### Requirement: Node CRUD
For every declared node table the library SHALL provide: insert a value (failing with a constraint error if its key exists), upsert a value (create it, or overwrite all properties of the node with its key), get by key (returning `none` if absent), find all, find by a typed predicate, update a value by its key (failing with a not-found error if absent), delete by key (failing if the node still has relationships), and detach delete by key.

#### Scenario: Insert then get
- **WHEN** `Person.mk 1 "Ann" (some 30)` is inserted and person 1 is fetched
- **THEN** the fetch returns that value

#### Scenario: Duplicate insert
- **WHEN** a person with key 1 is inserted twice
- **THEN** the second insert fails with a constraint error and the first value is unchanged

#### Scenario: Upsert overwrites
- **WHEN** person 1 is upserted with name "Bea" after being inserted as "Ann"
- **THEN** fetching person 1 returns name "Bea" and there is still one person

#### Scenario: Get missing
- **WHEN** person 99 is fetched and does not exist
- **THEN** the result is `none`

#### Scenario: Update missing
- **WHEN** person 99 is updated and does not exist
- **THEN** a not-found error is raised

#### Scenario: Delete with relationships
- **WHEN** a person with a `WorksAt` relationship is deleted, then detach deleted
- **THEN** the delete fails and the detach delete removes the person and the relationship

#### Scenario: Find by predicate
- **WHEN** persons aged 20, 40 and NULL exist and persons with `age > 30` are found
- **THEN** only the person aged 40 is returned

### Requirement: Relationship links
The library SHALL create a relationship from a relationship value between two nodes given by key, typed by the declared endpoints. It SHALL fail with a not-found error if either endpoint is missing. It SHALL also list the relationships between two nodes, and delete the relationships of a table between two nodes.

#### Scenario: Link and list
- **WHEN** person 1 is linked to company "ACME" with `WorksAt.mk 2020`
- **THEN** listing `WorksAt` between them returns `#[WorksAt.mk 2020]`

#### Scenario: Link with missing endpoint
- **WHEN** person 1 is linked to company "Nope", which does not exist
- **THEN** a not-found error is raised and no relationship is created

#### Scenario: Unlink
- **WHEN** the `WorksAt` relationships between person 1 and "ACME" are deleted
- **THEN** listing them returns an empty array and both nodes still exist

### Requirement: Traversal helpers
For a node and a relationship table, the library SHALL return the outgoing neighbours (destination nodes with the relationship values) and the incoming neighbours (source nodes with the relationship values), typed by the declared endpoints.

#### Scenario: Outgoing neighbours
- **WHEN** person 1 works at "ACME" since 2020 and at "Init" since 2022
- **THEN** the outgoing `WorksAt` neighbours of person 1 are those two companies paired with their `WorksAt` values

#### Scenario: Incoming neighbours
- **WHEN** persons 1 and 2 work at "ACME"
- **THEN** the incoming `WorksAt` neighbours of "ACME" are persons 1 and 2

### Requirement: Batched insert
The library SHALL insert or upsert an array of node values, or an array of (source key, relationship value, destination key) triples, in batches of a configurable size (default 1000), each batch one parameterised query. Within a transaction, a failing batch SHALL roll back the whole load.

#### Scenario: Insert ten thousand nodes
- **WHEN** 10,000 persons are inserted in batches of 1000
- **THEN** 10 queries are executed and counting persons returns 10,000

#### Scenario: Failure rolls back
- **WHEN** a batched insert inside a transaction contains a duplicate key in its third batch
- **THEN** a constraint error is raised and counting persons returns the count from before the load

### Requirement: File import
On the native backend, the library SHALL load a node or relationship table from a CSV or Parquet file whose columns match the declared table, and report Ladybug's error if they do not.

#### Scenario: CSV import
- **WHEN** a CSV with a header row `id,name,age` and three rows is imported into `Person`
- **THEN** counting persons returns 3 and the values match the file
