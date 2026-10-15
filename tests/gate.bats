#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2089,SC2090,SC2154 # bats runs each test in a subshell; $scratch comes from helpers.bash; commands are strings on purpose
# Gate mode, end to end through the entrypoint: a real git repository with a
# base and a head commit, each carrying its own "lockfile" of advisories.
# The fake audit prints the lockfile and fails when it isn't empty, or
# fails with a registry-style error when the lockfile says "error".

load helpers

setup() {
  common_setup
  export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
  export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
  calls="$scratch/calls"
  : >"$calls"
  export CALLS="$calls"
  export ADVISORY_MODE=gate
  export AUDIT_COMMAND="sh ./audit.sh"
  export SETUP_COMMAND=""
  export WORKING_DIRECTORY="."
  export GITHUB_OUTPUT="$scratch/github_output"
  : >"$GITHUB_OUTPUT"
  unset GITHUB_STEP_SUMMARY
}
teardown() { common_teardown; }

# commit <dir> <lockfile content> <message>
commit() {
  local dir=$1 content=$2
  mkdir -p "$origin/$dir"
  cat >"$origin/$dir/audit.sh" <<'SH'
echo "$PWD" >>"$CALLS"
case "$(cat advisories)" in
  "") echo "No vulnerabilities found"; exit 0 ;;
  error) echo "error: audit request failed: ConnectionClosed"; exit 1 ;;
  *) cat advisories; exit 1 ;;
esac
SH
  printf '%s' "$content" >"$origin/$dir/advisories"
  git -C "$origin" add -A
  git -C "$origin" commit -q --allow-empty -m "$3"
  git -C "$origin" rev-parse HEAD
}

# repo <base lockfile> <head lockfile> [dir] [checkout path]: builds origin,
# clones the head into $GITHUB_WORKSPACE (or a path under it, like
# actions/checkout's `path:`) with depth 1 so the base commit isn't local.
repo() {
  local dir=${3:-.} into=${4:-}
  origin="$scratch/origin"
  git init -q -b main "$origin"
  BASE_SHA="$(commit "$dir" "$1" base)"
  commit "$dir" "$2" head >/dev/null
  export BASE_SHA
  GITHUB_WORKSPACE="$scratch/work"
  git clone -q --depth 1 "file://$origin" "$GITHUB_WORKSPACE${into:+/$into}"
  export GITHUB_WORKSPACE
}

audits_run() { wc -l <"$calls" | tr -d ' '; }

@test "an advisory the head introduces fails the gate, naming only that one" {
  repo "GHSA-aaaa-bbbb-cccc" "$(printf 'GHSA-aaaa-bbbb-cccc\nGHSA-dddd-eeee-ffff')"
  run "$REPO_ROOT/scripts/advisory-scan.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::"*"GHSA-dddd-eeee-ffff"* ]]
  grep -qx "introduced=GHSA-dddd-eeee-ffff" "$GITHUB_OUTPUT"
}

@test "advisories already on the base pass, and are named as pre-existing" {
  repo "GHSA-aaaa-bbbb-cccc" "GHSA-aaaa-bbbb-cccc"
  run "$REPO_ROOT/scripts/advisory-scan.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"GHSA-aaaa-bbbb-cccc"* ]]
  [[ "$output" != *"::error::"* ]]
  grep -qx "introduced=" "$GITHUB_OUTPUT"
  grep -qx "advisories=GHSA-aaaa-bbbb-cccc" "$GITHUB_OUTPUT"
}

@test "a pull request that fixes an advisory passes" {
  repo "GHSA-aaaa-bbbb-cccc" ""
  run "$REPO_ROOT/scripts/advisory-scan.sh"
  [ "$status" -eq 0 ]
}

@test "a clean head passes without auditing the base" {
  repo "GHSA-aaaa-bbbb-cccc" ""
  run "$REPO_ROOT/scripts/advisory-scan.sh"
  [ "$status" -eq 0 ]
  [ "$(audits_run)" -eq 1 ]
}

@test "a head audit that errors without an advisory fails, after three attempts" {
  repo "" "error"
  run "$REPO_ROOT/scripts/advisory-scan.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"::error::"*"no advisory ID"* ]]
  [ "$(audits_run)" -eq 3 ]
}

@test "a base audit that errors fails the gate rather than guessing" {
  repo "error" "GHSA-aaaa-bbbb-cccc"
  run "$REPO_ROOT/scripts/advisory-scan.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"::error::"*"base"* ]]
}

@test "the base is fetched when the checkout is shallow, and audited in its own tree" {
  repo "GHSA-aaaa-bbbb-cccc" "GHSA-aaaa-bbbb-cccc"
  run "$REPO_ROOT/scripts/advisory-scan.sh"
  [ "$status" -eq 0 ]
  [ "$(audits_run)" -eq 2 ]
  [ "$(sed -n 1p "$calls")" != "$(sed -n 2p "$calls")" ]
}

@test "working-directory and setup apply to the head and the base" {
  repo "GHSA-aaaa-bbbb-cccc" "GHSA-aaaa-bbbb-cccc" sub/dir
  export WORKING_DIRECTORY=sub/dir
  export SETUP_COMMAND="touch setup-ran"
  export AUDIT_COMMAND="test -f setup-ran && sh ./audit.sh"
  run "$REPO_ROOT/scripts/advisory-scan.sh"
  [ "$status" -eq 0 ]
  [ "$(audits_run)" -eq 2 ]
  grep -q "/sub/dir$" "$calls"
}

@test "a checkout under a path: in the workspace finds the same directory on the base" {
  repo "GHSA-aaaa-bbbb-cccc" "GHSA-aaaa-bbbb-cccc" sub repo
  export WORKING_DIRECTORY=repo/sub
  run "$REPO_ROOT/scripts/advisory-scan.sh"
  [ "$status" -eq 0 ]
  [ "$(audits_run)" -eq 2 ]
  [ "$(grep -c '/sub$' "$calls")" -eq 2 ]
}

@test "gate mode never passes the token to setup or the audit" {
  repo "GHSA-aaaa-bbbb-cccc" "GHSA-aaaa-bbbb-cccc"
  export ADVISORY_TOKEN=s3cret API_TOKEN=caller __advisory_scan_token=caller
  export SETUP_COMMAND="env >>'$scratch/env'"
  export AUDIT_COMMAND="env >>'$scratch/env'; sh ./audit.sh"
  run "$REPO_ROOT/scripts/advisory-scan.sh"
  [ "$status" -eq 0 ]
  [ -s "$scratch/env" ]
  [ "$(grep -c s3cret "$scratch/env")" -eq 0 ]
}

@test "a failing setup fails the step" {
  repo "" "GHSA-aaaa-bbbb-cccc"
  export SETUP_COMMAND="exit 3"
  run "$REPO_ROOT/scripts/advisory-scan.sh"
  [ "$status" -ne 0 ]
  [ "$(audits_run)" -eq 0 ]
}

@test "gate mode with findings and no base commit fails with a reason" {
  repo "" "GHSA-aaaa-bbbb-cccc"
  export BASE_SHA=""
  run "$REPO_ROOT/scripts/advisory-scan.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"::error::"*"base-sha"* ]]
}

@test "the all-zero 'before' of a new branch's first push counts as no base" {
  repo "" "GHSA-aaaa-bbbb-cccc"
  export BASE_SHA=0000000000000000000000000000000000000000
  run "$REPO_ROOT/scripts/advisory-scan.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"::error::"*"base-sha"* ]]
}

@test "an unknown mode is refused" {
  repo "" ""
  export ADVISORY_MODE=audit
  run "$REPO_ROOT/scripts/advisory-scan.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"::error::"*"mode"* ]]
}

@test "an empty command is refused" {
  repo "" ""
  export AUDIT_COMMAND=""
  run "$REPO_ROOT/scripts/advisory-scan.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"::error::"*"command"* ]]
}
