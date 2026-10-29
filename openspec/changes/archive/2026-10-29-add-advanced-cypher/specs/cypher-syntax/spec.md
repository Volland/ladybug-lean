## ADDED Requirements

### Requirement: Advanced clauses in syntax
`cypher%` SHALL accept variable-length and shortest-path patterns, `EXISTS`/`COUNT` subqueries, `UNION`/`UNION ALL`, and the vector and full-text query procedures, with the same typing and the same core AST as the builder.

#### Scenario: Variable-length in syntax
- **WHEN** `cypher% MATCH (a:Person)-[:Knows*1..2]->(b:Person) WHERE a.id = 1 RETURN b.id` is elaborated and printed
- **THEN** it is a `Query Int64` that prints the same as the builder form

#### Scenario: Union in syntax
- **WHEN** two `cypher%` reads with different result types are joined with UNION
- **THEN** elaboration fails
