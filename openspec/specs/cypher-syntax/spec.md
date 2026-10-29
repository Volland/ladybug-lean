# cypher-syntax Specification

## Purpose
Writing Cypher directly in Lean source as a typed term, checked against the declared schema at compile time and equivalent to the builder.

## Requirements

### Requirement: Embedded Cypher
The `cypher%` term SHALL accept Cypher text covering every clause and expression the builder supports, with case-insensitive keywords, and SHALL elaborate to a typed query (when it ends in RETURN) or a statement (otherwise). Cypher constructs outside the supported subset SHALL be rejected with an error suggesting the raw-text API.

#### Scenario: Read query
- **WHEN** `cypher% MATCH (p:Person) WHERE p.age > 30 RETURN p.name` is elaborated
- **THEN** it is a `Query String`

#### Scenario: Statement
- **WHEN** `cypher% MATCH (p:Person) SET p.age = 1` is elaborated
- **THEN** it is a `Statement`

#### Scenario: Lowercase keywords
- **WHEN** `cypher% match (p:Person) return p` is elaborated
- **THEN** it is a `Query Person`

### Requirement: Same AST as the builder
A `cypher%` query and the builder query that expresses the same clauses SHALL produce equal core ASTs, so they print identically and run identically on every backend.

#### Scenario: Equivalent queries print identically
- **WHEN** the `cypher%` query from the relationship-pattern scenario of the builder and its builder form are both printed
- **THEN** the texts and parameter maps are equal

### Requirement: Schema-checked elaboration
Elaboration SHALL resolve every node and relationship label to a declared table, every property to a declared field, check expression types with the same rules as the builder (including NULL lifting and OPTIONAL MATCH nullability), check relationship endpoints, and infer the result type from RETURN.

#### Scenario: Unknown label
- **WHEN** `cypher% MATCH (p:Persn) RETURN p` is elaborated
- **THEN** elaboration fails with an error naming `Persn`

#### Scenario: Unknown property
- **WHEN** `cypher% MATCH (p:Person) RETURN p.nmae` is elaborated
- **THEN** elaboration fails with an error naming `nmae` and the table `Person`

#### Scenario: Inferred tuple type
- **WHEN** `cypher% MATCH (p:Person) OPTIONAL MATCH (p)-[:WorksAt]->(c:Company) RETURN p.name, c.name` is elaborated
- **THEN** it is a `Query (String × Option String)`

### Requirement: Lean values as parameters
Inside `cypher%`, `$x` SHALL refer to the Lean local `x` and `$(e)` to the Lean term `e`. Each SHALL become a query parameter typed by its Lean type, and SHALL be type-checked against its use like any other expression.

#### Scenario: Local becomes a parameter
- **WHEN** `let minAge : Int64 := 30` and `cypher% MATCH (p:Person) WHERE p.age > $minAge RETURN p.name` is printed
- **THEN** the text has a `$p0` parameter bound to 30

#### Scenario: Wrongly typed local
- **WHEN** `let s := "x"` and `cypher% MATCH (p:Person) WHERE p.age > $s RETURN p` is elaborated
- **THEN** elaboration fails

### Requirement: Located errors
Every elaboration error from `cypher%` SHALL be reported at the source range of the Cypher token or expression that caused it.

#### Scenario: Error position
- **WHEN** a `cypher%` term contains an unknown property on its second line
- **THEN** the error is reported at that property's position, not at `cypher%`

### Requirement: Advanced clauses in syntax
`cypher%` SHALL accept variable-length and shortest-path patterns, `EXISTS`/`COUNT` subqueries, `UNION`/`UNION ALL`, and the vector and full-text query procedures, with the same typing and the same core AST as the builder.

#### Scenario: Variable-length in syntax
- **WHEN** `cypher% MATCH (a:Person)-[:Knows*1..2]->(b:Person) WHERE a.id = 1 RETURN b.id` is elaborated and printed
- **THEN** it is a `Query Int64` that prints the same as the builder form

#### Scenario: Union in syntax
- **WHEN** two `cypher%` reads with different result types are joined with UNION
- **THEN** elaboration fails
