#!/usr/bin/env sh
# Grammar, spelling, the phonetic article. Fails the build - mechanics have
# a right answer, unlike Vale's style tier.
#
# In CI, the grammar job's own container is ghcr.io/alrayyes/ltex-cli-plus,
# so ltex-cli-plus is already on PATH and this script's only job there is to
# skip fetching anything. Locally, prefers docker against the same image
# (about the same ~10s once pulled as the raw tarball, per
# rules/markdown.md); a machine with neither falls back to fetching and
# caching the release tarball under $XDG_CACHE_HOME.
set -eu

VERSION=18.7.0
IMAGE="ghcr.io/alrayyes/ltex-cli-plus:$VERSION@sha256:00c30809802234d6c43b0ce0b295075bd0aff9c576aaba57433bc8baf314398c"

if command -v ltex-cli-plus >/dev/null 2>&1; then
  run_ltex() { ltex-cli-plus "$@"; }
elif command -v docker >/dev/null 2>&1; then
  run_ltex() {
    docker run --rm -v "$PWD:/work" -w /work --entrypoint /usr/local/bin/ltex-cli-plus "$IMAGE" "$@"
  }
else
  CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/ltex-ls-plus/$VERSION/ltex-ls-plus-$VERSION"
  CLI="$CACHE_DIR/bin/ltex-cli-plus"

  if [ ! -x "$CLI" ]; then
    TMP=$(mktemp -d)
    curl -fsSL -o "$TMP/ltex.tar.gz" \
      "https://github.com/ltex-plus/ltex-ls-plus/releases/download/$VERSION/ltex-ls-plus-$VERSION-linux-x64.tar.gz"
    mkdir -p "$(dirname "$CACHE_DIR")"
    tar -xzf "$TMP/ltex.tar.gz" -C "$(dirname "$CACHE_DIR")"
    rm -rf "$TMP"
  fi
  run_ltex() { "$CLI" "$@"; }
fi

cd "$(dirname "$0")/.."

# ltex-cli-plus exits 3 when it finds something, not 1. Testing for a
# specific code would pass a failing document, so this tests for non-zero.
run_ltex --client-configuration=.ltex.json README.md CONTRIBUTING.md SECURITY.md
