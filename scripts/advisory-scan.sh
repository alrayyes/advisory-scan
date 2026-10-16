#!/usr/bin/env bash
# Entrypoint for action.yml. Reads its inputs from the environment:
#
#   ADVISORY_MODE      gate | scan
#   AUDIT_COMMAND      the audit, run in bash; non-zero exit on findings
#   AUDIT_COMMANDS     more audits, one per line, each classified on its own
#   SETUP_COMMAND      optional, run before each audit in the same directory
#   WORKING_DIRECTORY  relative to GITHUB_WORKSPACE
#   BASE_SHA           gate mode: the commit to compare against
#   ADVISORY_TOKEN     scan mode: a token that can write issues
#   ISSUE_TITLE        scan mode: the ticket's title
#   ISSUE_LABELS       scan mode: comma-separated labels for a new ticket
#   AUDIT_TIMEOUT      seconds per audit attempt
set -euo pipefail

# The token leaves the environment before anything else runs, so setup, the
# audit and whatever they spawn (postinstall scripts, Composer plugins) can't
# read it. Only api() in scan.sh uses this copy. A variable inherited from
# the environment keeps its export flag when reassigned, and a job-level
# env: reaches composite steps, so the copy is unset first and explicitly
# un-exported, under a name a caller has no reason to set.
unset __advisory_scan_token
__advisory_scan_token="${ADVISORY_TOKEN:-}"
export -n __advisory_scan_token
unset ADVISORY_TOKEN

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$here/lib.sh"

load_audits
[ "${#AUDITS[@]}" -gt 0 ] || die "The command input is empty: pass the audit to run, such as 'bun audit', or one per line in commands."

workspace="${GITHUB_WORKSPACE:-$PWD}"
workdir="${WORKING_DIRECTORY:-.}"
cd "$workspace/$workdir" || die "working-directory '$workdir' doesn't exist in $workspace."

case "${ADVISORY_MODE:-}" in
  gate)
    __advisory_scan_token=""
    require git timeout grep sed sort paste awk mktemp
    # shellcheck source=gate.sh
    source "$here/gate.sh"
    gate
    ;;
  scan)
    require timeout grep sed sort paste awk mktemp curl jq
    # A pull request's head isn't the default branch, and pull_request_target
    # would audit a fork's lockfile with a write token.
    case "${GITHUB_EVENT_NAME:-}" in
      pull_request*) die "Scan mode doesn't run on $GITHUB_EVENT_NAME: it keeps the default branch's ticket. Use gate mode on pull requests." ;;
    esac
    [ -n "$__advisory_scan_token" ] || die "Scan mode needs a token that can write issues."
    # shellcheck source=scan.sh
    source "$here/scan.sh"
    scan
    ;;
  *)
    die "Unknown mode '${ADVISORY_MODE:-}': use gate or scan."
    ;;
esac
