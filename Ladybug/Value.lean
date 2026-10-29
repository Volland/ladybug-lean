/-!
# Values

Every value Ladybug can return or accept as a parameter, as a pure Lean tree.
Results are copied into this type before the native result is released, so a
`Value` never refers to native memory.
-/

namespace Ladybug

/-- Ladybug's internal node or relationship ID: table ID and offset in the table. -/
structure InternalId where
  table : UInt64
  offset : UInt64
  deriving Repr, BEq, Hashable, Inhabited, Ord, DecidableEq

instance : ToString InternalId := ⟨fun i => s!"{i.table}:{i.offset}"⟩

-- @tg: implements:: [[openspec:native-connection#Value model]]
/-- A Ladybug value. Timestamps count from 1970-01-01 UTC in the unit their
constructor names; `date` counts days. -/
inductive Value where
  | null
  | bool (v : Bool)
  | int8 (v : Int8)
  | int16 (v : Int16)
  | int32 (v : Int32)
  | int64 (v : Int64)
  | uint8 (v : UInt8)
  | uint16 (v : UInt16)
  | uint32 (v : UInt32)
  | uint64 (v : UInt64)
  | int128 (v : Int)
  | float (v : Float32)
  | double (v : Float)
  | decimal (digits : String)
  | string (v : String)
  | blob (v : ByteArray)
  | uuid (v : String)
  | date (days : Int32)
  | timestamp (micros : Int64)
  | timestampNs (nanos : Int64)
  | timestampMs (millis : Int64)
  | timestampSec (secs : Int64)
  | timestampTz (micros : Int64)
  | interval (months days : Int32) (micros : Int64)
  | internalId (id : InternalId)
  | list (xs : Array Value)
  | array (xs : Array Value)
  | struct (fields : Array (String × Value))
  | map (entries : Array (Value × Value))
  /-- A union value; `tag` is the active member's name, or empty when Ladybug
  does not report it (unions with more than one member). -/
  | union (tag : String) (v : Value)
  | node (id : InternalId) (label : String) (props : Array (String × Value))
  | rel (id src dst : InternalId) (label : String) (props : Array (String × Value))
  | path (nodes : Array Value) (rels : Array Value)
  deriving Inhabited

namespace Value

/-- The name of a value's kind, used in decode errors. -/
def kind : Value → String
  | null => "NULL" | bool _ => "BOOL"
  | int8 _ => "INT8" | int16 _ => "INT16" | int32 _ => "INT32" | int64 _ => "INT64"
  | uint8 _ => "UINT8" | uint16 _ => "UINT16" | uint32 _ => "UINT32" | uint64 _ => "UINT64"
  | int128 _ => "INT128" | float _ => "FLOAT" | double _ => "DOUBLE" | decimal _ => "DECIMAL"
  | string _ => "STRING" | blob _ => "BLOB" | uuid _ => "UUID" | date _ => "DATE"
  | timestamp _ => "TIMESTAMP" | timestampNs _ => "TIMESTAMP_NS" | timestampMs _ => "TIMESTAMP_MS"
  | timestampSec _ => "TIMESTAMP_SEC" | timestampTz _ => "TIMESTAMP_TZ"
  | interval .. => "INTERVAL" | internalId _ => "INTERNAL_ID" | list _ => "LIST"
  | array _ => "ARRAY" | struct _ => "STRUCT" | map _ => "MAP" | union .. => "UNION"
  | node .. => "NODE" | rel .. => "REL" | path .. => "RECURSIVE_REL"

private def byteArrayEq (a b : ByteArray) : Bool :=
  a.size == b.size && (List.range a.size).all fun i => a.get! i == b.get! i

/-- Structural equality. Floats compare with `==`, so NaN is unequal to itself. -/
protected partial def beq : Value → Value → Bool
  | null, null => true
  | bool a, bool b => a == b
  | int8 a, int8 b => a == b
  | int16 a, int16 b => a == b
  | int32 a, int32 b => a == b
  | int64 a, int64 b => a == b
  | uint8 a, uint8 b => a == b
  | uint16 a, uint16 b => a == b
  | uint32 a, uint32 b => a == b
  | uint64 a, uint64 b => a == b
  | int128 a, int128 b => a == b
  | float a, float b => a == b
  | double a, double b => a == b
  | decimal a, decimal b => a == b
  | string a, string b => a == b
  | blob a, blob b => byteArrayEq a b
  | uuid a, uuid b => a == b
  | date a, date b => a == b
  | timestamp a, timestamp b => a == b
  | timestampNs a, timestampNs b => a == b
  | timestampMs a, timestampMs b => a == b
  | timestampSec a, timestampSec b => a == b
  | timestampTz a, timestampTz b => a == b
  | interval m d u, interval m' d' u' => m == m' && d == d' && u == u'
  | internalId a, internalId b => a == b
  | list a, list b => arrEq a b
  | array a, array b => arrEq a b
  | struct a, struct b => fieldsEq a b
  | map a, map b =>
    a.size == b.size && (a.zip b).all fun ((k, v), (k', v')) => Value.beq k k' && Value.beq v v'
  | union t v, union t' v' => t == t' && Value.beq v v'
  | node i l p, node i' l' p' => i == i' && l == l' && fieldsEq p p'
  | rel i s d l p, rel i' s' d' l' p' => i == i' && s == s' && d == d' && l == l' && fieldsEq p p'
  | path n r, path n' r' => arrEq n n' && arrEq r r'
  | _, _ => false
where
  arrEq (a b : Array Value) : Bool := a.size == b.size && (a.zip b).all fun (x, y) => Value.beq x y
  fieldsEq (a b : Array (String × Value)) : Bool :=
    a.size == b.size && (a.zip b).all fun ((k, x), (k', y)) => k == k' && Value.beq x y

instance : BEq Value := ⟨Value.beq⟩

private def quote (s : String) : String :=
  "'" ++ (s.replace "\\" "\\\\" |>.replace "'" "\\'") ++ "'"

/-- Render a value in Cypher-like notation, for messages and debugging. -/
protected partial def toString : Value → String
  | null => "NULL"
  | bool b => if b then "true" else "false"
  | int8 v => toString v | int16 v => toString v | int32 v => toString v | int64 v => toString v
  | uint8 v => toString v | uint16 v => toString v | uint32 v => toString v | uint64 v => toString v
  | int128 v => toString v
  | float v => toString v | double v => toString v
  | decimal d => d
  | string s => quote s
  | blob b => s!"BLOB({b.size} bytes)"
  | uuid u => s!"UUID({quote u})"
  | date d => s!"DATE({d} days)"
  | timestamp t => s!"TIMESTAMP({t} us)"
  | timestampNs t => s!"TIMESTAMP_NS({t})"
  | timestampMs t => s!"TIMESTAMP_MS({t})"
  | timestampSec t => s!"TIMESTAMP_SEC({t})"
  | timestampTz t => s!"TIMESTAMP_TZ({t} us)"
  | interval m d u => s!"INTERVAL({m} months, {d} days, {u} us)"
  | internalId i => toString i
  | list xs => "[" ++ ", ".intercalate (xs.map Value.toString).toList ++ "]"
  | array xs => "[" ++ ", ".intercalate (xs.map Value.toString).toList ++ "]"
  | struct fs => "{" ++ ", ".intercalate (fs.map fun (k, v) => s!"{k}: {Value.toString v}").toList ++ "}"
  | map es => "map{" ++ ", ".intercalate (es.map fun (k, v) => s!"{Value.toString k}: {Value.toString v}").toList ++ "}"
  | union t v => s!"{t}: {Value.toString v}"
  | node i l ps =>
    s!"(:{l} \{_ID: {i}" ++ String.join (ps.map fun (k, v) => s!", {k}: {Value.toString v}").toList ++ "})"
  | rel i s d l ps =>
    s!"[:{l} \{_ID: {i}, _SRC: {s}, _DST: {d}" ++
      String.join (ps.map fun (k, v) => s!", {k}: {Value.toString v}").toList ++ "}]"
  | path ns rs => s!"PATH(nodes: {ns.size}, rels: {rs.size})"

instance : ToString Value := ⟨Value.toString⟩
instance : Repr Value := ⟨fun v _ => .text v.toString⟩

/-- Look up a field of a struct, node or relationship value by name. -/
def field? (v : Value) (name : String) : Option Value :=
  match v with
  | struct fs | node _ _ fs | rel _ _ _ _ fs => fs.find? (·.1 == name) |>.map (·.2)
  | _ => none

end Value

/-! Constructors exported to the C shim, which builds results through them so
that only the Lean compiler knows the memory layout of `Value`. -/

namespace Value.Export
@[export lean_lbug_mk_null] def mkNull (_ : Unit) : Value := .null
@[export lean_lbug_mk_bool] def mkBool (v : Bool) : Value := .bool v
@[export lean_lbug_mk_int8] def mkInt8 (v : Int8) : Value := .int8 v
@[export lean_lbug_mk_int16] def mkInt16 (v : Int16) : Value := .int16 v
@[export lean_lbug_mk_int32] def mkInt32 (v : Int32) : Value := .int32 v
@[export lean_lbug_mk_int64] def mkInt64 (v : Int64) : Value := .int64 v
@[export lean_lbug_mk_uint8] def mkUInt8 (v : UInt8) : Value := .uint8 v
@[export lean_lbug_mk_uint16] def mkUInt16 (v : UInt16) : Value := .uint16 v
@[export lean_lbug_mk_uint32] def mkUInt32 (v : UInt32) : Value := .uint32 v
@[export lean_lbug_mk_uint64] def mkUInt64 (v : UInt64) : Value := .uint64 v
@[export lean_lbug_mk_int128] def mkInt128 (lo : UInt64) (hi : Int64) : Value :=
  .int128 (hi.toInt * 18446744073709551616 + lo.toNat)
@[export lean_lbug_mk_float] def mkFloat (v : Float32) : Value := .float v
@[export lean_lbug_mk_double] def mkDouble (v : Float) : Value := .double v
@[export lean_lbug_mk_decimal] def mkDecimal (v : String) : Value := .decimal v
@[export lean_lbug_mk_string] def mkString (v : String) : Value := .string v
@[export lean_lbug_mk_blob] def mkBlob (v : ByteArray) : Value := .blob v
@[export lean_lbug_mk_uuid] def mkUuid (v : String) : Value := .uuid v
@[export lean_lbug_mk_date] def mkDate (v : Int32) : Value := .date v
@[export lean_lbug_mk_timestamp] def mkTimestamp (v : Int64) : Value := .timestamp v
@[export lean_lbug_mk_timestamp_ns] def mkTimestampNs (v : Int64) : Value := .timestampNs v
@[export lean_lbug_mk_timestamp_ms] def mkTimestampMs (v : Int64) : Value := .timestampMs v
@[export lean_lbug_mk_timestamp_sec] def mkTimestampSec (v : Int64) : Value := .timestampSec v
@[export lean_lbug_mk_timestamp_tz] def mkTimestampTz (v : Int64) : Value := .timestampTz v
@[export lean_lbug_mk_interval] def mkInterval (m d : Int32) (u : Int64) : Value := .interval m d u
@[export lean_lbug_mk_internal_id] def mkInternalId (t o : UInt64) : Value := .internalId ⟨t, o⟩
@[export lean_lbug_mk_list] def mkList (xs : Array Value) : Value := .list xs
@[export lean_lbug_mk_array] def mkArray (xs : Array Value) : Value := .array xs
@[export lean_lbug_mk_field] def mkField (k : String) (v : Value) : String × Value := (k, v)
@[export lean_lbug_mk_entry] def mkEntry (k v : Value) : Value × Value := (k, v)
@[export lean_lbug_mk_struct] def mkStruct (fs : Array (String × Value)) : Value := .struct fs
@[export lean_lbug_mk_map] def mkMap (es : Array (Value × Value)) : Value := .map es
@[export lean_lbug_mk_union] def mkUnion (t : String) (v : Value) : Value := .union t v
@[export lean_lbug_mk_node] def mkNode (t o : UInt64) (l : String) (ps : Array (String × Value)) : Value :=
  .node ⟨t, o⟩ l ps
@[export lean_lbug_mk_rel] def mkRel (t o st so dt do_ : UInt64) (l : String)
    (ps : Array (String × Value)) : Value :=
  .rel ⟨t, o⟩ ⟨st, so⟩ ⟨dt, do_⟩ l ps
@[export lean_lbug_mk_path] def mkPath (ns rs : Array Value) : Value := .path ns rs
end Value.Export

end Ladybug
