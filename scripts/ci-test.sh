#!/bin/sh
# The CI test step, run on every platform of the matrix in .github/workflows/ci.yml.
set -eu
cd "$(dirname "$0")/.."

# @tg: verifies:: [[openspec:native-library#Supported platforms#Linux build]] {level: e2e}
# @tg: verifies:: [[openspec:native-library#Supported platforms#Windows build]] {level: e2e}
# @tg: verifies:: [[openspec:native-library#Supported platforms#CI matrix]] {level: e2e}
run_suite() {
  echo "platform: $(uname -s 2>/dev/null || echo Windows) $(uname -m 2>/dev/null || true)"
  lake build tests
  lake test
}

run_suite

# The example project builds against this checkout and runs its compile-time checks.
(cd examples/agent-memory && lake build AgentMemory agent-memory)

case "$(uname -s 2>/dev/null || echo Windows)" in
  Linux|Darwin) scripts/check-native-library.sh ;;
  *) echo "build-level checks are not run on this platform" ;;
esac
