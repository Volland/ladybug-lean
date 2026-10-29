import Ladybug.Value

/-!
# Core Cypher AST

The untyped AST that the builder, the `cypher%` syntax and the in-memory
evaluator share. Literal values are stored inline as `Value`s; the printer turns
each into a query parameter, so no value is ever printed as Cypher text.
Typed wrappers in `Ladybug.Cypher.Expr` are the only intended way to build it.
-/

namespace Ladybug.Cypher.Core

inductive BinOp where
  | eq | neq | lt | le | gt | ge
  | and | or | xor
  | add | sub | mul | div | mod
  | startsWith | endsWith | contains | in_
  deriving Repr, BEq, Inhabited

inductive UnOp where
  | not | neg | isNull | isNotNull
  deriving Repr, BEq, Inhabited

inductive Dir where
  | out | inc | both
  deriving Repr, BEq, Inhabited

/-- Which paths a variable-length pattern binds. -/
inductive PathMode where
  | all
  | shortest
  | allShortest
  deriving Repr, BEq, Inhabited

mutual

inductive Expr where
  | var (name : String)
  | prop (e : Expr) (key : String)
  /-- A literal; always printed as a parameter. -/
  | value (v : Value)
  | null
  | list (xs : List Expr)
  | binop (op : BinOp) (a b : Expr)
  | unop (op : UnOp) (a : Expr)
  /-- A function call; aggregates are calls too. -/
  | call (fn : String) (args : List Expr) (distinct : Bool)
  | countStar
  /-- `EXISTS { MATCH pats WHERE cond }`. -/
  | exists (pats : List Pattern) (cond : Option Expr)
  /-- `COUNT { MATCH pats WHERE cond }`. -/
  | countSub (pats : List Pattern) (cond : Option Expr)
  /-- A table or index name passed to a procedure, printed as a string literal.
  Only identifiers from declarations are used here. -/
  | name (s : String)

structure NodePat where
  var : String
  label : Option String
  props : List (String × Expr) := []

structure RelPat where
  var : Option String
  label : String
  dir : Dir
  props : List (String × Expr) := []

/-- A path pattern: a start node and relationship steps. -/
structure Pattern where
  start : NodePat
  steps : List (RelPat × NodePat) := []

end

instance : Inhabited Expr := ⟨.null⟩
instance : Inhabited NodePat := ⟨⟨"", none, []⟩⟩
instance : Inhabited RelPat := ⟨⟨none, "", .out, []⟩⟩
instance : Inhabited Pattern := ⟨⟨default, []⟩⟩

/-- One projected item: an expression and its alias, if any. -/
structure Item where
  expr : Expr
  alias : Option String := none
  deriving Inhabited

structure SortKey where
  expr : Expr
  desc : Bool := false
  deriving Inhabited

/-- ORDER BY, SKIP and LIMIT, printed after the projection they modify. -/
structure Modifiers where
  orderBy : List SortKey := []
  skip : Option Expr := none
  limit : Option Expr := none
  deriving Inhabited

def Modifiers.isEmpty (m : Modifiers) : Bool :=
  m.orderBy.isEmpty && m.skip.isNone && m.limit.isNone

structure SetItem where
  target : Expr
  value : Expr
  deriving Inhabited

inductive Clause where
  | «match» (optional : Bool) (pats : List Pattern)
  | «where» (cond : Expr)
  | «with» (items : List Item) (distinct : Bool) (mods : Modifiers)
  | «return» (items : List Item) (distinct : Bool) (mods : Modifiers)
  | unwind (e : Expr) (as : String)
  | create (pats : List Pattern)
  | merge (pat : Pattern)
  | set (items : List SetItem)
  | delete (detach : Bool) (targets : List Expr)
  /-- `MATCH pathVar = (src)-[rel*min..max]->(dst)`, a variable-length or shortest path. -/
  | matchPath (optional : Bool) (pathVar : String) (src : NodePat) (rel : RelPat)
      (min max : Nat) (mode : PathMode) (dst : NodePat)
  /-- `CALL proc(args, k := v) YIELD out AS alias, …`. -/
  | call (proc : String) (args : List Expr) (named : List (String × Expr)) (yields : List (String × String))
  /-- Separates the parts of a `UNION` (`all := true` for `UNION ALL`). -/
  | union (all : Bool)
  deriving Inhabited

structure Query where
  clauses : Array Clause
  deriving Inhabited

/-- Whether a pattern's variable names are bound by the clause (used to decide
whether a later WHERE can attach directly). -/
def Clause.acceptsWhere : Clause → Bool
  | .match .. | .with .. | .matchPath .. => true
  | _ => false

end Ladybug.Cypher.Core
