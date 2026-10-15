#!/usr/bin/env bash
# Every shell file in the repo, found by name rather than listed by hand, so
# a new script can't slip past the linter. The pre-push hook and CI both run
# this, so they check the same set.
set -euo pipefail

cd "$(dirname "$0")/.."

mapfile -t files < <(git ls-files '*.sh' '*.bash' '*.bats')
if [ "${#files[@]}" -eq 0 ]; then
  exit 0
fi
shellcheck -x "${files[@]}"
