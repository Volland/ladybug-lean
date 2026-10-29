import Tests.Native
import Tests.Typed
import Tests.Syntax

def main : IO UInt32 := do
  Tests.runAll (Tests.Native.tests ++ Tests.Typed.tests ++ Tests.Syntax.tests)
