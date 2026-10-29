## ADDED Requirements

### Requirement: Variable-length paths
The builder SHALL match relationship patterns repeated between a lower and an upper bound (`*min..max`) in any direction, and SHALL bind the matched path to a variable of a typed path whose nodes and relationships decode to the declared structures. The language SHALL provide `length`, `nodes` and `rels` on paths. A pattern with no upper bound SHALL be rejected at compile time, because Ladybug requires one.

#### Scenario: Friends within three hops
- **WHEN** persons form the chain 1-Knows->2-Knows->3-Knows->4 and the persons reachable from 1 in 1 to 2 hops are returned
- **THEN** persons 2 and 3 are returned

#### Scenario: Path decoding
- **WHEN** the path from 1 to 3 is returned
- **THEN** it decodes to a path with nodes `[1, 2, 3]` as `Person` values and two `Knows` relationships, and `length` is 2

#### Scenario: Unbounded pattern rejected
- **WHEN** a variable-length pattern without an upper bound is built
- **THEN** elaboration fails

### Requirement: Shortest paths
The builder SHALL match the shortest path and all shortest paths between two variables over a relationship table within an upper bound, returning typed paths.

#### Scenario: Shortest path
- **WHEN** 1->2->4 and 1->3->5->4 exist and the shortest path from 1 to 4 is returned
- **THEN** the result is the path through 2, with length 2

#### Scenario: All shortest
- **WHEN** 1->2->4 and 1->3->4 exist and all shortest paths from 1 to 4 are returned
- **THEN** both length-2 paths are returned

### Requirement: Subqueries
The language SHALL support `EXISTS { pattern [WHERE …] }` as an `Expr Bool`, `COUNT { pattern [WHERE …] }` as an `Expr Int64`, and `CALL { … }` subqueries whose returned variables are in scope afterwards, with the subquery able to reference outer variables.

#### Scenario: Exists filter
- **WHEN** persons are filtered by `EXISTS { (p)-[:WorksAt]->(:Company) }`
- **THEN** only persons with an employer are returned

#### Scenario: Count subquery
- **WHEN** each person is returned with `COUNT { (p)-[:Knows]->() }`
- **THEN** each count equals the person's number of outgoing `Knows` relationships

### Requirement: Union
The language SHALL combine two queries with `UNION` (removing duplicates) or `UNION ALL` (keeping duplicates) only when they have the same result type and the same column names.

#### Scenario: Union removes duplicates
- **WHEN** a query returning names `["a","b"]` is unioned with one returning `["b","c"]`
- **THEN** UNION returns three names and UNION ALL returns four

#### Scenario: Mismatched result types rejected
- **WHEN** a `Query String` is unioned with a `Query Int64`
- **THEN** elaboration fails
