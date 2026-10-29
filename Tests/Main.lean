import Tests.Native
import Tests.Typed
import Tests.Syntax
import Tests.ORM
import Tests.Advanced
import Tests.Memory
import Tests.Differential
import Tests.Property
import Tests.SiteSnippets

def main : IO UInt32 := do
  Tests.runAll (Tests.Native.tests ++ Tests.Typed.tests ++ Tests.Syntax.tests ++ Tests.ORM.tests ++
    Tests.Advanced.tests ++ Tests.Memory.tests ++ Tests.Differential.tests ++ Tests.Property.tests)
