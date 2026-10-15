# shellcheck shell=bash
# Shared by every .bats file: the repo root, the library under test and a
# scratch directory that teardown removes.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export REPO_ROOT
export FIXTURES="$BATS_TEST_DIRNAME/fixtures"

common_setup() {
  # shellcheck source=../scripts/lib.sh
  source "$REPO_ROOT/scripts/lib.sh"
  scratch="$(mktemp -d)"
  # No sleeping between attempts in tests.
  export RETRY_DELAY=0
}

common_teardown() {
  rm -rf "$scratch"
}
