import Ladybug

/-! Tables shared by the typed tests. -/

namespace Tests.Fixtures

open Ladybug

structure Person where
  id : Int64
  name : String
  age : Option Int64
  deriving BEq, Repr

structure Company where
  name : String
  founded : Int32
  deriving BEq, Repr

structure WorksAt where
  since : Int64
  deriving BEq, Repr

structure Knows
  deriving BEq, Repr

node_table Person
node_table Company (key := name)
rel_table WorksAt (from := Person) (to := Company)
rel_table Knows (from := Person) (to := Person)

/-- A table with a custom key and label. -/
structure Firm where
  name : String
  founded : Int32

node_table Firm (key := name) (label := "Org")

/-- A table whose label needs quoting. -/
structure Labelled where
  id : Int64

node_table Labelled (label := "My Label")

def schema : Schema := [.ofNode Person, .ofNode Company, .ofRel WorksAt, .ofRel Knows]

instance : ToString Person := ⟨fun p => s!"Person({p.id}, {p.name}, {p.age})"⟩

end Tests.Fixtures
