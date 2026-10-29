import Tests.Framework
import Tests.Differential

/-!
# Value round-trip properties

For every column type, generated values (with NULLs, extreme integers,
non-ASCII and empty strings, empty lists, nested structs, infinities and
negative zero) are stored in a one-column table and read back on both
backends. Floats are compared bit for bit. A failing value is shrunk before it
is reported.

The generators and shrinking are the project's own, as in the differential
suite, rather than Plausible: Lake has no test-only dependencies, so a
dependency here would reach every package that depends on this one.
-/

namespace Tests.Property

open Ladybug Tests.Differential

/-! ## One table per column type -/

structure Inner where
  x : Int64
  s : Option String
  deriving Ladybug.CypherType

structure RBool where
  id : Int64
  v : Bool
structure RInt8 where
  id : Int64
  v : Int8
structure RInt16 where
  id : Int64
  v : Int16
structure RInt32 where
  id : Int64
  v : Int32
structure RInt64 where
  id : Int64
  v : Int64
structure RUInt8 where
  id : Int64
  v : UInt8
structure RUInt16 where
  id : Int64
  v : UInt16
structure RUInt32 where
  id : Int64
  v : UInt32
structure RUInt64 where
  id : Int64
  v : UInt64
structure RInt128 where
  id : Int64
  v : Int
structure RFloat32 where
  id : Int64
  v : Float32
structure RDouble where
  id : Int64
  v : Float
structure RString where
  id : Int64
  v : String
structure RBlob where
  id : Int64
  v : ByteArray
structure RUuid where
  id : Int64
  v : Uuid
structure RDate where
  id : Int64
  v : Date
structure RTimestamp where
  id : Int64
  v : Timestamp
structure RInterval where
  id : Int64
  v : Interval
structure ROptInt where
  id : Int64
  v : Option Int64
structure ROptString where
  id : Int64
  v : Option String
structure RListInt where
  id : Int64
  v : Array Int64
structure RListString where
  id : Int64
  v : Array String
structure RListOpt where
  id : Int64
  v : Array (Option Int64)
structure RStruct where
  id : Int64
  v : Inner

node_table RBool
node_table RInt8
node_table RInt16
node_table RInt32
node_table RInt64
node_table RUInt8
node_table RUInt16
node_table RUInt32
node_table RUInt64
node_table RInt128
node_table RFloat32
node_table RDouble
node_table RString
node_table RBlob
node_table RUuid
node_table RDate
node_table RTimestamp
node_table RInterval
node_table ROptInt
node_table ROptString
node_table RListInt
node_table RListString
node_table RListOpt
node_table RStruct

/-! ## Comparison -/

/-- Values equal up to float bits: `-0.0 ≠ 0.0`, NaN equal to itself. -/
partial def sameBits : Value → Value → Bool
  | .double a, .double b => a.toBits == b.toBits
  | .float a, .float b => a.toBits == b.toBits
  | .list xs, .list ys | .array xs, .array ys => xs.size == ys.size && (xs.zip ys).all fun (a, b) => sameBits a b
  | .struct xs, .struct ys => xs.size == ys.size && (xs.zip ys).all fun ((k, a), (k', b)) => k == k' && sameBits a b
  | a, b => a == b

/-! ## Generators and shrinking -/

def genInt (lo hi : Int) : Gen Int := do
  match ← nat 0 4 with
  | 0 => pick ((#[lo, hi, 0, -1, 1].filter fun i => decide (lo ≤ i ∧ i ≤ hi)).push 0)
  | _ => return lo + ((← nat 0 1000000000) : Int) % (hi - lo + 1)

def genString : Gen String := do
  match ← nat 0 5 with
  | 0 => pick #["", "héllo", "日本語", "✓ emoji 🦊", "quote ' and \" and \\", "line\nbreak", "tab\tx"]
  | _ =>
    let n ← nat 0 12
    let chars ← (List.range n).mapM fun _ => do
      let c ← nat 32 126
      return Char.ofNat (if (← chance 10) then c + 900 else c)
    return String.ofList chars

def genFloat : Gen Float := do
  match ← nat 0 4 with
  | 0 => pick #[0.0, -0.0, 1.0 / 0.0, -1.0 / 0.0, 1e308, -1e308, 5e-324, 1.5]
  | _ => return (Float.ofNat (← nat 0 2000000) - 1000000.0) / 1000.0

def genUuid : Gen Uuid := do
  let hex (n : Nat) : Gen String := do
    let ds ← (List.range n).mapM fun _ => do return "0123456789abcdef".toList[← nat 0 15]!
    return String.ofList ds
  return ⟨s!"{← hex 8}-{← hex 4}-4{← hex 3}-a{← hex 3}-{← hex 12}"⟩

def genOpt {α : Type} (g : Gen α) : Gen (Option α) := do
  if ← chance 25 then return none else some <$> g

def genArray {α : Type} (g : Gen α) : Gen (Array α) := do
  let n ← if ← chance 20 then pure 0 else nat 1 5
  (Array.range n).mapM fun _ => g

/-- Smaller candidates for a failing value, simplest first. -/
partial def shrinks : Value → List Value
  | .int64 v => if v == 0 then [] else [.int64 0, .int64 (v / 2)]
  | .int128 v => if v == 0 then [] else [.int128 0, .int128 (v / 2)]
  | .string s => if s.isEmpty then [] else [.string "", .string (s.drop 1).toString, .string (s.dropEnd 1).toString]
  | .list xs => if xs.isEmpty then [] else [.list #[], .list (xs.extract 1 xs.size), .list xs.pop]
  | .double d => if d == 0 then [] else [.double 0, .double (d / 2)]
  | _ => []

/-- One column type: how to generate a value, store it and read it back. -/
structure Column where
  name : String
  gen : Gen Value
  roundTrip : {m : Type → Type} → [MonadGraph m] → Int64 → Value → m (Option Value)

def column (name : String) (α : Type) [NodeTable α] [ToValue α] [FromValue α] [NodeKey α Int64]
    (gen : Gen Value) : Column where
  name := name
  gen := gen
  roundTrip id v := do
    let some x := (fromValue? (.struct #[("id", .int64 id), ("v", v)]) : Option α) | return none
    applySchema [.ofNode α]
    Repo.insert x
    return (← Repo.get? α id).map fun y => (toValue y).field? "v" |>.getD .null

def i (lo hi : Int) : Gen Int := genInt lo hi

def columns : List Column := [
  column "BOOL" RBool (do return .bool (← chance 50)),
  column "INT8" RInt8 (do return .int8 (Int8.ofInt (← i (-128) 127))),
  column "INT16" RInt16 (do return .int16 (Int16.ofInt (← i (-32768) 32767))),
  column "INT32" RInt32 (do return .int32 (Int32.ofInt (← i (-2147483648) 2147483647))),
  column "INT64" RInt64 (do return .int64 (Int64.ofInt (← i (-9223372036854775808) 9223372036854775807))),
  column "UINT8" RUInt8 (do return .uint8 (UInt8.ofNat (← i 0 255).toNat)),
  column "UINT16" RUInt16 (do return .uint16 (UInt16.ofNat (← i 0 65535).toNat)),
  column "UINT32" RUInt32 (do return .uint32 (UInt32.ofNat (← i 0 4294967295).toNat)),
  column "UINT64" RUInt64 (do return .uint64 (UInt64.ofNat (← i 0 18446744073709551615).toNat)),
  column "INT128" RInt128 (do return toValue (← i (-170141183460469231731687303715884105728) 170141183460469231731687303715884105727)),
  column "FLOAT" RFloat32 (do return .float (← genFloat).toFloat32),
  column "DOUBLE" RDouble (do return .double (← genFloat)),
  column "STRING" RString (do return .string (← genString)),
  column "BLOB" RBlob (do return .blob ⟨← (Array.range (← nat 0 16)).mapM fun _ => do return UInt8.ofNat (← nat 0 255)⟩),
  column "UUID" RUuid (do return toValue (← genUuid)),
  column "DATE" RDate (do return .date (Int32.ofInt (← i (-719162) 2932896))),
  column "TIMESTAMP" RTimestamp (do return .timestamp (Int64.ofInt (← i (-62135596800000000) 253402300799999999))),
  column "INTERVAL" RInterval (do return .interval (Int32.ofInt (← i (-1000) 1000)) (Int32.ofInt (← i (-1000) 1000)) (Int64.ofInt (← i (-100000000) 100000000))),
  column "INT64 (nullable)" ROptInt (do return toValue (← genOpt (Int64.ofInt <$> i (-1000) 1000))),
  column "STRING (nullable)" ROptString (do return toValue (← genOpt genString)),
  column "INT64[]" RListInt (do return toValue (← genArray (Int64.ofInt <$> i (-1000) 1000))),
  column "STRING[]" RListString (do return toValue (← genArray genString)),
  column "INT64[] with NULLs" RListOpt (do return toValue (← genArray (genOpt (Int64.ofInt <$> i (-1000) 1000)))),
  column "STRUCT" RStruct (do return .struct #[("x", .int64 (Int64.ofInt (← i (-1000) 1000))), ("s", toValue (← genOpt genString))])
]

/-! ## Running -/

inductive Backend where
  | native | memory
  deriving Repr, BEq

def roundTripOn (b : Backend) (c : Column) (v : Value) : IO (Except String Value) := do
  let r ← match b with
    | .native => (do (← Database.open ":memory:").withConnection (c.roundTrip 1 v)).run
    | .memory => pure ((c.roundTrip 1 v : MemM _).run' {})
  return match r with
    | .ok (some w) => .ok w
    | .ok none => .error "not found after insert"
    | .error e => .error (toString e)

def fails (rt : Value → IO (Except String Value)) (v : Value) : IO Bool := do
  match ← rt v with
  | .ok w => return !sameBits v w
  | .error _ => return true

partial def shrinkValue (rt : Value → IO (Except String Value)) (v : Value) : IO Value := do
  for s in shrinks v do
    if ← fails rt s then return ← shrinkValue rt s
  return v

/-- Check `n` generated values of one column type; a report of the first failure, shrunk. -/
def checkColumn (c : Column) (n seed : Nat) (rt : Backend → Value → IO (Except String Value)) :
    IO (Option String) := do
  let mut g := mkStdGen seed
  for _ in [0:n] do
    let (v, g') := c.gen.run g
    g := g'
    for b in [Backend.native, .memory] do
      if ← fails (rt b) v then
        let small ← shrinkValue (rt b) v
        let got := match ← rt b small with
          | .ok w => toString w
          | .error e => s!"error: {e}"
        return some s!"{c.name} on {repr b}: {small} came back as {got}"
  return none

-- @tg: implements:: [[openspec:native-connection#Value round-trip property]]
-- @tg: verifies:: [[openspec:native-connection#Value round-trip property#Generated round trips]] {level: integration}
def generatedRoundTrips : IO Unit := do
  for c in columns do
    if let some report ← checkColumn c 200 17 (roundTripOn · c) then fail report

-- @tg: verifies:: [[openspec:native-connection#Value round-trip property#Counterexample reported]] {level: unit}
def counterexampleReported : IO Unit := do
  -- A broken store that drops the last character of non-empty strings.
  let broken : Backend → Value → IO (Except String Value) := fun _ v => pure <| .ok <| match v with
    | .string s => if s.length > 1 then .string (s.dropEnd 1).toString else .string s
    | v => v
  let some strings := columns.find? (·.name == "STRING") | fail "no STRING column"
  let some report ← checkColumn strings 200 3 broken
    | fail "a broken round trip passed"
  check ((report.splitOn "STRING").length > 1) s!"report lacks the column type: {report}"
  -- Shrinking leaves a two-character string, the smallest that still fails.
  check ((report.splitOn "came back as").length > 1) s!"report lacks the result: {report}"

def tests : List Test := [
  ⟨"native-connection: generated value round trips", generatedRoundTrips⟩,
  ⟨"native-connection: round-trip counterexample reported", counterexampleReported⟩
]

end Tests.Property
