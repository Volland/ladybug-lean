# agent-memory

A small project that uses ladybug-lean the way an application would: the memory schema of an AI agent, after the one in [*LadybugDB for Edge Agent AI Memory*](https://leanpub.com/ladybugdb).

| File | What it shows |
|---|---|
| `AgentMemory/Schema.lean` | the ontology as Lean structures: `Entity`, `Memory` (with an `Embedding 4`), `Mentions`, `Relates`, `Next` |
| `AgentMemory/Memory.lean` | remembering and recalling, written once against `MonadGraph`: the repository API, the query builder, `cypher%`, a vector search, variable-length and shortest paths, an `EXISTS` subquery |
| `AgentMemory/Checks.lean` | checks that run while the file compiles: `#guard` on the in-memory backend, and `#guard_msgs` for queries the schema rejects |
| `Main.lean` | the same functions on a LadybugDB file |

```sh
lake build AgentMemory     # compiles the schema and runs every check
lake exe agent-memory      # runs on a LadybugDB file, memory.lbug
```

```
about Ann:        #[(Ann started the Ladybug bindings, 5), (Meetup in Kyiv about graph memory, 4), (Bob reviewed Ann's first query, 3)]
near Ann:         #[Ladybug, Bob, Lean]
memories 1 → 4:   3 steps
like memory 1:    #[(Ann started the Ladybug bindings, 0.000000), (Bob reviewed Ann's first query, 0.029858)]
nobody mentions:  #[Kyiv]
```

This copy depends on the library through `require ladybug from "../.."`. In your own project use the published package:

```lean
require ladybug from git "https://github.com/Volland/ladybug-lean" @ "v0.1.0"
```
