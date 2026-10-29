## Purpose

The typed Cypher query language embedded in Lean: expressions with Cypher's NULL semantics in their types, a monadic builder, a printer, and query result types.

## ADDED Requirements

### Requirement: Typed expressions
Matching a node or relationship table SHALL yield a variable whose properties are reachable by dot notation as expressions typed by the declared field types. Expressions SHALL support comparison, arithmetic, string concatenation and predicates (`STARTS WITH`, `CONTAINS`, `IN`), list literals, and calls to typed scalar functions. Any Lean value embedded in an expression SHALL become a query parameter, never literal text. An ill-typed expression (e.g. comparing a string property with an integer) SHALL be a compile-time error.

#### Scenario: Property access is typed
- **WHEN** `p` is the variable from matching `Person`
- **THEN** `p.name` has type `Expr String` and `p.age` has type `Expr (Option Int64)`

#### Scenario: Embedded value becomes a parameter
- **WHEN** a query filters `p.name ==. lit "Ann"` and is printed
- **THEN** the text contains `$p0` (not `'Ann'`) and the parameter map binds `p0` to `"Ann"`

#### Scenario: Ill-typed comparison rejected
- **WHEN** a query contains `p.name ==. lit (5 : Int64)`
- **THEN** elaboration fails

### Requirement: Three-valued logic
Every comparison and boolean connective SHALL have type `Expr (Option Bool)`, where `none` is Cypher's unknown. Arithmetic and comparisons SHALL accept nullable and non-nullable operands and produce a nullable result when either operand is nullable. WHERE SHALL keep exactly the rows whose predicate is true. The language SHALL provide `isNull`, `isNotNull`, `coalesce`, and `isTrue`/`isFalse` (which turn unknown into false). AND, OR, NOT and XOR SHALL follow Cypher's truth tables.

#### Scenario: Unknown filters out the row
- **WHEN** persons with ages 20, 40 and NULL are filtered with `p.age >. lit 30` and their names returned
- **THEN** only the person aged 40 is returned

#### Scenario: Unknown OR true is true
- **WHEN** the same persons are filtered with `p.age >. lit 30 ||. p.name ==. lit "nulled"`, where the NULL-age person's name is `"nulled"`
- **THEN** the persons aged 40 and NULL are returned

#### Scenario: Coalesce removes nullability
- **WHEN** `coalesce p.age (lit 0)` is returned
- **THEN** its type is `Expr Int64` and the NULL-age person yields 0

### Requirement: Query builder
Queries SHALL be built in a monad whose actions append clauses: match a node table, match a relationship pattern between variables (outgoing, incoming or undirected), optional match, where, with (projecting and renaming variables), unwind a list, order by (ascending/descending), skip, limit, create a node or relationship from a Lean value, merge on a node's key, set properties, delete and detach delete. A variable from OPTIONAL MATCH SHALL make every property reached through it nullable. Pattern endpoints SHALL be checked against the relationship's declared source and destination tables at compile time.

#### Scenario: Relationship pattern
- **WHEN** a query matches `Person`, then `p -[WorksAt]-> Company`, and returns the person's and company's names
- **THEN** it prints as `MATCH (n0:Person) MATCH (n0)-[r1:WorksAt]->(n2:Company) RETURN n0.name, n2.name`

#### Scenario: Wrong endpoint rejected
- **WHEN** `c -[WorksAt]-> Person` is matched where `c` is a `Company` variable
- **THEN** elaboration fails

#### Scenario: Optional match makes properties nullable
- **WHEN** a company is optionally matched from a person and `c.name` is returned
- **THEN** the result column type is `Option String` and persons with no company yield `none`

#### Scenario: Create from a value
- **WHEN** a query creates `Person.mk 1 "Ann" none`
- **THEN** after running it, matching `Person` returns that value

### Requirement: Aggregation
The language SHALL provide `count`, `countDistinct`, `sum`, `avg`, `min`, `max` and `collect`, and returning a mix of aggregates and plain expressions SHALL group by the plain expressions, as Cypher does. `sum` and `count` of no rows SHALL be 0; `avg`, `min` and `max` of no rows SHALL be NULL and typed as `Option`.

#### Scenario: Group by
- **WHEN** persons are matched with their company and `(c.name, count p)` is returned
- **THEN** each company appears once with its number of employees

#### Scenario: Empty aggregate types
- **WHEN** `max p.age` over no rows is returned
- **THEN** its type is `Option Int64` and the value is `none`

### Requirement: Printing
Printing a query SHALL produce deterministic Cypher text and a parameter map: the same query value always prints identically, variables are named by clause order, labels and property names that are not plain identifiers are quoted with backticks, and every embedded Lean value is a parameter.

#### Scenario: Deterministic text
- **WHEN** the same query is printed twice
- **THEN** both texts and parameter maps are equal

#### Scenario: Quoted identifier
- **WHEN** a table is declared with label `My Label`
- **THEN** matching it prints `` (n0:`My Label`) ``

### Requirement: Result typing
The result type of a query SHALL be determined by what it returns: a single expression of type `Expr α` gives rows of `α`, a tuple of expressions gives a tuple, and a table variable gives the table's structure. A query that returns nothing SHALL be executable only as a statement.

#### Scenario: Return a whole node
- **WHEN** a query matches `Person` and returns `p`
- **THEN** its rows have type `Person` and decode to the stored values

#### Scenario: Return a tuple
- **WHEN** a query returns `(p.name, p.age)`
- **THEN** its rows have type `String × Option Int64`
