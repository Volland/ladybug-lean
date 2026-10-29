import Ladybug

/-!
# The memory ontology

The schema of a small agent memory, after the one built in *LadybugDB for
Edge Agent AI Memory*: memories mention entities, entities relate to each
other, and memories form a timeline. These structures are the whole schema:
`node_table` and `rel_table` check every field type when the file compiles and
derive the DDL, the decoders and the typed query variables from them.
-/

namespace AgentMemory

open Ladybug

/-- Something the agent knows about: a person, a project, a place. -/
structure Entity where
  name : String
  kind : String
  deriving Repr, BEq, Inhabited

/-- One remembered observation, with an embedding for similarity recall. -/
structure Memory where
  id : Int64
  text : String
  importance : Int32
  happenedAt : Timestamp
  embedding : Embedding 4
  deriving Repr, Inhabited

/-- A memory mentions an entity, with how strongly it is about it. -/
structure Mentions where
  weight : Option Float
  deriving Repr, Inhabited

/-- How two entities relate, e.g. `works_on`, `knows`. -/
structure Relates where
  label : String
  deriving Repr, Inhabited

/-- The next memory in time. -/
structure Next
  deriving Repr, Inhabited

node_table Entity (key := name)
node_table Memory
rel_table Mentions (from := Memory) (to := Entity)
rel_table Relates (from := Entity) (to := Entity)
rel_table Next (from := Memory) (to := Memory)

def schema : Schema :=
  [.ofNode Entity, .ofNode Memory, .ofRel Mentions, .ofRel Relates, .ofRel Next]

/-- A 4-dimensional embedding from a list (the example uses hand-made vectors). -/
def vec (xs : List Float) : Embedding 4 := (Embedding.ofArray? xs.toArray).getD default

end AgentMemory
