#!/usr/bin/env bats
# shellcheck disable=SC2089,SC2090,SC2154 # commands are strings on purpose; $scratch and $stderr come from helpers.bash and bats
# actions/setup-go registers a problem matcher (owner "go") that turns any
# log line shaped like file.go:line:col: message into an annotation, and
# ::stop-commands:: doesn't switch matchers off. govulncheck's call traces
# have that shape, so a passing gate showed failure annotations (#9).
#
# runner_annotations < log: a stand-in for the runner. It starts with
# setup-go's matcher registered, honours ::remove-matcher owner=go:: and
# counts the lines the matcher's own regex would annotate.

bats_require_minimum_version 1.5.0

load helpers

setup() { common_setup; }
teardown() { common_teardown; }

# setup-go's regexp, from its matchers.json at the SHA the examples pin.
GO_MATCHER='^\s*(.+\.go):(?:(\d+):(\d+):)? (.*)'

runner_annotations() {
  python3 -c '
import re, sys
matcher = re.compile(sys.argv[1])
active, count = True, 0
for line in sys.stdin.read().splitlines():
    if line.strip() == "::remove-matcher owner=go::":
        active = False
    elif active and matcher.match(line):
        count += 1
print(count)
' "$GO_MATCHER"
}

TRACE="echo 'Vulnerability #1: GO-2024-2687'; echo '  #1: internal/forgejo/forgejo.go:93:21: forgejo.Client.SetArchived calls fmt.Sprintf'; exit 1"

@test "govulncheck's call traces don't become annotations" {
  AUDIT_COMMAND="$TRACE"
  export AUDIT_COMMAND
  run --separate-stderr run_audit "$scratch/out"
  [ "$output" = findings ]
  [ "$(runner_annotations <<<"$stderr")" -eq 0 ]
  # The trace is still in the log, for a person to read.
  [[ "$stderr" == *"forgejo.go:93:21"* ]]
}

@test "the matcher is removed before the output, outside the stop-commands block" {
  AUDIT_COMMAND="$TRACE"
  export AUDIT_COMMAND
  run --separate-stderr run_audit "$scratch/out"
  mapfile -t lines <<<"$stderr"
  [ "${lines[0]}" = "::remove-matcher owner=go::" ]
  [[ "${lines[1]}" == "::stop-commands::"* ]]
}

@test "output with nothing for the matcher is unchanged apart from that line" {
  AUDIT_COMMAND="echo 'No vulnerabilities found'"
  export AUDIT_COMMAND
  run --separate-stderr run_audit "$scratch/out"
  [ "$output" = clean ]
  [ "$(grep -vc '^::' <<<"$stderr")" -eq 1 ]
  [[ "$stderr" == *"No vulnerabilities found"* ]]
}
