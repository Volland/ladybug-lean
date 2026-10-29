import Ladybug.Schema

/-!
# Typed expressions

`Expr α` is a phantom-typed wrapper over the core AST. Nullability lives in the
type: `Expr (Option τ)` may be NULL, `Expr τ` may not. Every comparison and
connective has type `Expr (Option Bool)` (Cypher's three-valued logic), and
arithmetic on a nullable operand is nullable.

Operators end in a dot to stay clear of Lean's own: `==.`, `!=.`, `<.`, `<=.`,
`>.`, `>=.`, `&&.`, `||.`, `+.`, `-.`, `*.`, `/.`, `%.`, `++.`.
-/

namespace Ladybug

open Cypher

structure Expr (α : Type) where
  raw : Core.Expr
  deriving Inhabited

namespace Expr

variable {α β γ τ ρ : Type}

/-- `Compat α β τ ρ`: `α` and `β` are each `τ` or `Option τ`; `ρ` is `τ` when
both are non-nullable and `Option τ` otherwise. -/
class Compat (α β : Type) (τ ρ : outParam Type) : Prop

instance (priority := high) : Compat (Option τ) (Option τ) τ (Option τ) := ⟨⟩
instance (priority := high) : Compat (Option τ) τ τ (Option τ) := ⟨⟩
instance (priority := high) : Compat τ (Option τ) τ (Option τ) := ⟨⟩
instance : Compat τ τ τ τ := ⟨⟩

/-- When the second operand's type is still unknown (a literal), make it the
first operand's type, so `p.age >. 30` elaborates `30` at `Option Int64`. -/
@[default_instance high] instance compatOptSelf : Compat (Option τ) (Option τ) τ (Option τ) := ⟨⟩
@[default_instance] instance compatSelf : Compat τ τ τ τ := ⟨⟩

/-- `HasBase α τ`: `α` is `τ` or `Option τ`. -/
class HasBase (α : Type) (τ : outParam Type) : Prop

instance (priority := high) : HasBase (Option τ) τ := ⟨⟩
instance : HasBase τ τ := ⟨⟩

/-- `LitFor β γ`: a Lean value of type `γ` can be a literal of type `β`
(`γ = τ` for both `β = τ` and `β = Option τ`). -/
class LitFor (β : Type) (γ : outParam Type) : Prop

instance (priority := high) : LitFor (Option τ) τ := ⟨⟩
instance : LitFor τ τ := ⟨⟩

/-- Predicate types: `Bool` and `Option Bool`. -/
class IsPred (α : Type) : Prop

instance : IsPred Bool := ⟨⟩
instance : IsPred (Option Bool) := ⟨⟩

class Numeric (τ : Type) : Prop

instance : Numeric Int8 := ⟨⟩
instance : Numeric Int16 := ⟨⟩
instance : Numeric Int32 := ⟨⟩
instance : Numeric Int64 := ⟨⟩
instance : Numeric UInt8 := ⟨⟩
instance : Numeric UInt16 := ⟨⟩
instance : Numeric UInt32 := ⟨⟩
instance : Numeric UInt64 := ⟨⟩
instance : Numeric Int := ⟨⟩
instance : Numeric Float := ⟨⟩
instance : Numeric Float32 := ⟨⟩

private def bin (op : Core.BinOp) (a : Expr α) (b : Expr β) : Expr ρ := ⟨.binop op a.raw b.raw⟩

-- @tg: implements:: [[openspec:cypher-query#Typed expressions]]
/-- A literal; printed as a parameter. -/
def lit [LitFor β γ] [ToValue γ] (x : γ) : Expr β := ⟨.value (toValue x)⟩

instance {n : Nat} [LitFor β γ] [OfNat γ n] [ToValue γ] : OfNat (Expr β) n := ⟨lit (OfNat.ofNat n : γ)⟩

instance [LitFor β γ] [OfScientific γ] [ToValue γ] : OfScientific (Expr β) :=
  ⟨fun m s e => lit (OfScientific.ofScientific m s e : γ)⟩

/-- The NULL literal. -/
def null : Expr (Option τ) := ⟨.null⟩

/-- A non-nullable expression used where a nullable one is expected. -/
def toOpt (e : Expr τ) : Expr (Option τ) := ⟨e.raw⟩

instance : Coe (Expr τ) (Expr (Option τ)) := ⟨toOpt⟩

-- @tg: implements:: [[openspec:cypher-query#Three-valued logic]]
def eq [Compat α β τ ρ] (a : Expr α) (b : Expr β) : Expr (Option Bool) := bin .eq a b
def neq [Compat α β τ ρ] (a : Expr α) (b : Expr β) : Expr (Option Bool) := bin .neq a b
def lt [Compat α β τ ρ] (a : Expr α) (b : Expr β) : Expr (Option Bool) := bin .lt a b
def le [Compat α β τ ρ] (a : Expr α) (b : Expr β) : Expr (Option Bool) := bin .le a b
def gt [Compat α β τ ρ] (a : Expr α) (b : Expr β) : Expr (Option Bool) := bin .gt a b
def ge [Compat α β τ ρ] (a : Expr α) (b : Expr β) : Expr (Option Bool) := bin .ge a b

def and [IsPred α] [IsPred β] (a : Expr α) (b : Expr β) : Expr (Option Bool) := bin .and a b
def or [IsPred α] [IsPred β] (a : Expr α) (b : Expr β) : Expr (Option Bool) := bin .or a b
def xor [IsPred α] [IsPred β] (a : Expr α) (b : Expr β) : Expr (Option Bool) := bin .xor a b
def not [IsPred α] (a : Expr α) : Expr (Option Bool) := ⟨.unop .not a.raw⟩

def isNull (a : Expr α) : Expr Bool := ⟨.unop .isNull a.raw⟩
def isNotNull (a : Expr α) : Expr Bool := ⟨.unop .isNotNull a.raw⟩

/-- `coalesce a b` is `a` unless it is NULL, else `b`. -/
def coalesce (a : Expr (Option τ)) (b : Expr τ) : Expr τ := ⟨.call "coalesce" [a.raw, b.raw] false⟩

/-- True only when the predicate is true; unknown becomes false. -/
def isTrue [IsPred α] (a : Expr α) : Expr Bool := ⟨.call "coalesce" [a.raw, .value (.bool false)] false⟩

/-- True only when the predicate is false; unknown becomes false. -/
def isFalse [IsPred α] (a : Expr α) : Expr Bool :=
  ⟨.call "coalesce" [.unop .not a.raw, .value (.bool false)] false⟩

def add [Compat α β τ ρ] [Numeric τ] (a : Expr α) (b : Expr β) : Expr ρ := bin .add a b
def sub [Compat α β τ ρ] [Numeric τ] (a : Expr α) (b : Expr β) : Expr ρ := bin .sub a b
def mul [Compat α β τ ρ] [Numeric τ] (a : Expr α) (b : Expr β) : Expr ρ := bin .mul a b
def div [Compat α β τ ρ] [Numeric τ] (a : Expr α) (b : Expr β) : Expr ρ := bin .div a b
def mod [Compat α β τ ρ] [Numeric τ] (a : Expr α) (b : Expr β) : Expr ρ := bin .mod a b
def neg [HasBase α τ] [Numeric τ] (a : Expr α) : Expr α := ⟨.unop .neg a.raw⟩

/-- Types `+` applies to in Cypher: numbers add, strings concatenate. -/
class Plus (τ : Type) : Prop

instance [Numeric τ] : Plus τ := ⟨⟩
instance : Plus String := ⟨⟩

/-- Cypher's `+`: `add` for numbers, `concat` for strings. -/
def plus [Compat α β τ ρ] [Plus τ] (a : Expr α) (b : Expr β) : Expr ρ := bin .add a b

def concat [Compat α β String ρ] (a : Expr α) (b : Expr β) : Expr ρ := bin .add a b
def startsWith [Compat α β String ρ] (a : Expr α) (b : Expr β) : Expr (Option Bool) := bin .startsWith a b
def endsWith [Compat α β String ρ] (a : Expr α) (b : Expr β) : Expr (Option Bool) := bin .endsWith a b
def contains [Compat α β String ρ] (a : Expr α) (b : Expr β) : Expr (Option Bool) := bin .contains a b

/-- `a IN xs`. -/
def isIn [HasBase α τ] (a : Expr α) (xs : Expr (Array τ)) : Expr (Option Bool) := bin .in_ a xs

/-- A list literal. -/
def list (xs : List (Expr τ)) : Expr (Array τ) := ⟨.list (xs.map (·.raw))⟩

/-- Call a Ladybug function by name with a declared result type. -/
def call (fn : String) (args : List Core.Expr) : Expr α := ⟨.call fn args false⟩

def lower [HasBase α String] (a : Expr α) : Expr α := call "lower" [a.raw]
def upper [HasBase α String] (a : Expr α) : Expr α := call "upper" [a.raw]
def trim [HasBase α String] (a : Expr α) : Expr α := call "trim" [a.raw]
def size [HasBase α String] [Compat α α String ρ] (a : Expr α) : Expr (Option Int64) := call "size" [a.raw]
def abs [HasBase α τ] [Numeric τ] (a : Expr α) : Expr α := call "abs" [a.raw]

/-! ## Aggregates -/

-- @tg: implements:: [[openspec:cypher-query#Aggregation]]
def count (a : Expr α) : Expr Int64 := ⟨.call "count" [a.raw] false⟩
def countDistinct (a : Expr α) : Expr Int64 := ⟨.call "count" [a.raw] true⟩
def countStar : Expr Int64 := ⟨.countStar⟩
def sum [HasBase α τ] [Numeric τ] (a : Expr α) : Expr (Option τ) := ⟨.call "sum" [a.raw] false⟩
def avg [HasBase α τ] [Numeric τ] (a : Expr α) : Expr (Option Float) := ⟨.call "avg" [a.raw] false⟩
def min [HasBase α τ] (a : Expr α) : Expr (Option τ) := ⟨.call "min" [a.raw] false⟩
def max [HasBase α τ] (a : Expr α) : Expr (Option τ) := ⟨.call "max" [a.raw] false⟩
/-- Collect the non-NULL values of a group. -/
def collect [HasBase α τ] (a : Expr α) : Expr (Array τ) := ⟨.call "collect" [a.raw] false⟩

end Expr

export Expr (lit null coalesce isTrue isFalse isNull isNotNull countStar)

infix:50 " ==. " => Expr.eq
infix:50 " !=. " => Expr.neq
infix:50 " <. " => Expr.lt
infix:50 " <=. " => Expr.le
infix:50 " >. " => Expr.gt
infix:50 " >=. " => Expr.ge
infixr:35 " &&. " => Expr.and
infixr:30 " ||. " => Expr.or
infixl:65 " +. " => Expr.add
infixl:65 " -. " => Expr.sub
infixl:70 " *. " => Expr.mul
infixl:70 " /. " => Expr.div
infixl:70 " %. " => Expr.mod
infixl:65 " ++. " => Expr.concat

end Ladybug
