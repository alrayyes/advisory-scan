#!/usr/bin/env bats
# What scan mode does to the ticket, from the audit's result and the open
# ticket's recorded IDs. decide <status> <issue number> <recorded> <current>

load helpers

setup() {
  common_setup
  # shellcheck source=../scripts/scan.sh
  source "$REPO_ROOT/scripts/scan.sh"
}
teardown() { common_teardown; }

@test "findings and no ticket: create" {
  [ "$(decide findings "" "" "GHSA-aaaa-bbbb-cccc")" = create ]
}

@test "findings, a ticket with the same IDs: leave it" {
  [ "$(decide findings 7 "GHSA-aaaa-bbbb-cccc CVE-2024-0001" "CVE-2024-0001 GHSA-aaaa-bbbb-cccc")" = leave ]
}

@test "findings, a ticket with different IDs: update" {
  [ "$(decide findings 7 "GHSA-aaaa-bbbb-cccc" "GHSA-aaaa-bbbb-cccc CVE-2024-0001")" = update ]
}

@test "clean and a ticket: close" {
  [ "$(decide clean 7 "GHSA-aaaa-bbbb-cccc" "")" = close ]
}

@test "clean and no ticket: leave" {
  [ "$(decide clean "" "" "")" = leave ]
}

@test "an audit error fails, ticket or not, and never touches it" {
  [ "$(decide error 7 "GHSA-aaaa-bbbb-cccc" "")" = fail ]
  [ "$(decide error "" "" "")" = fail ]
}
