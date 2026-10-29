import AgentMemory.Memory
import LadybugNative

open Ladybug AgentMemory

/-- The same functions as in `AgentMemory/Checks.lean`, on a LadybugDB file. -/
def main : IO Unit := do
  for p in ["memory.lbug", "memory.lbug.wal"] do
    if ← System.FilePath.pathExists p then IO.FS.removeFile p
  Ladybug.withDatabase "memory.lbug" fun db => db.withConnection do
    seed
    IO.println s!"about Ann:        {← about "Ann"}"
    IO.println s!"near Ann:         {← neighbourhood "Ann"}"
    IO.println s!"memories 1 → 4:   {(← distance 1 4).getD 0} steps"
    IO.println s!"like memory 1:    {← recallSimilar (vec [1, 0, 0, 0]) 2}"
    IO.println s!"nobody mentions:  {← forgotten}"
