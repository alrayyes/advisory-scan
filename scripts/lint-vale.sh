#!/usr/bin/env sh
# Style: house voice, weasel words, corporate speak, the cliches proselint
# knows. Advice, not a gate - Vale only fails on error-severity alerts
# (MinAlertLevel in .vale.ini), which is why this script's own exit code is
# the real signal and nothing here downgrades it.
#
# With file arguments (the pre-commit hook passes the staged list) it lints
# only those and skips `vale sync`, so a commit makes no network fetch; run
# `scripts/lint-vale.sh` once with no arguments on a fresh clone to fetch the
# styles. With none it syncs and lints the whole set.
set -eu

VERSION=v3.17.1
IMAGE="jdkato/vale:$VERSION"

cd "$(dirname "$0")/.."

if [ "$#" -gt 0 ]; then
  files=$*
  sync=""
else
  files="README.md CONTRIBUTING.md SECURITY.md"
  sync="vale sync && "
fi

if command -v vale >/dev/null 2>&1; then
  [ -z "$sync" ] || vale sync
  # shellcheck disable=SC2086 # word-splitting the file list is intended
  vale $files
else
  docker run --rm -v "$PWD:/work" -w /work --entrypoint sh "$IMAGE" \
    -c "${sync}vale $files"
fi
