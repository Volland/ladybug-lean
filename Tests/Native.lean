import Tests.Framework
import Ladybug.Decode.Derive

/-! Tests for the `native-library` and `native-connection` capabilities. -/

namespace Tests.Native

open Ladybug

/-! ## native-library -/

-- @tg: verifies:: [[openspec:native-library#Pinned library version#First build fetches the locked version]] {level: integration}
def fetchesLockedVersion : IO Unit := do
  let locked := (← IO.FS.readFile "lbug.lock").trimAscii.toString
  assertEq (← Ladybug.version) locked "runtime version"

-- @tg: verifies:: [[openspec:native-library#Executables find the library at runtime#Run built executable directly]] {level: integration}
def findsLibraryWithoutSearchPath : IO Unit := do
  let vars := ["DYLD_LIBRARY_PATH", "DYLD_FALLBACK_LIBRARY_PATH", "LD_LIBRARY_PATH"]
  let set ← vars.filterM fun v => return ((← IO.getEnv v).getD "").length > 0
  if set.isEmpty then
    assertEq (← inMem (queryAs Int64 "RETURN 7 AS x")) #[7] "query result"
  else
    -- `lake test` and `lake exe` set library paths; check in a child without them.
    let out ← IO.Process.output {
      cmd := (← IO.appPath).toString
      env := (vars.map (·, none)).toArray.push ("TEST_FILTER", some "no library search path needed") }
    check (out.exitCode == 0 && (out.stdout.splitOn "1/1 passed").length > 1)
      s!"without library paths:\n{out.stdout}{out.stderr}"

private def readBytes (path : System.FilePath) : IO ByteArray := IO.FS.readBinFile path

-- @tg: verifies:: [[openspec:native-library#Storage version check#Incompatible database file]] {level: integration}
def incompatibleStorage : IO Unit := do
  let path ← freshPath "storage-v39"
  let unpacked ← try
      let gunzip ← IO.Process.spawn
        { cmd := "sh", args := #["-c", s!"gunzip -c Tests/fixtures/storage-v39.lbug.gz > '{path}'"] }
      pure ((← gunzip.wait) == 0)
    catch _ => pure false
  unless unpacked do skipTest "needs sh and gunzip to unpack the fixture"
  let before ← readBytes path
  let e ← expectError (Database.open path) (fun | .storageMismatch .. => true | _ => false) "open"
  match e with
  | .storageMismatch file linked _ =>
    assertEq file (some 39) "file version"
    assertEq linked (← storageVersion) "linked version"
  | _ => pure ()
  check ((← readBytes path) == before) "database file was modified"

-- @tg: verifies:: [[openspec:native-library#Storage version check#Compatible or new database]] {level: integration}
def compatibleStorage : IO Unit := do
  let path ← freshPath "storage-new"
  lbug do
    let db ← Database.open path
    db.withConnection (exec "CREATE NODE TABLE T(id INT64, PRIMARY KEY(id))")
  lbug do discard (Database.open path)

/-! ## native-connection: open database -/

-- @tg: verifies:: [[openspec:native-connection#Open database#In-memory database]] {level: integration}
def inMemoryDatabase : IO Unit := do
  let rs ← inMem (queryRaw "RETURN 1 AS x")
  assertEq rs.columns #["x"] "columns"
  check (rs.rows.size == 1 && rs.rows[0]![0]! == .int64 1) s!"rows: {rs.rows}"

-- @tg: verifies:: [[openspec:native-connection#Open database#On-disk persistence]] {level: integration}
def onDiskPersistence : IO Unit := do
  let path ← freshPath "persist"
  lbug do
    (← Database.open path).withConnection do
      exec "CREATE NODE TABLE P(id INT64, PRIMARY KEY(id)); CREATE (:P {id: 42})"
  let ids ← lbug do (← Database.open path).withConnection (queryAs Int64 "MATCH (p:P) RETURN p.id")
  assertEq ids #[42] "ids after reopen"

-- @tg: verifies:: [[openspec:native-connection#Open database#Read-only rejects writes]] {level: integration}
def readOnlyRejectsWrites : IO Unit := do
  let path ← freshPath "readonly"
  lbug do
    (← Database.open path).withConnection do
      exec "CREATE NODE TABLE P(id INT64, PRIMARY KEY(id)); CREATE (:P {id: 1})"
  let db ← lbug (Database.open path { readOnly := true })
  discard <| expectError (db.withConnection (exec "CREATE (:P {id: 2})"))
    (fun | .query _ => true | _ => false) "write on read-only database"
  assertEq (← lbug (db.withConnection (queryAs Int64 "MATCH (p:P) RETURN count(*)"))) #[1] "count"

/-! ## Handle lifetimes -/

-- @tg: verifies:: [[openspec:native-connection#Handle lifetimes#Database dropped before connection]] {level: integration}
def databaseDroppedFirst : IO Unit := do
  -- `connOpen` consumes the only Lean reference to the database.
  let conn ← do
    let db ← match ← FFI.dbOpen ":memory:" 0 0 false 0 with
      | .ok db => pure db
      | .error e => fail e
    match ← FFI.connOpen db with
    | .ok c => pure c
    | .error e => fail e
  for i in [0:100] do
    match ← FFI.connQuery conn s!"RETURN {i} AS x" with
    | .ok r => match ← FFI.resultNext r with
      | .ok (some row) => check (row[0]! == .int64 (Int64.ofNat i)) s!"row {i}"
      | _ => fail s!"no row {i}"
    | .error e => fail e

-- @tg: verifies:: [[openspec:native-connection#Handle lifetimes#Many short-lived results]] {level: integration}
def manyShortLivedResults : IO Unit := inMem do
  for _ in [0:10000] do
    discard (queryRaw "RETURN 1 AS x")

/-! ## Run Cypher text -/

-- @tg: verifies:: [[openspec:native-connection#Run Cypher text#Multiple statements]] {level: integration}
def multipleStatements : IO Unit := do
  let all ← inMem fun c => c.queryAll
    "CREATE NODE TABLE P(id INT64, PRIMARY KEY(id)); CREATE (:P {id: 1}); MATCH (p:P) RETURN p.id"
  assertEq all.size 3 "result count"
  check (all.back!.rows == #[#[.int64 1]]) s!"last rows: {all.back!.rows}"

-- @tg: verifies:: [[openspec:native-connection#Run Cypher text#Syntax error]] {level: integration}
def syntaxError : IO Unit := do
  let db ← lbug (Database.open ":memory:")
  let e ← expectError (db.withConnection (exec "MATC (n) RETURN n"))
    (fun | .query _ => true | _ => false) "syntax error"
  check (!e.message.isEmpty) "empty message"

/-! ## Prepared parameters -/

-- @tg: verifies:: [[openspec:native-connection#Prepared parameters#Bind scalar and nested parameters]] {level: integration}
def bindParameters : IO Unit := do
  let rows ← inMem <| queryAs (Int64 × Array Int64 × Value) "RETURN $a + 1 AS x, $xs AS xs, $s AS s"
    #[param "a" (41 : Int64), param "xs" #[(1 : Int64), 2, 3],
      ("s", .struct #[("name", .string "x"), ("n", .int64 2)])]
  let (x, xs, s) := rows[0]!
  assertEq x 42 "x"
  assertEq xs #[1, 2, 3] "xs"
  check (s.field? "name" == some (.string "x") && s.field? "n" == some (.int64 2)) s!"s: {s}"

-- @tg: verifies:: [[openspec:native-connection#Prepared parameters#Injection-shaped string is data]] {level: integration}
def injectionIsData : IO Unit := inMem do
  exec "CREATE NODE TABLE N(id INT64, PRIMARY KEY(id)); CREATE (:N {id: 1})"
  let evil := "x'}) DETACH DELETE n //"
  let back ← queryAs String "MATCH (n:N) RETURN $s AS s" #[param "s" evil]
  unless back == #[evil] do throw (.custom s!"returned {back}")
  let n ← queryAs Int64 "MATCH (n:N) RETURN count(*)"
  unless n == #[1] do throw (.custom s!"nodes: {n}")

-- @tg: verifies:: [[openspec:native-connection#Prepared parameters#Missing parameter]] {level: integration}
def missingParameter : IO Unit := do
  let db ← lbug (Database.open ":memory:")
  let e ← expectError (db.withConnection fun c => do (← c.prepare "RETURN $a + 1 AS x").execute)
    (fun | .bind .. => true | _ => false) "missing parameter"
  match e with
  | .bind p _ => assertEq p "a" "parameter name"
  | _ => pure ()

/-! ## Value model -/

-- @tg: verifies:: [[openspec:native-connection#Value model#Round trip of every scalar kind]] {level: integration}
def everyScalarKind : IO Unit := do
  let rs ← inMem <| queryRaw <| "RETURN true, CAST(-8 AS INT8), CAST(-16 AS INT16), CAST(-32 AS INT32), " ++
    "CAST(-64 AS INT64), CAST(8 AS UINT8), CAST(16 AS UINT16), CAST(32 AS UINT32), CAST(64 AS UINT64), " ++
    "CAST('-170141183460469231731687303715884105728' AS INT128), CAST(1.5 AS FLOAT), CAST(2.25 AS DOUBLE), " ++
    "CAST('3.14' AS DECIMAL(5, 2)), 'text', BLOB('\\\\xAA\\\\xBB'), " ++
    "UUID('a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11'), DATE('1970-01-11'), " ++
    "TIMESTAMP('1970-01-01 00:00:01'), CAST(TIMESTAMP('1970-01-01 00:00:01') AS TIMESTAMP_NS), " ++
    "CAST(TIMESTAMP('1970-01-01 00:00:01') AS TIMESTAMP_MS), CAST(TIMESTAMP('1970-01-01 00:00:01') AS TIMESTAMP_SEC), " ++
    "CAST(TIMESTAMP('1970-01-01 00:00:01') AS TIMESTAMP_TZ), INTERVAL('1 year 2 days'), NULL"
  let row := rs.rows[0]!
  let expected : Array Value := #[.bool true, .int8 (-8), .int16 (-16), .int32 (-32), .int64 (-64),
    .uint8 8, .uint16 16, .uint32 32, .uint64 64, .int128 (-170141183460469231731687303715884105728),
    .float 1.5, .double 2.25, .decimal "3.14", .string "text", .blob ⟨#[0xAA, 0xBB]⟩,
    .uuid "a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11", .date 10, .timestamp 1000000, .timestampNs 1000000000,
    .timestampMs 1000, .timestampSec 1, .timestampTz 1000000, .interval 12 2 0, .null]
  assertEq row.size expected.size "column count"
  for (a, e) in row.zip expected do
    check (a == e) s!"expected {e} ({e.kind}), got {a} ({a.kind})"
  let nested ← inMem <| queryRaw <| "RETURN [1, 2], CAST([1, 2] AS INT64[2]), {x: 1, y: 'z'}, " ++
    "map([1], ['a']), union_value(k := 1), []"
  let expectedNested : Array Value := #[.list #[.int64 1, .int64 2], .array #[.int64 1, .int64 2],
    .struct #[("x", .int64 1), ("y", .string "z")], .map #[(.int64 1, .string "a")],
    .union "k" (.int64 1), .list #[]]
  for (a, e) in nested.rows[0]!.zip expectedNested do
    check (a == e) s!"expected {e} ({e.kind}), got {a} ({a.kind})"

-- @tg: verifies:: [[openspec:native-connection#Value model#Node and relationship values]] {level: integration}
def nodeAndRelValues : IO Unit := do
  let rows ← inMem do
    exec "CREATE NODE TABLE P(id INT64, name STRING, PRIMARY KEY(id)); CREATE REL TABLE K(FROM P TO P, since INT64)"
    exec "CREATE (:P {id: 1, name: 'a'})-[:K {since: 2020}]->(:P {id: 2, name: 'b'})"
    queryAs (Value × Value × Value) "MATCH (a:P)-[r:K]->(b:P) RETURN a, r, b"
  let (a, r, b) := rows[0]!
  match a, r, b with
  | .node ai al ap, .rel _ rs rd rl rp, .node bi bl _ =>
    assertEq al "P" "a label"; assertEq bl "P" "b label"; assertEq rl "K" "rel label"
    check (ap.contains ("name", .string "a")) s!"a props: {a}"
    check (rp.contains ("since", .int64 2020)) s!"r props: {r}"
    check (rs == ai && rd == bi) s!"endpoints: {r}"
  | _, _, _ => fail s!"unexpected kinds: {a.kind} {r.kind} {b.kind}"

-- @tg: verifies:: [[openspec:native-connection#Value model#Path values]] {level: integration}
def pathValues : IO Unit := do
  let rows ← inMem do
    exec "CREATE NODE TABLE P(id INT64, PRIMARY KEY(id)); CREATE REL TABLE K(FROM P TO P)"
    exec "CREATE (:P {id: 1})-[:K]->(:P {id: 2})-[:K]->(:P {id: 3})"
    queryAs Value "MATCH p = (a:P)-[:K*1..2]->(b:P) WHERE a.id = 1 AND b.id = 3 RETURN p"
  match rows with
  | #[.path ns rs] =>
    let ids := ns.filterMap (·.field? "id")
    check (ids == #[.int64 1, .int64 2, .int64 3]) s!"path nodes: {ids}"
    assertEq rs.size 2 "path rels"
  | _ => fail s!"unexpected rows: {rows}"

-- @tg: verifies:: [[openspec:native-connection#Value model#Values outlive the result]] {level: integration}
def valuesOutliveResult : IO Unit := do
  let rows ← inMem (queryAs (Int64 × String) "UNWIND range(1, 1000) AS i RETURN i, 'v' + CAST(i AS STRING)")
  assertEq rows.size 1000 "row count"
  for (i, s) in rows do
    assertEq s s!"v{i}" "value"

/-! ## Row decoding -/

structure PersonRow where
  name : String
  age : Int64
  deriving FromRow, BEq, Repr

instance : ToString PersonRow := ⟨fun p => s!"⟨{p.name}, {p.age}⟩"⟩

-- @tg: verifies:: [[openspec:native-connection#Row decoding#Decode tuple rows]] {level: integration}
def decodeTupleRows : IO Unit := do
  let rows ← inMem (queryAs (String × Int64) "RETURN 'a' AS s, 1 AS n")
  check (rows == #[("a", 1)]) s!"rows: {rows}"

-- @tg: verifies:: [[openspec:native-connection#Row decoding#NULL into Option and into a non-Option]] {level: integration}
def decodeNull : IO Unit := do
  assertEq (← inMem (queryAs (Option Int64) "RETURN NULL AS x")) #[none] "Option"
  let db ← lbug (Database.open ":memory:")
  let e ← expectError (db.withConnection (queryAs Int64 "RETURN NULL AS x"))
    (fun | .decode .. => true | _ => false) "NULL into Int64"
  match e with
  | .decode col _ actual => assertEq col "x" "column"; assertEq actual "NULL" "actual"
  | _ => pure ()

-- @tg: verifies:: [[openspec:native-connection#Row decoding#Decode structure by column names]] {level: integration}
def decodeStructure : IO Unit := do
  let rows ← inMem (queryAs PersonRow "RETURN 30 AS age, 'b' AS name")
  assertEq rows #[{ name := "b", age := 30 }] "rows"

/-! ## Transactions -/

private def countP : LbugM Int64 := do
  return (← queryAs Int64 "MATCH (p:P) RETURN count(*)")[0]!

private def withPTable (path : String) : IO Database := lbug do
  let db ← Database.open path
  db.withConnection (exec "CREATE NODE TABLE P(id INT64, PRIMARY KEY(id))")
  return db

-- @tg: verifies:: [[openspec:native-connection#Transactions#Commit on success]] {level: integration}
def commitOnSuccess : IO Unit := do
  let db ← withPTable (← freshPath "tx-commit")
  lbug <| db.withConnection <| withTx (exec "CREATE (:P {id: 1})")
  assertEq (← lbug (db.withConnection countP)) 1 "count from a new connection"

-- @tg: verifies:: [[openspec:native-connection#Transactions#Roll back on error]] {level: integration}
def rollbackOnError : IO Unit := do
  let db ← withPTable (← freshPath "tx-rollback")
  let e ← expectError (db.withConnection <| withTx (α := Unit) do
      exec "CREATE (:P {id: 1})"
      throw (.custom "boom"))
    (· == .custom "boom") "body error"
  assertEq e (.custom "boom") "propagated error"
  assertEq (← lbug (db.withConnection countP)) 0 "count after rollback"

-- @tg: verifies:: [[openspec:native-connection#Transactions#Nested bracket rejected]] {level: integration}
def nestedRejected : IO Unit := do
  let db ← withPTable (← freshPath "tx-nested")
  discard <| expectError (db.withConnection <| withTx do
      exec "CREATE (:P {id: 1})"
      withTx (exec "CREATE (:P {id: 2})"))
    (fun | .transaction _ => true | _ => false) "nested bracket"
  assertEq (← lbug (db.withConnection countP)) 0 "count after outer rollback"

/-! ## Structured errors -/

-- @tg: verifies:: [[openspec:native-connection#Structured errors#Catch a query error]] {level: integration}
def catchQueryError : IO Unit := do
  let msg ← inMem do
    try
      exec "MATCH (n:Missing) RETURN n"
      return "no error"
    catch
      | .query m => return m
      | e => return s!"wrong kind: {e}"
  check ((msg.splitOn "Missing").length > 1) s!"message: {msg}"

def tests : List Test := [
  ⟨"native-library: runtime version matches lbug.lock", fetchesLockedVersion⟩,
  ⟨"native-library: no library search path needed", findsLibraryWithoutSearchPath⟩,
  ⟨"native-library: incompatible storage refused", incompatibleStorage⟩,
  ⟨"native-library: compatible storage opens", compatibleStorage⟩,
  ⟨"native-connection: in-memory database", inMemoryDatabase⟩,
  ⟨"native-connection: on-disk persistence", onDiskPersistence⟩,
  ⟨"native-connection: read-only rejects writes", readOnlyRejectsWrites⟩,
  ⟨"native-connection: database dropped before connection", databaseDroppedFirst⟩,
  ⟨"native-connection: many short-lived results", manyShortLivedResults⟩,
  ⟨"native-connection: multiple statements", multipleStatements⟩,
  ⟨"native-connection: syntax error", syntaxError⟩,
  ⟨"native-connection: bind scalar and nested parameters", bindParameters⟩,
  ⟨"native-connection: injection-shaped string is data", injectionIsData⟩,
  ⟨"native-connection: missing parameter", missingParameter⟩,
  ⟨"native-connection: every scalar kind", everyScalarKind⟩,
  ⟨"native-connection: node and relationship values", nodeAndRelValues⟩,
  ⟨"native-connection: path values", pathValues⟩,
  ⟨"native-connection: values outlive the result", valuesOutliveResult⟩,
  ⟨"native-connection: decode tuple rows", decodeTupleRows⟩,
  ⟨"native-connection: decode NULL", decodeNull⟩,
  ⟨"native-connection: decode structure by column names", decodeStructure⟩,
  ⟨"native-connection: commit on success", commitOnSuccess⟩,
  ⟨"native-connection: roll back on error", rollbackOnError⟩,
  ⟨"native-connection: nested bracket rejected", nestedRejected⟩,
  ⟨"native-connection: catch a query error", catchQueryError⟩
]

end Tests.Native
