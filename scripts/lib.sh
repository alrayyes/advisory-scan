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
# that aren't in the second. awk, not `grep -vxFf`: BusyBox grep matches
# everything against an empty pattern file, which would hide every ID
# against a clean base.
introduced_ids() {
  awk 'FILENAME == ARGV[1] { seen[$0] = 1; next } !seen[$0]' "$2" "$1"
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
# the last attempt's output is left in the file. The runner reads the log for
# workflow commands, so that output goes between ::stop-commands:: and a
# fresh random token: an advisory title starting with :: stays text.
run_audit() {
  local out=$1
  local attempts=${AUDIT_ATTEMPTS:-3}
  local seconds=${AUDIT_TIMEOUT:-300}
  local delay=${RETRY_DELAY:-10}
  local attempt status timed_out

  for ((attempt = 1; attempt <= attempts; attempt++)); do
    status=0
    timeout "$seconds" bash -o pipefail -c "$AUDIT_COMMAND" >"$out" 2>&1 || status=$?
    log_inert <"$out"
    # GNU timeout exits 124; BusyBox's exits 128 + the signal (SIGTERM).
    timed_out=false
    case "$status" in 124 | 143) timed_out=true ;; esac

    if [ "$status" -eq 0 ]; then
      echo clean
      return 0
    fi
    if [ "$timed_out" = false ] && [ -n "$(extract_ids <"$out")" ]; then
      echo findings
      return 0
    fi

    if [ "$timed_out" = true ]; then
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

# log_inert < text: copies text to stderr with workflow commands switched
# off for its duration. $RANDOM keeps this free of extra tools.
log_inert() {
  local token
  token="$(printf '%04x%04x%04x%04x' "$RANDOM" "$RANDOM" "$RANDOM" "$RANDOM")"
  {
    echo "::stop-commands::$token"
    # $(...) drops trailing newlines; printf puts exactly one back, so the
    # resume marker is always on a line of its own.
    printf '%s\n' "$(cat)"
    echo "::$token::"
  } >&2
}

# load_audits: fills AUDITS with the commands to run. $AUDIT_COMMAND is one
# command, whatever it contains, so a multi-line script still runs whole;
# each non-blank line of $AUDIT_COMMANDS is one more.
load_audits() {
  local line
  AUDITS=()
  [ -n "${AUDIT_COMMAND:-}" ] && AUDITS+=("$AUDIT_COMMAND")
  while IFS= read -r line; do
    [ -n "${line//[[:space:]]/}" ] && AUDITS+=("$line")
  done <<<"${AUDIT_COMMANDS:-}"
  return 0
}

# run_audits <prefix>: runs every command load_audits finds through
# run_audit, each with its own attempts, timeout and verdict, and prints one
# word for the lot:
#
#   error     any command errored, whatever the others found (#8): a second
#             tool's outage must not hide behind the first tool's IDs
#   findings  none errored and at least one found something
#   clean     every command was clean
#
# Writes <prefix>.out, each command's output under a "$ command" line, and
# <prefix>.ids, the IDs from the commands that found something. IDs a clean
# command printed (govulncheck's unreached code) don't count.
run_audits() {
  local prefix=$1 i status overall=clean
  load_audits
  : >"$prefix.out"
  : >"$prefix.ids.all"
  for i in "${!AUDITS[@]}"; do
    status="$(AUDIT_COMMAND="${AUDITS[$i]}" run_audit "$prefix.$i.out")"
    printf '$ %s\n' "${AUDITS[$i]}" >>"$prefix.out"
    cat "$prefix.$i.out" >>"$prefix.out"
    case "$status" in
      error)
        echo "Audit command $((i + 1)) of ${#AUDITS[@]} errored: ${AUDITS[$i]}" >&2
        overall=error
        ;;
      findings)
        extract_ids <"$prefix.$i.out" >>"$prefix.ids.all"
        [ "$overall" = error ] || overall=findings
        ;;
    esac
  done
  sort -u "$prefix.ids.all" | sed '/^$/d' >"$prefix.ids"
  rm -f "$prefix.ids.all"
  echo "$overall"
}

# audit_label: the commands, as inline code, for the ticket.
audit_label() {
  local cmd out=""
  load_audits
  for cmd in "${AUDITS[@]}"; do
    out+="${out:+, }\`${cmd}\`"
  done
  printf '%s' "$out"
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
