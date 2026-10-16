#!/usr/bin/env bats
# shellcheck disable=SC2089,SC2090,SC2154 # commands are strings on purpose; $scratch comes from helpers.bash; AUDITS from lib.sh
# Several audit commands, one per ecosystem: each gets its own attempts,
# timeout and verdict, and one that errors makes the whole run an error,
# however many IDs the others printed (#8).
# run_audits <prefix> prints clean|findings|error and writes <prefix>.out
# (every command's output) and <prefix>.ids (IDs from the ones that found
# something).

bats_require_minimum_version 1.5.0

load helpers

FINDING_A="echo 'braces - GHSA-vfj7-8cjw-p6xm'; exit 1"
FINDING_B="echo 'Vulnerability #1: GO-2024-2687'; exit 1"
ERROR="echo 'error: OSV down'; exit 1"
CLEAN="echo 'No vulnerabilities found'"
# govulncheck prints IDs for unreached code and exits 0: still clean.
CLEAN_WITH_ID="echo 'informational: GO-2024-9999'"

setup() {
  common_setup
  unset AUDIT_COMMAND AUDIT_COMMANDS
  counter="$scratch/attempts"
  : >"$counter"
}
teardown() { common_teardown; }

audits() {
  AUDIT_COMMANDS="$(printf '%s\n' "$@")"
  export AUDIT_COMMANDS
  run --separate-stderr run_audits "$scratch/run"
}

@test "a finding and an error is an error, not findings" {
  audits "$FINDING_A" "echo run >>'$counter'; $ERROR"
  [ "$output" = error ]
  [ "$(wc -l <"$counter")" -eq 3 ]
  [[ "$stderr" == *"OSV down"* ]]
}

@test "an error and a finding is an error, whichever comes first" {
  audits "$ERROR" "$FINDING_A"
  [ "$output" = error ]
}

@test "a finding and a clean audit is findings, with only the finding's IDs" {
  audits "$FINDING_A" "$CLEAN_WITH_ID"
  [ "$output" = findings ]
  [ "$(cat "$scratch/run.ids")" = GHSA-vfj7-8cjw-p6xm ]
}

@test "two clean audits are clean" {
  audits "$CLEAN" "$CLEAN_WITH_ID"
  [ "$output" = clean ]
  [ ! -s "$scratch/run.ids" ]
}

@test "a lone error is an error" {
  audits "$ERROR"
  [ "$output" = error ]
}

@test "two findings union their IDs" {
  audits "$FINDING_A" "$FINDING_B"
  [ "$output" = findings ]
  [ "$(cat "$scratch/run.ids")" = "$(printf 'GHSA-vfj7-8cjw-p6xm\nGO-2024-2687')" ]
}

@test "the output names each command above its own output" {
  audits "$FINDING_A" "$FINDING_B"
  grep -qxF "\$ $FINDING_A" "$scratch/run.out"
  grep -qxF "\$ $FINDING_B" "$scratch/run.out"
  grep -q GO-2024-2687 "$scratch/run.out"
}

@test "command and commands together run the command first, then each line" {
  AUDIT_COMMAND="$FINDING_A"
  AUDIT_COMMANDS="$(printf '\n%s\n\n' "$FINDING_B")"
  export AUDIT_COMMAND AUDIT_COMMANDS
  load_audits
  [ "${#AUDITS[@]}" -eq 2 ]
  [ "${AUDITS[0]}" = "$FINDING_A" ]
  [ "${AUDITS[1]}" = "$FINDING_B" ]
}

@test "a single command still runs as one, however many lines it has" {
  AUDIT_COMMAND="$(printf 'status=0\necho GHSA-vfj7-8cjw-p6xm\nexit 1')"
  export AUDIT_COMMAND
  load_audits
  [ "${#AUDITS[@]}" -eq 1 ]
  run --separate-stderr run_audits "$scratch/run"
  [ "$output" = findings ]
}

@test "neither command nor commands is nothing to run" {
  load_audits
  [ "${#AUDITS[@]}" -eq 0 ]
}
