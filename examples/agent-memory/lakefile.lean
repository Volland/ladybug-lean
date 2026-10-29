import Lake
open Lake DSL

package «agent-memory» where
  leanOptions := #[⟨`autoImplicit, false⟩]

-- In your own project, depend on the published package instead:
--   require ladybug from git "https://github.com/Volland/ladybug-lean" @ "v0.1.0"
require ladybug from "../.."

lean_lib AgentMemory

@[default_target]
lean_exe «agent-memory» where
  root := `Main
