import Ladybug.Value

/-!
# Raw FFI

`@[extern]` declarations over `c/lbug_shim.c`. Every handle is a reference-counted
external object that keeps its parent alive (see the shim's header comment), so
these functions are memory-safe in any order of use; the safe API in
`LadybugNative` adds error mapping and transactions on top.
-/

namespace Ladybug.FFI

opaque DatabasePtr : NonemptyType
opaque ConnectionPtr : NonemptyType
opaque PreparedPtr : NonemptyType
opaque ResultPtr : NonemptyType
opaque NValuePtr : NonemptyType

-- @tg: implements:: [[openspec:native-connection#Handle lifetimes]]
/-- A native database handle. -/
def Database : Type := DatabasePtr.type
/-- A native connection; keeps its database alive. -/
def Connection : Type := ConnectionPtr.type
/-- A prepared statement; keeps its connection alive. -/
def Prepared : Type := PreparedPtr.type
/-- A query result; keeps its connection (or its first result) alive. -/
def Result : Type := ResultPtr.type
/-- A native value used as a parameter. -/
def NValue : Type := NValuePtr.type

instance : Nonempty Database := DatabasePtr.property
instance : Nonempty Connection := ConnectionPtr.property
instance : Nonempty Prepared := PreparedPtr.property
instance : Nonempty Result := ResultPtr.property
instance : Nonempty NValue := NValuePtr.property

@[extern "lbug_lean_version"] opaque version : IO String
@[extern "lbug_lean_storage_version"] opaque storageVersion : IO UInt64

@[extern "lbug_lean_db_open"]
opaque dbOpen (path : @& String) (bufferPoolSize maxThreads : UInt64) (readOnly : Bool)
  (maxDbSize : UInt64) : IO (Except String Database)

@[extern "lbug_lean_conn_open"] opaque connOpen (db : Database) : IO (Except String Connection)

@[extern "lbug_lean_conn_query"]
opaque connQuery (c : @& Connection) (q : @& String) : IO (Except String Result)

@[extern "lbug_lean_conn_prepare"]
opaque connPrepare (c : @& Connection) (q : @& String) : IO (Except String Prepared)

@[extern "lbug_lean_stmt_bind"]
opaque stmtBind (p : @& Prepared) (name : @& String) (v : @& NValue) : IO (Except String Unit)

@[extern "lbug_lean_conn_execute"]
opaque connExecute (c : @& Connection) (p : @& Prepared) : IO (Except String Result)

@[extern "lbug_lean_result_columns"] opaque resultColumns (r : @& Result) : IO (Array String)

/-- The next row, copied out of the native result, or `none` at the end. -/
@[extern "lbug_lean_result_next"]
opaque resultNext (r : @& Result) : IO (Except String (Option (Array Value)))

/-- The result of the next statement of a multi-statement query. -/
@[extern "lbug_lean_result_next_result"]
opaque resultNextResult (r : @& Result) : IO (Option (Except String Result))

@[extern "lbug_lean_nv_null"] opaque nvNull : Unit → NValue
@[extern "lbug_lean_nv_bool"] opaque nvBool : Bool → NValue
@[extern "lbug_lean_nv_int8"] opaque nvInt8 : Int8 → NValue
@[extern "lbug_lean_nv_int16"] opaque nvInt16 : Int16 → NValue
@[extern "lbug_lean_nv_int32"] opaque nvInt32 : Int32 → NValue
@[extern "lbug_lean_nv_int64"] opaque nvInt64 : Int64 → NValue
@[extern "lbug_lean_nv_uint8"] opaque nvUInt8 : UInt8 → NValue
@[extern "lbug_lean_nv_uint16"] opaque nvUInt16 : UInt16 → NValue
@[extern "lbug_lean_nv_uint32"] opaque nvUInt32 : UInt32 → NValue
@[extern "lbug_lean_nv_uint64"] opaque nvUInt64 : UInt64 → NValue
@[extern "lbug_lean_nv_int128"] opaque nvInt128 (lo : UInt64) (hi : Int64) : NValue
@[extern "lbug_lean_nv_float"] opaque nvFloat : Float32 → NValue
@[extern "lbug_lean_nv_double"] opaque nvDouble : Float → NValue
@[extern "lbug_lean_nv_string"] opaque nvString : @& String → NValue
@[extern "lbug_lean_nv_uuid"] opaque nvUuid : @& String → NValue
@[extern "lbug_lean_nv_decimal"] opaque nvDecimal (digits : @& String) (precision scale : UInt32) : NValue
@[extern "lbug_lean_nv_blob"] opaque nvBlob : @& ByteArray → NValue
@[extern "lbug_lean_nv_date"] opaque nvDate : Int32 → NValue
@[extern "lbug_lean_nv_timestamp"] opaque nvTimestamp : Int64 → NValue
@[extern "lbug_lean_nv_timestamp_ns"] opaque nvTimestampNs : Int64 → NValue
@[extern "lbug_lean_nv_timestamp_ms"] opaque nvTimestampMs : Int64 → NValue
@[extern "lbug_lean_nv_timestamp_sec"] opaque nvTimestampSec : Int64 → NValue
@[extern "lbug_lean_nv_timestamp_tz"] opaque nvTimestampTz : Int64 → NValue
@[extern "lbug_lean_nv_interval"] opaque nvInterval (months days : Int32) (micros : Int64) : NValue
@[extern "lbug_lean_nv_internal_id"] opaque nvInternalId (table offset : UInt64) : NValue
/-- A NULL of the template's type. -/
@[extern "lbug_lean_nv_null_like"] opaque nvNullLike : @& NValue → NValue
/-- The default value of the template's type: an empty list for a list type. -/
@[extern "lbug_lean_nv_empty_like"] opaque nvEmptyLike : @& NValue → NValue
@[extern "lbug_lean_nv_list"] opaque nvList : @& Array NValue → Except String NValue
@[extern "lbug_lean_nv_struct"]
opaque nvStruct (names : @& Array String) (vals : @& Array NValue) : Except String NValue
@[extern "lbug_lean_nv_map"] opaque nvMap (keys vals : @& Array NValue) : Except String NValue

end Ladybug.FFI
