# graph-schema Specification

## Purpose
Declaring a graph's node and relationship tables as Lean structures, so that the structures are the single source of truth for queries, decoding and DDL.

## Requirements

### Requirement: Node table declaration
A Lean structure SHALL be declarable as a node table with a label (default: the structure's name) and exactly one primary-key field (default: the field named `id`). Every field type SHALL map to a Ladybug column type: `Bool`, signed and unsigned integers of every width, `Float`, `Float32`, `String`, `ByteArray` (blob), UUID, date, timestamp, interval, `Option α` (a nullable column of `α`), `Array α` (a list of `α`) and nested structures whose fields map (struct columns). Declaring a field of any other type, a missing key, or an `Option` key SHALL be a compile-time error that names the field.

#### Scenario: Default label and key
- **WHEN** `structure Person where id : Int64; name : String; age : Option Int64` is declared as a node table
- **THEN** its label is `Person`, its key is `id`, and `age` is a nullable INT64 column

#### Scenario: Custom key and label
- **WHEN** a structure `Company` with fields `name : String; founded : Int32` is declared with key `name` and label `Org`
- **THEN** its label is `Org` and its key is `name`

#### Scenario: Unsupported field type rejected
- **WHEN** a structure with a field `f : Nat → Nat` is declared as a node table
- **THEN** elaboration fails with an error naming field `f`

#### Scenario: Missing key rejected
- **WHEN** a structure with no `id` field is declared as a node table without naming a key
- **THEN** elaboration fails with an error saying a key is required

### Requirement: Relationship table declaration
A Lean structure SHALL be declarable as a relationship table between a source and a destination node table, with a label (default: the structure's name) and its fields as relationship properties. A structure with no fields SHALL be allowed for property-less relationships.

#### Scenario: Relationship with property
- **WHEN** `structure WorksAt where since : Int64` is declared as a relationship from `Person` to `Company`
- **THEN** its label is `WorksAt`, its endpoints are `Person` and `Company`, and it has one INT64 property `since`

#### Scenario: Property-less relationship
- **WHEN** `structure Knows` is declared as a relationship from `Person` to `Person`
- **THEN** it is accepted with no properties

### Requirement: DDL generation
The library SHALL generate Ladybug DDL for each declared table and for a schema (a list of tables), creating node tables before relationship tables, and the generated statements SHALL be idempotent (`IF NOT EXISTS`).

#### Scenario: Node DDL text
- **WHEN** DDL is generated for `Person` from the first scenario above
- **THEN** it is `CREATE NODE TABLE IF NOT EXISTS Person(id INT64, name STRING, age INT64, PRIMARY KEY(id))`

#### Scenario: Apply schema twice
- **WHEN** a schema with `Person`, `Company` and `WorksAt` is applied to an empty database twice
- **THEN** both applications succeed and the tables exist once

### Requirement: Schema verification
The library SHALL compare a declared schema with a database's catalog and report every difference: missing tables, extra or missing properties, property type mismatches, a different primary key, and different relationship endpoints. An empty report SHALL mean the database matches.

#### Scenario: Matching database
- **WHEN** a schema is applied and then verified against the same database
- **THEN** the report is empty

#### Scenario: Type mismatch reported
- **WHEN** the database has `Person.age` as STRING and the declaration says `Option Int64`
- **THEN** the report contains one type mismatch for `Person.age` naming both types
