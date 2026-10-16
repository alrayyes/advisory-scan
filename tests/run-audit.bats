#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2089,SC2090,SC2154 # bats runs each test in a subshell; $scratch comes from helpers.bash; commands are strings on purpose
# The audit runs up to three times. A failure that names an advisory is a
# finding and isn't retried; one that names none (registry down, tool
# error, timeout) is retried, and is an error if every attempt fails.

bats_require_minimum_version 1.5.0

load helpers

setup() {
  common_setup
  counter="$scratch/attempts"
  : >"$counter"
}
teardown() { common_teardown; }

attempts() { wc -l <"$counter" | tr -d ' '; }

@test "a passing audit is clean after one attempt" {
  AUDIT_COMMAND="echo run >>'$counter'; echo 'No vulnerabilities found'"
  export AUDIT_COMMAND
  run --separate-stderr run_audit "$scratch/out"
  [ "$output" = "clean" ]
  [ "$(attempts)" -eq 1 ]
}

@test "a failure naming an advisory is a finding, with no retry" {
  AUDIT_COMMAND="echo run >>'$counter'; cat '$FIXTURES/bun-audit.txt'; exit 1"
  export AUDIT_COMMAND
  run --separate-stderr run_audit "$scratch/out"
  [ "$output" = "findings" ]
  [ "$(attempts)" -eq 1 ]
  grep -q GHSA-vfj7-8cjw-p6xm "$scratch/out"
}

@test "a failure naming nothing is retried, and passes if a retry does" {
  AUDIT_COMMAND="echo run >>'$counter'; [ \$(wc -l <'$counter') -ge 3 ] || { cat '$FIXTURES/registry-error.txt'; exit 1; }"
  export AUDIT_COMMAND
  run --separate-stderr run_audit "$scratch/out"
  [ "$output" = "clean" ]
  [ "$(attempts)" -eq 3 ]
}

@test "three failures naming nothing are an error" {
  AUDIT_COMMAND="echo run >>'$counter'; cat '$FIXTURES/registry-error.txt'; exit 1"
  export AUDIT_COMMAND
  run --separate-stderr run_audit "$scratch/out"
  [ "$output" = "error" ]
  [ "$(attempts)" -eq 3 ]
}

@test "an attempt that runs past the timeout is an error, even if it printed an ID" {
  AUDIT_COMMAND="echo run >>'$counter'; echo GHSA-vfj7-8cjw-p6xm; sleep 5"
  AUDIT_TIMEOUT=1
  export AUDIT_COMMAND AUDIT_TIMEOUT
  run --separate-stderr run_audit "$scratch/out"
  [ "$output" = "error" ]
  [ "$(attempts)" -eq 3 ]
}

@test "the command runs in bash, so pipes and && work" {
  AUDIT_COMMAND="echo run >>'$counter' && printf 'a\nb\n' | grep -q b"
  export AUDIT_COMMAND
  run --separate-stderr run_audit "$scratch/out"
  [ "$output" = "clean" ]
}

@test "the audit's output can't issue workflow commands" {
  AUDIT_COMMAND="echo '::error::spoofed'; echo GHSA-vfj7-8cjw-p6xm; exit 1"
  export AUDIT_COMMAND
  run --separate-stderr run_audit "$scratch/out"
  [ "$output" = "findings" ]
  mapfile -t lines <<<"$stderr"
  # lines[0] removes setup-go's problem matcher (matcher.bats).
  [[ "${lines[1]}" =~ ^::stop-commands::([0-9a-f]{12,})$ ]]
  token=${BASH_REMATCH[1]}
  [ "${lines[2]}" = "::error::spoofed" ]
  [ "${lines[4]}" = "::${token}::" ]
}

@test "each attempt stops commands with a different token" {
  AUDIT_COMMAND="echo run >>'$counter'; echo 'error: down'; exit 1"
  export AUDIT_COMMAND
  run --separate-stderr run_audit "$scratch/out"
  [ "$(grep -c '^::stop-commands::' <<<"$stderr")" -eq 3 ]
  [ "$(grep '^::stop-commands::' <<<"$stderr" | sort -u | wc -l)" -eq 3 ]
}
