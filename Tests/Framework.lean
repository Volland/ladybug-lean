import LadybugNative

/-!
# A minimal test harness

A test is a named `IO Unit` that throws on failure.
-/

namespace Tests

open Ladybug

structure Test where
  name : String
  run : IO Unit

def fail {α : Type} (msg : String) : IO α := throw (IO.userError msg)

/-- Skip a test whose prerequisite is missing on this machine; reported, not counted as passed. -/
def skipTest {α : Type} (reason : String) : IO α := throw (IO.userError s!"SKIP: {reason}")

def check (cond : Bool) (msg : String) : IO Unit := unless cond do fail msg

def assertEq {α : Type} [BEq α] [ToString α] (actual expected : α) (what : String := "value") : IO Unit :=
  unless actual == expected do fail s!"{what}: expected {expected}, got {actual}"

/-- Run a Ladybug computation, failing the test on any `Ladybug.Error`. -/
def lbug {α : Type} (m : LbugIO α) : IO α := m.toIO

/-- Expect `m` to fail with an error accepted by `ok`. -/
def expectError {α : Type} (m : LbugIO α) (ok : Error → Bool) (what : String) : IO Error := do
  match ← m.run with
  | .ok _ => fail s!"{what}: expected an error, but it succeeded"
  | .error e => if ok e then return e else fail s!"{what}: unexpected error {e}"

/-- Run `m` on a fresh in-memory database. -/
def inMem {α : Type} (m : LbugM α) : IO α :=
  lbug do (← Database.open ":memory:").withConnection m

/-- A fresh, nonexistent path for an on-disk database under `.lake/test-tmp`. -/
def freshPath (name : String) : IO String := do
  let dir : System.FilePath := ".lake" / "test-tmp"
  IO.FS.createDirAll dir
  let path := dir / s!"{name}.lbug"
  for p in [path, path.addExtension "wal", path.addExtension "lock", path.addExtension "shadow"] do
    if ← p.pathExists then
      if ← p.isDir then IO.FS.removeDirAll p else IO.FS.removeFile p
  return path.toString

/-- Run every test and print a summary; the exit code is the number of failures. -/
def runAll (tests : List Test) : IO UInt32 := do
  let filter := (← IO.getEnv "TEST_FILTER").getD ""
  let mut failed := 0
  let mut skipped := 0
  let mut ran := 0
  for t in tests do
    unless filter.isEmpty || (t.name.splitOn filter).length > 1 do continue
    ran := ran + 1
    try
      t.run
      IO.println s!"  ok    {t.name}"
    catch e =>
      let msg := toString e
      if msg.startsWith "SKIP: " then
        skipped := skipped + 1
        IO.println s!"  skip  {t.name}: {(msg.drop 6).toString}"
      else
        failed := failed + 1
        IO.println s!"  FAIL  {t.name}\n        {e}"
  IO.println s!"{ran - failed - skipped}/{ran} passed, {skipped} skipped"
  return failed.toUInt32

end Tests
