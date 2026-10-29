# ladybug-lean

**Website: [volland.github.io/ladybug-lean](https://volland.github.io/ladybug-lean/)** · [Guide](https://volland.github.io/ladybug-lean/guide.html) · [Mini book](https://volland.github.io/ladybug-lean/book.html) · [Example](examples/agent-memory)

A Lean 4 library for [LadybugDB](https://github.com/LadybugDB/ladybug), the embedded graph database, with:

- **typed Cypher**: queries are checked against your schema when you compile, written either with a monadic builder or as Cypher text (`cypher%`);
- **a repository layer**: insert, upsert, get, update, delete, link, traverse and bulk-load the Lean structures you declare as tables;
- **two backends behind one interface**: the native Ladybug database, and a pure in-memory graph that runs the same programs in `#eval` and in unit tests;
- **vector and full-text search**, variable-length and shortest paths, subqueries and unions.

```lean
import Ladybug
import LadybugNative
open Ladybug

structure Person where
  id : Int64
  name : String
  age : Option Int64

structure Company where
  name : String

structure WorksAt where
  since : Int64

node_table Person
node_table Company (key := name)
rel_table WorksAt (from := Person) (to := Company)

def schema : Schema := [.ofNode Person, .ofNode Company, .ofRel WorksAt]

-- Written once, runs on any backend.
def demo {m : Type → Type} [MonadGraph m] : m (Array (String × Option String)) := do
  applySchema schema
  Repo.insert (Person.mk 1 "Ann" (some 41))
  Repo.insert (Person.mk 2 "Bob" none)
  Repo.insert (Company.mk "ACME")
  Repo.link (1 : Int64) (WorksAt.mk 2020) "ACME"
  runQuery (cypher% MATCH (p:Person) OPTIONAL MATCH (p)-[:WorksAt]->(c:Company)
                    RETURN p.name, c.name ORDER BY p.name)

#eval (demo : MemM _).run' {}          -- in memory, no native library needed

def main : IO Unit := Ladybug.withDatabase "./company.lbug" fun db => db.withConnection do
  IO.println (← demo)                   -- on the Ladybug database
```

## Installing

Add the package to your `lakefile.lean`:

```lean
require ladybug from git "https://github.com/Volland/ladybug-lean" @ "main"
```

The first build downloads the official Ladybug library for your platform (macOS, Linux and Windows on x86_64 and arm64) at the version in `lbug.lock`, into `.lake/lbug/`. The library is loaded at runtime from that path, so you don't need to set an rpath or a library search path.

- `lake run lbug-update` moves `lbug.lock` to the latest Ladybug release.
- `LBUG_LIB_DIR=/path/to/dir` builds against a local Ladybug build instead of downloading one; the directory needs `lbug.h` and the shared library.
- `LBUG_LIBRARY=/path/to/liblbug.so` overrides the library file at runtime.

Toolchain: Lean `v4.35.0`. Building the C shim needs a C compiler: the system `cc` on macOS and Linux, MinGW-w64 `gcc` on Windows (for example from MSYS2's UCRT64 environment); `CC` overrides it.

## Libraries

| Import | What it contains | Native library |
|---|---|---|
| `Ladybug` | values and decoding, schema commands, the typed Cypher language, `cypher%`, the repository, search, `MonadGraph`, the in-memory backend `MemM` | no |
| `LadybugNative` | the native backend: `Database`, `Connection`, `LbugM`, raw Cypher text, timeouts, file import | yes |

## Declaring tables

`node_table T` makes a structure a node table. The label defaults to the structure's name and the key to a field called `id`; use `(key := field)` and `(label := "Name")` in any order to change them. `rel_table R (from := A) (to := B)` declares a relationship table, and a structure with no fields is a relationship without properties.

The commands check every field's type at compile time and generate:

- decoders and encoders;
- `T.Var`, the query variable of the table, whose fields are typed property expressions (`p.age : Expr (Option Int64)`);
- `T.OptVar`, the same with every property nullable, for OPTIONAL MATCH.

Column types: `Bool`, all signed and unsigned integer widths, `Int` (INT128), `Float`, `Float32`, `String`, `ByteArray`, `Uuid`, `Date`, `Timestamp`, `Interval`, `Option α`, `Array α`, `Embedding n` (`FLOAT[n]`), and structures that derive `Ladybug.CypherType`.

## Writing queries

The builder and `cypher%` produce the same query:

```lean
def employees : Query (String × String) := query do
  let p ← match_ (node Person)
  let (_, c) ← match_ (out p WorksAt (node Company))
  where_ (p.age >. 30)
  return_ (p.name, c.name)

def employees' := cypher% MATCH (p:Person)-[:WorksAt]->(c:Company) WHERE p.age > 30 RETURN p.name, c.name
```

- **NULL is in the types.** Comparisons and connectives have type `Expr (Option Bool)`, and WHERE keeps only rows that are true. Use `coalesce`, `isNull`, `isTrue` to leave three-valued logic.
- **Lean values are always parameters.** `lit x`, numerals, and `$x` / `$(e)` inside `cypher%` are sent as query parameters, never spliced into the text.
- **Mistakes are compile errors**, reported at the Cypher token: an unknown label or property (with a "did you mean"), a comparison of a string with a number, or a relationship pattern whose endpoints don't match its table.
- Operators end in a dot: `==.` `!=.` `<.` `<=.` `>.` `>=.` `&&.` `||.` `+.` `-.` `*.` `/.` `%.` `++.`.
- Patterns: `out p R (node T)`, `inc …`, `both …`, `matchPaths p Knows (node Person) (max := 3)`, `shortestPath`, `allShortestPaths`.
- Subqueries and unions: `exists_ do …`, `countSub do …`, `q₁.union q₂`, `q₁.unionAll q₂`.
- Search: `createVectorIndex`, `vectorSearch`, `createFtsIndex`, `ftsSearch`. The native backend installs and loads the `vector` and `fts` extensions on first use.

In `cypher%`, keywords may be upper, lower or capitalized case, strings are Lean string literals (`"Ann"`), and the clauses after the first must start at or right of the first clause's column.

## Running

- `runQuery q`, `runStmt s`, `withTx`, `withReadTx`, `applySchema`, `verifySchema` work on every `MonadGraph`.
- On the native backend, `queryRaw`, `queryAs` and `exec` run Cypher text, `withTimeout ms` limits a query, `Connection.interrupt` stops one from another task, and `Repo.copyNodes`/`copyRels` load CSV or Parquet files.
- Errors are a structured `Ladybug.Error`: `.query`, `.constraint`, `.notFound`, `.decode`, `.transaction`, `.timeout`, `.storageMismatch` and others.

## Behaviour to know

- The in-memory backend follows Ladybug's semantics where openCypher leaves a choice: NULL sorts as the largest value, `x IN [.., NULL]` is false rather than unknown, integer `/` and `%` truncate toward zero, variable-length patterns repeat relationships (walk semantics), and shortest paths never return to their start. A differential test suite checks this against Ladybug on generated graphs and queries.
- Its full-text search uses BM25 and a Porter stemmer: it matches the same documents as Ladybug for ordinary queries, but scores are not identical.
- Ladybug has no `CALL { … }` subqueries, so neither does the typed language.
- A union value's member name is empty when the union has more than one member, because the C API does not report it.
- Timeouts and interrupts take effect between Ladybug's units of work, so a query can overrun its timeout.

## Example

[`examples/agent-memory`](examples/agent-memory) is a small project that stores an AI agent's memory as a typed property graph: a schema of five tables, recall functions written once for both backends, checks that run while it compiles, and a native run on a LadybugDB file.

## Development

```sh
lake build tests && .lake/build/bin/tests   # the full suite
DIFF_CASES=3000 TEST_FILTER=differential .lake/build/bin/tests
scripts/check-native-library.sh             # download caching, lbug-update, LBUG_LIB_DIR
(cd examples/agent-memory && lake build AgentMemory && lake exe agent-memory)
```

The website lives in `site/` (static HTML, deployed to GitHub Pages by `.github/workflows/pages.yml`); its Lean snippets are compiled and checked by `Tests/SiteSnippets.lean`.

Intent lives in `tg.md/` (decisions, constraints and architecture, as a typed graph checked with `tg check`) and requirements in `openspec/specs/`; the milestones' changes are archived under `openspec/changes/archive/`.

## License

MIT; see [LICENSE](LICENSE). LadybugDB itself is distributed under its own license by the LadybugDB project.
