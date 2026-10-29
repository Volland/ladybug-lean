#!/bin/sh
# Build-level checks of the native-library capability that the test binary
# cannot do from inside: download caching, lock updates and the local override.
set -eu
cd "$(dirname "$0")/.."

fail() { echo "FAIL: $*" >&2; exit 1; }

# @tg: verifies:: [[openspec:native-library#Pinned library version#Rebuild does not re-download]] {level: integration}
check_no_redownload() {
  lake build tests >/dev/null
  out=$(lake build tests -v 2>&1)
  if echo "$out" | grep -q "downloading Ladybug"; then fail "rebuild downloaded the library again"; fi
  echo "ok    rebuild does not re-download"
}

# @tg: verifies:: [[openspec:native-library#Pinned library version#Update resolves latest]] {level: integration}
check_update_resolves_latest() {
  cp lbug.lock lbug.lock.bak
  trap 'mv lbug.lock.bak lbug.lock' EXIT
  echo "0.0.1" > lbug.lock
  lake run lbug-update >/dev/null
  latest=$(curl -fsSL https://api.github.com/repos/LadybugDB/ladybug/releases/latest | sed -n 's/.*"tag_name": *"v\{0,1\}\([^"]*\)".*/\1/p')
  [ "$(cat lbug.lock)" = "$latest" ] || fail "lbug.lock is $(cat lbug.lock), latest is $latest"
  mv lbug.lock.bak lbug.lock
  trap - EXIT
  echo "ok    update resolves latest ($latest)"
}

# @tg: verifies:: [[openspec:native-library#Library override#Local build is used]] {level: integration}
check_override() {
  ver=$(cat lbug.lock)
  src=$(ls -d .lake/lbug/"$ver"/*/ | head -1)
  local_dir="$PWD/.lake/test-tmp/local-lbug"
  rm -rf "$local_dir" && mkdir -p "$local_dir" && cp -R "$src". "$local_dir"
  out=$(LBUG_LIB_DIR="$local_dir" lake build tests -v 2>&1)
  if echo "$out" | grep -q "downloading Ladybug"; then fail "the override downloaded the library"; fi
  strings .lake/build/c/lbug_shim.o | grep -q "test-tmp/local-lbug" || fail "the shim does not load the override"
  .lake/build/bin/tests >/dev/null || fail "tests fail with the override"
  lake build tests >/dev/null
  echo "ok    LBUG_LIB_DIR override is used"
}

check_no_redownload
check_update_resolves_latest
check_override
