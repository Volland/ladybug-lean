import Tests.Native
import Tests.Typed

def main : IO UInt32 := do
  Tests.runAll (Tests.Native.tests ++ Tests.Typed.tests)
