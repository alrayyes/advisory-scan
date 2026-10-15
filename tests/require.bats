#!/usr/bin/env bats
# shellcheck disable=SC2154 # $scratch comes from helpers.bash
# The runner image has to carry what the scripts call. Say which tool is
# missing, rather than failing later on "command not found".

load helpers

setup() { common_setup; }
teardown() { common_teardown; }

@test "every tool present passes" {
  run require bash git
  [ "$status" -eq 0 ]
}

@test "a missing tool fails, naming it" {
  run require bash no-such-tool-here
  [ "$status" -ne 0 ]
  [[ "$output" == *"::error::"*"no-such-tool-here"* ]]
}
