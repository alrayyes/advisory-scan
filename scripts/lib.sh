# shellcheck shell=bash
# Functions shared by gate and scan mode. Sourced, never run: the
# entrypoint is advisory-scan.sh.

# One alternative per advisory database. Each ID has to start at a word
# boundary, so the GO-2024-1234 inside ALGO-2024-1234 isn't read as one.
ADVISORY_ID_PATTERN='GHSA(-[0-9a-zA-Z]{4}){3}|CVE-[0-9]{4}-[0-9]{4,}|PKSA(-[0-9a-zA-Z]{4}){3}|GO-[0-9]{4}-[0-9]{4,}|PYSEC-[0-9]{4}-[0-9]+|RUSTSEC-[0-9]{4}-[0-9]{4,}'

# extract_ids < output: prints every advisory ID in the text, sorted and
# deduplicated, one per line. Prints nothing (and succeeds) if there are
# none. Colour escapes are stripped first, so a bold ID still counts.
extract_ids() {
  local esc
  esc=$(printf '\033')
  sed "s/${esc}\[[0-9;]*[A-Za-z]//g" |
    grep -oE "(^|[^A-Za-z0-9])(${ADVISORY_ID_PATTERN})" |
    sed -E 's/^[^A-Za-z0-9]//' |
    sort -u || true
}

# introduced_ids <head ids file> <base ids file>: the IDs in the first file
# that aren't in the second.
introduced_ids() {
  grep -vxF -f "$2" "$1" || true
}

# run_audit <output file>: runs $AUDIT_COMMAND in bash, in the current
# directory, and prints one word for what happened:
#
#   clean     the command exited 0
#   findings  it failed and its output names at least one advisory
#   error     every attempt failed without naming one, or timed out
#
# Only a failure that names nothing is retried: a real finding fails every
# attempt the same way, so retrying it only costs time. A timed-out attempt
# counts as naming nothing, whatever it printed before it was stopped. The
# command's output goes to stderr as it is, so it shows in the job log, and
# the last attempt's output is left in the file.
run_audit() {
  local out=$1
  local attempts=${AUDIT_ATTEMPTS:-3}
  local seconds=${AUDIT_TIMEOUT:-300}
  local delay=${RETRY_DELAY:-10}
  local attempt status

  for ((attempt = 1; attempt <= attempts; attempt++)); do
    status=0
    timeout "$seconds" bash -o pipefail -c "$AUDIT_COMMAND" >"$out" 2>&1 || status=$?
    cat "$out" >&2

    if [ "$status" -eq 0 ]; then
      echo clean
      return 0
    fi
    if [ "$status" -ne 124 ] && [ -n "$(extract_ids <"$out")" ]; then
      echo findings
      return 0
    fi

    if [ "$status" -eq 124 ]; then
      echo "Audit attempt $attempt/$attempts timed out after ${seconds}s." >&2
    else
      echo "Audit attempt $attempt/$attempts exited $status without naming an advisory." >&2
    fi
    if [ "$attempt" -lt "$attempts" ]; then
      sleep "$delay"
    fi
  done
  echo error
}

# run_setup: runs $SETUP_COMMAND in bash, in the current directory, if
# there is one. Not retried: an install that flakes is the caller's to
# make robust, and a broken one should fail loudly.
run_setup() {
  if [ -n "${SETUP_COMMAND:-}" ]; then
    bash -o pipefail -c "$SETUP_COMMAND"
  fi
}

# join_ids < ids: one line, space-separated.
join_ids() {
  paste -sd ' ' - || true
}

# set_output <name> <value>: a step output, when the runner provides the
# file for one.
set_output() {
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    printf '%s=%s\n' "$1" "$2" >>"$GITHUB_OUTPUT"
  fi
}

# summary < markdown: appends to the job summary, when there is one.
summary() {
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    cat >>"$GITHUB_STEP_SUMMARY"
  else
    cat >/dev/null
  fi
}

die() {
  echo "::error::$*"
  exit 1
}

# require <tool>...: fails naming every tool the runner image lacks.
require() {
  local tool missing=()
  for tool in "$@"; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    die "This runner lacks ${missing[*]}. See the README's 'Runner requirements'."
  fi
}
