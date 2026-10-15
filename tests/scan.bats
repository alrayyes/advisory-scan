#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2154 # bats runs each test in a subshell; $scratch comes from helpers.bash
# Scan mode end to end through the entrypoint, against a fake issues API
# (fake_forge.py) that records every request. The audit is a stand-in
# that prints $scratch/findings and fails when it isn't empty, or fails
# like a registry outage when it says "error".

load helpers

setup() {
  common_setup
  state="$scratch/state.json"
  requests="$scratch/requests.jsonl"
  : >"$requests"
  echo '{"issues": []}' >"$state"
  : >"$scratch/findings"

  export ADVISORY_MODE=scan
  export AUDIT_COMMAND="f=\$(cat '$scratch/findings'); case \"\$f\" in '') echo 'No vulnerabilities found';; error) echo 'error: audit request failed'; exit 1;; *) echo \"\$f\"; exit 1;; esac"
  export SETUP_COMMAND="" WORKING_DIRECTORY="."
  export GITHUB_WORKSPACE="$scratch"
  export ADVISORY_TOKEN=s3cret ISSUE_TITLE="Dependency advisories" ISSUE_LABELS=""
  export GITHUB_REPOSITORY=o/r GITHUB_RUN_ID=111 GITHUB_RUN_NUMBER=7 GITHUB_SHA=abc1234def
  export GITHUB_OUTPUT="$scratch/github_output"
  : >"$GITHUB_OUTPUT"
  unset GITHUB_STEP_SUMMARY FORGEJO_ACTIONS GITEA_ACTIONS
}

teardown() {
  [ -n "${server_pid:-}" ] && kill "$server_pid" 2>/dev/null
  common_teardown
}

# start_forge github|forgejo: the fake API, and the variables each forge's
# runner sets.
start_forge() {
  python3 "$BATS_TEST_DIRNAME/fake_forge.py" "$state" "$requests" "$scratch/port" &
  server_pid=$!
  for _ in $(seq 50); do [ -s "$scratch/port" ] && break; sleep 0.1; done
  local base
  base="http://127.0.0.1:$(cat "$scratch/port")"
  if [ "$1" = forgejo ]; then
    export GITHUB_API_URL="$base/api/v1" GITHUB_SERVER_URL="$base"
  else
    export GITHUB_API_URL="$base" GITHUB_SERVER_URL="https://github.com"
  fi
}

# seed_issue <number> <title> <ids...>: an open ticket as the action would
# have written it.
seed_issue() {
  local number=$1 title=$2
  shift 2
  jq --argjson n "$number" --arg t "$title" --arg ids "$*" \
    '.issues += [{number: $n, title: $t, state: "open", labels: [], comments: [],
      body: ("<!-- advisory-scan ids: " + $ids + " -->\nold body")}]' \
    "$state" >"$state.tmp" && mv "$state.tmp" "$state"
}

writes() { jq -c 'select(.method != "GET")' "$requests"; }
issue() { jq ".issues[] | select(.number == $1)" "$state"; }

@test "GitHub: findings and no ticket create one, labelled, with the IDs and the run" {
  start_forge github
  export ISSUE_LABELS="dependencies, security"
  printf 'GHSA-dddd-eeee-ffff\nGHSA-aaaa-bbbb-cccc\n' >"$scratch/findings"
  run "$REPO_ROOT/scripts/advisory-scan.sh"
  [ "$status" -eq 0 ]

  [ "$(writes | jq -r '"\(.method) \(.path)"' | paste -sd ,)" = "POST /repos/o/r/issues,POST /repos/o/r/issues/1/labels" ]
  [ "$(jq -r 'select(.method == "POST") | .auth' "$requests" | sort -u)" = "Bearer s3cret" ]
  created="$(jq -c 'select(.method == "POST" and .path == "/repos/o/r/issues") | .body' "$requests")"
  [ "$(jq -r .title <<<"$created")" = "Dependency advisories" ]
  [ "$(jq -r 'keys | join(",")' <<<"$created")" = "body,title" ]
  body="$(jq -r .body <<<"$created")"
  [[ "$body" == *"<!-- advisory-scan ids: GHSA-aaaa-bbbb-cccc GHSA-dddd-eeee-ffff -->"* ]]
  [[ "$body" == *"https://github.com/o/r/actions/runs/111"* ]]
  [ "$(issue 1 | jq -c .labels)" = '["dependencies","security"]' ]
  grep -qx "issue=1" "$GITHUB_OUTPUT"
}

@test "GitHub: the same IDs as the open ticket make no write" {
  seed_issue 4 "Dependency advisories" GHSA-aaaa-bbbb-cccc
  start_forge github
  printf 'GHSA-aaaa-bbbb-cccc\n' >"$scratch/findings"
  run "$REPO_ROOT/scripts/advisory-scan.sh"
  [ "$status" -eq 0 ]
  [ -z "$(writes)" ]
  grep -qx "issue=4" "$GITHUB_OUTPUT"
}

@test "GitHub: a changed set of IDs updates the body and nothing else" {
  seed_issue 4 "Dependency advisories" GHSA-aaaa-bbbb-cccc
  start_forge github
  printf 'GHSA-aaaa-bbbb-cccc\nCVE-2024-0001\n' >"$scratch/findings"
  run "$REPO_ROOT/scripts/advisory-scan.sh"
  [ "$status" -eq 0 ]
  [ "$(writes | jq -r '"\(.method) \(.path) \(.body | keys | join(","))"')" = "PATCH /repos/o/r/issues/4 body" ]
  [[ "$(issue 4 | jq -r .body)" == *"ids: CVE-2024-0001 GHSA-aaaa-bbbb-cccc -->"* ]]
}

@test "GitHub: a clean audit comments on the ticket and closes it as completed" {
  seed_issue 4 "Dependency advisories" GHSA-aaaa-bbbb-cccc
  start_forge github
  run "$REPO_ROOT/scripts/advisory-scan.sh"
  [ "$status" -eq 0 ]
  [ "$(writes | jq -r '"\(.method) \(.path)"' | paste -sd ,)" = "POST /repos/o/r/issues/4/comments,PATCH /repos/o/r/issues/4" ]
  [ "$(writes | jq -c 'select(.method == "PATCH") | .body')" = '{"state":"closed","state_reason":"completed"}' ]
  [[ "$(issue 4 | jq -r '.comments[0]')" == *"clean"*"abc1234"* ]]
}

@test "GitHub: a clean audit and no ticket make no write" {
  start_forge github
  run "$REPO_ROOT/scripts/advisory-scan.sh"
  [ "$status" -eq 0 ]
  [ -z "$(writes)" ]
}

@test "an audit error fails and makes no API call at all" {
  seed_issue 4 "Dependency advisories" GHSA-aaaa-bbbb-cccc
  start_forge github
  echo error >"$scratch/findings"
  run "$REPO_ROOT/scripts/advisory-scan.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"::error::"* ]]
  [ ! -s "$requests" ]
  [ "$(issue 4 | jq -r .state)" = open ]
}

@test "GitHub: the search skips pull requests and pages past the first 100" {
  jq '.issues = [range(1; 131) | {number: ., title: "other", state: "open", body: "", labels: [], comments: []}]
      | .issues += [{number: 200, title: "Dependency advisories", state: "open", body: "", labels: [], comments: [], pull_request: {}}]' \
    "$state" >"$state.tmp" && mv "$state.tmp" "$state"
  seed_issue 201 "Dependency advisories" GHSA-aaaa-bbbb-cccc
  start_forge github
  printf 'GHSA-aaaa-bbbb-cccc\n' >"$scratch/findings"
  run "$REPO_ROOT/scripts/advisory-scan.sh"
  [ "$status" -eq 0 ]
  [ -z "$(writes)" ]
  grep -qx "issue=201" "$GITHUB_OUTPUT"
  [ "$(jq -r 'select(.method == "GET") | .query.per_page' "$requests" | sort -u)" = 100 ]
}

@test "Forgejo: create uses the /api/v1 paths, a token header and the run number" {
  start_forge forgejo
  export ISSUE_LABELS="dependencies"
  printf 'GHSA-aaaa-bbbb-cccc\n' >"$scratch/findings"
  run "$REPO_ROOT/scripts/advisory-scan.sh"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.prefix' "$requests" | sort -u)" = true ]
  [ "$(jq -r '.auth' "$requests" | sort -u)" = "token s3cret" ]
  [ "$(jq -r 'select(.method == "GET") | "\(.query.type) \(.query.limit) \(.query.state)"' "$requests" | sort -u)" = "issues 50 open" ]
  [[ "$(issue 1 | jq -r .body)" == *"/o/r/actions/runs/7"* ]]
  [ "$(writes | jq -c 'select(.path == "/repos/o/r/issues/1/labels") | .body')" = '{"labels":["dependencies"]}' ]
}

@test "Forgejo: close sends state only, no state_reason" {
  seed_issue 4 "Dependency advisories" GHSA-aaaa-bbbb-cccc
  start_forge forgejo
  run "$REPO_ROOT/scripts/advisory-scan.sh"
  [ "$status" -eq 0 ]
  [ "$(writes | jq -c 'select(.method == "PATCH") | .body')" = '{"state":"closed"}' ]
}

@test "a custom title finds and creates its own ticket" {
  seed_issue 4 "Dependency advisories" GHSA-aaaa-bbbb-cccc
  start_forge github
  export ISSUE_TITLE="Dependency advisories (web)"
  printf 'GHSA-aaaa-bbbb-cccc\n' >"$scratch/findings"
  run "$REPO_ROOT/scripts/advisory-scan.sh"
  [ "$status" -eq 0 ]
  [ "$(issue 5 | jq -r .title)" = "Dependency advisories (web)" ]
}

@test "an API error fails the step" {
  start_forge github
  jq '.fail = {"POST /repos/o/r/issues": 403}' "$state" >"$state.tmp" && mv "$state.tmp" "$state"
  kill "$server_pid"; rm "$scratch/port"; start_forge github
  printf 'GHSA-aaaa-bbbb-cccc\n' >"$scratch/findings"
  run "$REPO_ROOT/scripts/advisory-scan.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"::error::"*"403"* ]]
}

@test "scan mode without a token is refused before the audit runs" {
  start_forge github
  export ADVISORY_TOKEN=""
  run "$REPO_ROOT/scripts/advisory-scan.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"::error::"*"token"* ]]
  [[ "$output" != *"No vulnerabilities found"* ]]
}

@test "the token never reaches setup, the audit, or the ticket" {
  start_forge github
  export SETUP_COMMAND="env >'$scratch/setup.env'"
  export AUDIT_COMMAND="env >'$scratch/audit.env'; echo \"token=\${ADVISORY_TOKEN:-}\"; echo GHSA-aaaa-bbbb-cccc; exit 1"
  run "$REPO_ROOT/scripts/advisory-scan.sh"
  [ "$status" -eq 0 ]
  [ "$(grep -c s3cret "$scratch/setup.env")" -eq 0 ]
  [ "$(grep -c s3cret "$scratch/audit.env")" -eq 0 ]
  [[ "$output" != *s3cret* ]]
  [[ "$(issue 1 | jq -r .body)" != *s3cret* ]]
  # The API calls still carried it.
  [ "$(jq -r 'select(.method == "POST") | .auth' "$requests" | sort -u)" = "Bearer s3cret" ]
}

@test "a newer duplicate ticket is closed, pointing at the oldest" {
  seed_issue 4 "Dependency advisories" GHSA-aaaa-bbbb-cccc
  seed_issue 9 "Dependency advisories" GHSA-aaaa-bbbb-cccc
  start_forge github
  printf 'GHSA-aaaa-bbbb-cccc\n' >"$scratch/findings"
  run "$REPO_ROOT/scripts/advisory-scan.sh"
  [ "$status" -eq 0 ]
  [ "$(writes | jq -r '"\(.method) \(.path)"' | paste -sd ,)" = "POST /repos/o/r/issues/9/comments,PATCH /repos/o/r/issues/9" ]
  [[ "$(issue 9 | jq -r '.comments[0]')" == *"#4"* ]]
  [ "$(issue 9 | jq -r .state)" = closed ]
  [ "$(issue 4 | jq -r .state)" = open ]
  grep -qx "issue=4" "$GITHUB_OUTPUT"
}

@test "a listing that isn't a JSON array fails instead of opening a duplicate" {
  seed_issue 4 "Dependency advisories" GHSA-aaaa-bbbb-cccc
  jq '.respond = {"GET /repos/o/r/issues": {}}' "$state" >"$state.tmp" && mv "$state.tmp" "$state"
  start_forge github
  printf 'GHSA-aaaa-bbbb-cccc\n' >"$scratch/findings"
  run "$REPO_ROOT/scripts/advisory-scan.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"::error::"* ]]
  [ -z "$(writes)" ]
}

@test "Forgejo: a server page smaller than asked for doesn't end the search early" {
  jq '.issues = [range(1; 31) | {number: ., title: "other", state: "open", body: "", labels: [], comments: []}]' \
    "$state" >"$state.tmp" && mv "$state.tmp" "$state"
  seed_issue 40 "Dependency advisories" GHSA-aaaa-bbbb-cccc
  # The fake honours limit, so ask it to behave like MAX_RESPONSE_ITEMS=20.
  jq '.max_page = 20' "$state" >"$state.tmp" && mv "$state.tmp" "$state"
  start_forge forgejo
  printf 'GHSA-aaaa-bbbb-cccc\n' >"$scratch/findings"
  run "$REPO_ROOT/scripts/advisory-scan.sh"
  [ "$status" -eq 0 ]
  [ -z "$(writes)" ]
  grep -qx "issue=40" "$GITHUB_OUTPUT"
}
