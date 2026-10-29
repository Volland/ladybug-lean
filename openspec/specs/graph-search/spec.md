# graph-search Specification

## Purpose
Similarity and text retrieval over declared node tables: embedding columns, vector indexes, full-text indexes and the extensions they need.

## Requirements

### Requirement: Embedding columns
A node table field of type `Embedding n` SHALL map to a fixed-size `FLOAT[n]` column. Constructing an `Embedding n` from an array of the wrong length SHALL fail, and decoding a stored array of the wrong length SHALL raise a decode error.

#### Scenario: Embedding column DDL
- **WHEN** a table `Doc` with `id : Int64` and `emb : Embedding 3` is declared
- **THEN** its DDL contains `emb FLOAT[3]`

#### Scenario: Wrong length
- **WHEN** an `Embedding 3` is built from 4 floats
- **THEN** construction fails

### Requirement: Vector index
The library SHALL create a named vector index on an embedding column with a distance metric (cosine, l2, l2sq or dot product), drop it, and query it for the k nearest nodes to a query vector, returning each node (as its structure) with its distance, ordered by distance. The query vector SHALL be a parameter.

#### Scenario: Nearest neighbours
- **WHEN** docs with embeddings `[1,0,0]`, `[0,1,0]` and `[0.9,0.1,0]` are indexed with cosine distance and queried with `[1,0,0]` and k = 2
- **THEN** the docs with `[1,0,0]` and `[0.9,0.1,0]` are returned in that order

#### Scenario: Filtered vector search
- **WHEN** the same query is combined in one query with a WHERE on another property of the returned nodes
- **THEN** only the nodes satisfying the predicate are returned

### Requirement: Full-text index
The library SHALL create a named full-text index over one or more string columns of a node table, drop it, and query it with a text query, returning each matching node with its relevance score, ordered by descending score.

#### Scenario: Keyword search
- **WHEN** docs "graph databases are fast", "lean is a prover" and "graph theory" are indexed and queried with "graph"
- **THEN** the two docs containing "graph" are returned with positive scores and the other is not

### Requirement: Extensions
On the native backend, the library SHALL install and load a Ladybug extension by name, and the search operations SHALL load the vector or full-text extension automatically on first use when it is not already loaded.

#### Scenario: Automatic loading
- **WHEN** a fresh database runs a vector index query without loading anything first
- **THEN** the query succeeds
