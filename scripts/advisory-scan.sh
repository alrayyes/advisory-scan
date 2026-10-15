#!/usr/bin/env bash
# Entrypoint for action.yml. Reads its inputs from the environment:
#
#   ADVISORY_MODE      gate | scan
#   AUDIT_COMMAND      the audit, run in bash; non-zero exit on findings
#   SETUP_COMMAND      optional, run before each audit in the same directory
#   WORKING_DIRECTORY  relative to GITHUB_WORKSPACE
#   BASE_SHA           gate mode: the commit to compare against
#   AUDIT_TIMEOUT      seconds per audit attempt
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$here/lib.sh"

[ -n "${AUDIT_COMMAND:-}" ] || die "The command input is empty: pass the audit to run, such as 'bun audit'."

workspace="${GITHUB_WORKSPACE:-$PWD}"
workdir="${WORKING_DIRECTORY:-.}"
cd "$workspace/$workdir" || die "working-directory '$workdir' doesn't exist in $workspace."

case "${ADVISORY_MODE:-}" in
  gate)
    require git timeout grep sed sort paste
    # shellcheck source=gate.sh
    source "$here/gate.sh"
    gate
    ;;
  *)
    die "Unknown mode '${ADVISORY_MODE:-}': use gate."
    ;;
esac
