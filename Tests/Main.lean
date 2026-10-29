import Tests.Native

def main : IO UInt32 := do
  Tests.runAll Tests.Native.tests
