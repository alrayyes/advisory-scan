#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2089,SC2090,SC2154 # bats runs each test in a subshell; $scratch comes from helpers.bash; commands are strings on purpose
# What the head has that the base doesn't.

load helpers

setup() { common_setup; }
teardown() { common_teardown; }

@test "an ID only the head has is introduced" {
  printf 'GHSA-aaaa-bbbb-cccc\nGHSA-dddd-eeee-ffff\n' >"$scratch/head"
  printf 'GHSA-aaaa-bbbb-cccc\n' >"$scratch/base"
  run introduced_ids "$scratch/head" "$scratch/base"
  [ "$output" = "GHSA-dddd-eeee-ffff" ]
}

@test "the same IDs on both sides introduce nothing" {
  printf 'GHSA-aaaa-bbbb-cccc\n' >"$scratch/head"
  printf 'GHSA-aaaa-bbbb-cccc\n' >"$scratch/base"
  run introduced_ids "$scratch/head" "$scratch/base"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a fix (fewer IDs on the head) introduces nothing" {
  : >"$scratch/head"
  printf 'GHSA-aaaa-bbbb-cccc\n' >"$scratch/base"
  run introduced_ids "$scratch/head" "$scratch/base"
  [ -z "$output" ]
}

@test "against a clean base, every head ID is introduced" {
  printf 'CVE-2024-0001\nGO-2024-0002\n' >"$scratch/head"
  : >"$scratch/base"
  run introduced_ids "$scratch/head" "$scratch/base"
  [ "$output" = "$(printf 'CVE-2024-0001\nGO-2024-0002')" ]
}
