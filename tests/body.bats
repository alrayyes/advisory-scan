#!/usr/bin/env bats
# shellcheck disable=SC2016,SC2154 # backticks are literal Markdown here; $scratch comes from helpers.bash
# The ticket body, the IDs it records, and which forge's API to talk to.

load helpers

setup() {
  common_setup
  # shellcheck source=../scripts/scan.sh
  source "$REPO_ROOT/scripts/scan.sh"
  export GITHUB_SERVER_URL=https://github.com GITHUB_REPOSITORY=o/r
  export GITHUB_RUN_ID=111 GITHUB_RUN_NUMBER=7 GITHUB_SHA=abc1234def
  export AUDIT_COMMAND="bun audit"
  export GITHUB_API_URL=https://api.github.com
}
teardown() { common_teardown; }

@test "the body lists the sorted IDs, the command, the raw output, the date and the run" {
  printf 'CVE-2024-0001\nGHSA-aaaa-bbbb-cccc\n' >"$scratch/ids"
  printf 'pkg@1.0\n  high: bad - GHSA-aaaa-bbbb-cccc\n' >"$scratch/out"
  run render_body "$scratch/ids" "$scratch/out"
  [ "$status" -eq 0 ]
  [[ "$output" == *"<!-- advisory-scan ids: CVE-2024-0001 GHSA-aaaa-bbbb-cccc -->"* ]]
  [[ "$output" == *"- [CVE-2024-0001](https://osv.dev/vulnerability/CVE-2024-0001)"* ]]
  [[ "$output" == *"- [GHSA-aaaa-bbbb-cccc](https://osv.dev/vulnerability/GHSA-aaaa-bbbb-cccc)"* ]]
  [[ "$output" == *'`bun audit`'* ]]
  [[ "$output" == *"high: bad - GHSA-aaaa-bbbb-cccc"* ]]
  [[ "$output" == *"$(date -u +%Y-%m-%d)"* ]]
  [[ "$output" == *"https://github.com/o/r/actions/runs/111"* ]]
}

@test "a PKSA ID has no OSV page, so it isn't linked" {
  printf 'PKSA-6m4y-ry9q-hhvc\n' >"$scratch/ids"
  : >"$scratch/out"
  run render_body "$scratch/ids" "$scratch/out"
  [[ "$output" == *$'\n- PKSA-6m4y-ry9q-hhvc\n'* ]]
}

@test "backticks in the output can't close the code fence" {
  printf 'GHSA-aaaa-bbbb-cccc\n' >"$scratch/ids"
  printf '```\nGHSA-aaaa-bbbb-cccc\n```\n' >"$scratch/out"
  run render_body "$scratch/ids" "$scratch/out"
  [[ "$output" == *$'\n~~~~~~text\n```\nGHSA-aaaa-bbbb-cccc\n```\n~~~~~~'* ]]
}

@test "a run of tildes in the output can't close the fence, whatever its length" {
  printf 'GHSA-aaaa-bbbb-cccc\n' >"$scratch/ids"
  for run in 3 6 10; do
    {
      echo GHSA-aaaa-bbbb-cccc
      printf '%*s\n' "$run" '' | tr ' ' '~'
      echo '   ~~~~~~~~~~~~ indented'
      echo '@alrayyes see #1 <img src=x>'
    } >"$scratch/out"
    run render_body "$scratch/ids" "$scratch/out"
    # The longest run is 12 (the indented line); the fence is 13.
    fence='~~~~~~~~~~~~~'
    [[ "$output" == *$'\n'"${fence}text"$'\n'* ]]
    [[ "$output" == *"@alrayyes see #1 <img src=x>"$'\n'"${fence}" ]]
  done
}

@test "a short fence stays six tildes" {
  printf 'GHSA-aaaa-bbbb-cccc\n' >"$scratch/ids"
  printf 'plain output\n' >"$scratch/out"
  run render_body "$scratch/ids" "$scratch/out"
  [[ "$output" == *$'\n~~~~~~text\nplain output\n~~~~~~' ]]
}

@test "a long ID list leaves less room for the output, and the body still fits" {
  for i in $(seq 1000 1499); do printf 'GHSA-%04d-bbbb-cccc\n' "$i"; done >"$scratch/ids"
  head -c 200000 /dev/zero | tr '\0' 'x' >"$scratch/out"
  run render_body "$scratch/ids" "$scratch/out"
  [ "${#output}" -lt 65536 ]
  [[ "$output" == *"Output cut"* ]]
}

@test "one huge tilde line still leaves the body, fences included, under the limit" {
  printf 'GHSA-aaaa-bbbb-cccc\n' >"$scratch/ids"
  { echo GHSA-aaaa-bbbb-cccc; head -c 70000 /dev/zero | tr '\0' '~'; echo; } >"$scratch/out"
  run render_body "$scratch/ids" "$scratch/out"
  [ "${#output}" -lt 65536 ]
  [[ "$output" == *"Output cut"* ]]
}

@test "very long output is cut to fit an issue body" {
  printf 'GHSA-aaaa-bbbb-cccc\n' >"$scratch/ids"
  head -c 200000 /dev/zero | tr '\0' 'x' >"$scratch/out"
  run render_body "$scratch/ids" "$scratch/out"
  [ "${#output}" -lt 65536 ]
  [[ "$output" == *"Output cut"* ]]
}

@test "recorded_ids reads the marker, not IDs elsewhere in the body" {
  body=$'<!-- advisory-scan ids: CVE-2024-0001 GHSA-aaaa-bbbb-cccc -->\nGHSA-zzzz-zzzz-zzzz in the output'
  run recorded_ids <<<"$body"
  [ "$output" = "CVE-2024-0001 GHSA-aaaa-bbbb-cccc" ]
}

@test "recorded_ids of a body without the marker is empty" {
  run recorded_ids <<<"someone rewrote this"
  [ -z "$output" ]
}

@test "GitHub is the default forge" {
  [ "$(detect_forge)" = github ]
}

@test "an API URL ending in /api/v1 is Forgejo" {
  GITHUB_API_URL=https://git.example.org/api/v1
  [ "$(detect_forge)" = forgejo ]
}

@test "Forgejo's runner flag is Forgejo, whatever the URL" {
  FORGEJO_ACTIONS=true
  export FORGEJO_ACTIONS
  [ "$(detect_forge)" = forgejo ]
}

@test "the run link uses the run ID on GitHub and the run number on Forgejo" {
  [ "$(run_url)" = "https://github.com/o/r/actions/runs/111" ]
  GITHUB_API_URL=https://git.example.org/api/v1
  GITHUB_SERVER_URL=https://git.example.org
  [ "$(run_url)" = "https://git.example.org/o/r/actions/runs/7" ]
}
