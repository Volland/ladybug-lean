import Ladybug.Value
import Ladybug.Error

/-!
# Decoding and encoding

`FromValue` decodes one `Value` into a Lean type, `ToValue` encodes a Lean value
as a query parameter, and `FromRow` decodes a whole result row: positionally
for scalars and tuples, by column name for structures.
-/

namespace Ladybug

variable {α β : Type}

/-- Days since 1970-01-01. -/
structure Date where
  days : Int32
  deriving Repr, BEq, Ord, Hashable, Inhabited, DecidableEq

/-- Microseconds since 1970-01-01 00:00:00 UTC. -/
structure Timestamp where
  micros : Int64
  deriving Repr, BEq, Ord, Hashable, Inhabited, DecidableEq

structure Interval where
  months : Int32
  days : Int32
  micros : Int64
  deriving Repr, BEq, Hashable, Inhabited, DecidableEq

/-- A UUID in its canonical textual form. -/
structure Uuid where
  text : String
  deriving Repr, BEq, Ord, Hashable, Inhabited, DecidableEq

class FromValue (α : Type) where
  /-- The type's name in decode errors. -/
  typeName : String
  fromValue? : Value → Option α

class ToValue (α : Type) where
  toValue : α → Value

export FromValue (fromValue?)
export ToValue (toValue)

namespace Value

/-- The value of any integer kind, as an `Int`. -/
def toInt? : Value → Option Int
  | int8 v => some v.toInt | int16 v => some v.toInt | int32 v => some v.toInt
  | int64 v => some v.toInt | int128 v => some v
  | uint8 v => some v.toNat | uint16 v => some v.toNat | uint32 v => some v.toNat
  | uint64 v => some v.toNat
  | _ => none

end Value

private def inRange (lo hi : Int) (i : Int) : Option Int := if lo ≤ i ∧ i ≤ hi then some i else none

instance : FromValue Value := ⟨"Value", some⟩
instance : ToValue Value := ⟨id⟩

instance : FromValue Bool := ⟨"Bool", fun | .bool b => some b | _ => none⟩
instance : ToValue Bool := ⟨.bool⟩

instance : FromValue Int := ⟨"Int", Value.toInt?⟩
instance : ToValue Int := ⟨fun i =>
  if -9223372036854775808 ≤ i ∧ i ≤ 9223372036854775807 then .int64 (Int64.ofInt i) else .int128 i⟩
instance : FromValue Nat := ⟨"Nat", fun v => v.toInt? >>= fun i => if i ≥ 0 then some i.toNat else none⟩
instance : ToValue Nat := ⟨fun n => toValue (n : Int)⟩

instance : FromValue Int64 :=
  ⟨"Int64", fun v => v.toInt? >>= inRange (-9223372036854775808) 9223372036854775807 |>.map Int64.ofInt⟩
instance : ToValue Int64 := ⟨.int64⟩
instance : FromValue Int32 :=
  ⟨"Int32", fun v => v.toInt? >>= inRange (-2147483648) 2147483647 |>.map Int32.ofInt⟩
instance : ToValue Int32 := ⟨.int32⟩
instance : FromValue Int16 := ⟨"Int16", fun v => v.toInt? >>= inRange (-32768) 32767 |>.map Int16.ofInt⟩
instance : ToValue Int16 := ⟨.int16⟩
instance : FromValue Int8 := ⟨"Int8", fun v => v.toInt? >>= inRange (-128) 127 |>.map Int8.ofInt⟩
instance : ToValue Int8 := ⟨.int8⟩
instance : FromValue UInt64 :=
  ⟨"UInt64", fun v => v.toInt? >>= inRange 0 18446744073709551615 |>.map (UInt64.ofNat ·.toNat)⟩
instance : ToValue UInt64 := ⟨.uint64⟩
instance : FromValue UInt32 := ⟨"UInt32", fun v => v.toInt? >>= inRange 0 4294967295 |>.map (UInt32.ofNat ·.toNat)⟩
instance : ToValue UInt32 := ⟨.uint32⟩
instance : FromValue UInt16 := ⟨"UInt16", fun v => v.toInt? >>= inRange 0 65535 |>.map (UInt16.ofNat ·.toNat)⟩
instance : ToValue UInt16 := ⟨.uint16⟩
instance : FromValue UInt8 := ⟨"UInt8", fun v => v.toInt? >>= inRange 0 255 |>.map (UInt8.ofNat ·.toNat)⟩
instance : ToValue UInt8 := ⟨.uint8⟩

instance : FromValue Float := ⟨"Float", fun | .double d => some d | .float f => some f.toFloat | _ => none⟩
instance : ToValue Float := ⟨.double⟩
instance : FromValue Float32 := ⟨"Float32", fun | .float f => some f | _ => none⟩
instance : ToValue Float32 := ⟨.float⟩

instance : FromValue String := ⟨"String", fun | .string s => some s | _ => none⟩
instance : ToValue String := ⟨.string⟩
instance : FromValue ByteArray := ⟨"ByteArray", fun | .blob b => some b | _ => none⟩
instance : ToValue ByteArray := ⟨.blob⟩

instance : FromValue Date := ⟨"Date", fun | .date d => some ⟨d⟩ | _ => none⟩
instance : ToValue Date := ⟨fun d => .date d.days⟩
instance : FromValue Timestamp := ⟨"Timestamp", fun | .timestamp t | .timestampTz t => some ⟨t⟩ | _ => none⟩
instance : ToValue Timestamp := ⟨fun t => .timestamp t.micros⟩
instance : FromValue Interval := ⟨"Interval", fun | .interval m d u => some ⟨m, d, u⟩ | _ => none⟩
instance : ToValue Interval := ⟨fun i => .interval i.months i.days i.micros⟩
instance : FromValue Uuid := ⟨"Uuid", fun | .uuid u => some ⟨u⟩ | _ => none⟩
instance : ToValue Uuid := ⟨fun u => .uuid u.text⟩

instance : FromValue InternalId := ⟨"InternalId", fun | .internalId i => some i | _ => none⟩
instance : ToValue InternalId := ⟨.internalId⟩

instance [FromValue α] : FromValue (Option α) where
  typeName := s!"Option {FromValue.typeName α}"
  fromValue?
    | .null => some none
    | v => (fromValue? v : Option α).map some

instance [ToValue α] : ToValue (Option α) := ⟨fun | none => .null | some a => toValue a⟩

instance [FromValue α] : FromValue (Array α) where
  typeName := s!"Array {FromValue.typeName α}"
  fromValue?
    | .list xs | .array xs => xs.mapM fromValue?
    | _ => none

instance [ToValue α] : ToValue (Array α) := ⟨fun xs => .list (xs.map toValue)⟩

instance [FromValue α] : FromValue (List α) where
  typeName := s!"List {FromValue.typeName α}"
  fromValue? v := (fromValue? v : Option (Array α)).map Array.toList

instance [ToValue α] : ToValue (List α) := ⟨fun xs => .list (xs.toArray.map toValue)⟩

/-- Decode a named field of a struct or node value; a missing field decodes as NULL. -/
def decodeField [FromValue α] (v : Value) (name : String) : Option α :=
  fromValue? ((v.field? name).getD .null)

/-! ## Rows -/

structure Row where
  columns : Array String
  values : Array Value
  deriving Inhabited

namespace Row

def columnName (r : Row) (i : Nat) : String := r.columns[i]?.getD s!"#{i}"

/-- Index of a column by exact name, or else by the part after its last `.`
(`RETURN p.name` produces a column called `p.name`). -/
def columnIndex? (r : Row) (name : String) : Option Nat :=
  r.columns.findIdx? (· == name) <|>
    r.columns.findIdx? fun c => (c.splitOn ".").getLast? == some name

def decodeAt [FromValue α] (r : Row) (i : Nat) : Except Error α :=
  match r.values[i]? with
  | none => .error (.decode (r.columnName i) (FromValue.typeName α) "missing column")
  | some v => match fromValue? v with
    | some a => .ok a
    | none => .error (.decode (r.columnName i) (FromValue.typeName α) v.kind)

/-- Decode the column with this name; a missing column decodes as NULL. -/
def decodeNamed [FromValue α] (r : Row) (name : String) : Except Error α :=
  match r.columnIndex? name with
  | some i => r.decodeAt i
  | none => match (fromValue? .null : Option α) with
    | some a => .ok a
    | none => .error (.decode name (FromValue.typeName α) "missing column")

end Row

-- @tg: implements:: [[openspec:native-connection#Row decoding]]
/-- Decoding of a result row. `decodeFrom r i` starts at column `i` and returns
the index of the first column it did not use. -/
class FromRow (α : Type) where
  decodeFrom : Row → Nat → Except Error (α × Nat)

instance (priority := low) [FromValue α] : FromRow α where
  decodeFrom r i := return (← r.decodeAt i, i + 1)

instance [FromRow α] [FromRow β] : FromRow (α × β) where
  decodeFrom r i := do
    let (a, j) ← FromRow.decodeFrom r i
    let (b, k) ← FromRow.decodeFrom r j
    return ((a, b), k)

instance : FromRow Unit := ⟨fun _ i => .ok ((), i)⟩
instance : FromRow Row := ⟨fun r _ => .ok (r, r.values.size)⟩

/-- Decode a whole row, failing if columns are left over. -/
def FromRow.decode [FromRow α] (r : Row) : Except Error α := do
  let (a, n) ← FromRow.decodeFrom r 0
  unless n == r.values.size do
    throw (.decode (r.columnName n) s!"{n} columns" s!"{r.values.size} columns")
  return a

end Ladybug
