#!/usr/bin/env bash
# Entrypoint for action.yml. Reads its inputs from the environment:
#
#   ADVISORY_MODE      gate | scan
#   AUDIT_COMMAND      the audit, run in bash; non-zero exit on findings
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
# read it. Only api() in scan.sh uses this unexported copy.
API_TOKEN="${ADVISORY_TOKEN:-}"
unset ADVISORY_TOKEN

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$here/lib.sh"

[ -n "${AUDIT_COMMAND:-}" ] || die "The command input is empty: pass the audit to run, such as 'bun audit'."

workspace="${GITHUB_WORKSPACE:-$PWD}"
workdir="${WORKING_DIRECTORY:-.}"
cd "$workspace/$workdir" || die "working-directory '$workdir' doesn't exist in $workspace."

case "${ADVISORY_MODE:-}" in
  gate)
    API_TOKEN=""
    require git timeout grep sed sort paste awk mktemp
    # shellcheck source=gate.sh
    source "$here/gate.sh"
    gate
    ;;
  scan)
    require timeout grep sed sort paste awk mktemp curl jq
    [ -n "$API_TOKEN" ] || die "Scan mode needs a token that can write issues."
    # shellcheck source=scan.sh
    source "$here/scan.sh"
    scan
    ;;
  *)
    die "Unknown mode '${ADVISORY_MODE:-}': use gate or scan."
    ;;
esac
