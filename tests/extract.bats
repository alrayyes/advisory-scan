#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2089,SC2090,SC2154 # bats runs each test in a subshell; $scratch comes from helpers.bash; commands are strings on purpose
# Advisory IDs come out of the audit tool's raw output, whatever the tool.

load helpers

setup() { common_setup; }
teardown() { common_teardown; }

@test "bun audit: GHSA IDs, sorted and deduplicated" {
  run extract_ids <"$FIXTURES/bun-audit.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'GHSA-7w5x-hrqm-74c2\nGHSA-r4xh-jqrq-34v2\nGHSA-vfj7-8cjw-p6xm')" ]
}

@test "composer audit: the PKSA, CVE and GHSA of one advisory" {
  run extract_ids <"$FIXTURES/composer-audit.txt"
  [ "$output" = "$(printf 'CVE-2023-29197\nGHSA-wxmh-65f7-jcvw\nPKSA-6m4y-ry9q-hhvc')" ]
}

@test "govulncheck: GO IDs" {
  run extract_ids <"$FIXTURES/govulncheck.txt"
  [ "$output" = "GO-2024-2687" ]
}

@test "pip-audit: PYSEC and GHSA IDs" {
  run extract_ids <"$FIXTURES/pip-audit.txt"
  [ "$output" = "$(printf 'GHSA-h75v-3vvj-5mfj\nPYSEC-2024-1')" ]
}

@test "cargo audit: RUSTSEC IDs" {
  run extract_ids <"$FIXTURES/cargo-audit.txt"
  [ "$output" = "RUSTSEC-2023-0071" ]
}

@test "colour codes around an ID don't hide it" {
  run extract_ids < <(printf '\033[1mGHSA-vfj7-8cjw-p6xm\033[0m\n')
  [ "$output" = "GHSA-vfj7-8cjw-p6xm" ]
}

@test "an ID-shaped tail of a longer word isn't an ID" {
  run extract_ids <<<"ALGO-2024-1234 MYCVE-2024-12345"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "output with no advisory gives nothing, and succeeds" {
  run extract_ids <"$FIXTURES/registry-error.txt"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
