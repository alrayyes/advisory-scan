# shellcheck shell=bash
# Gate mode: fail only on advisories the head introduces over the base.
# Sourced by advisory-scan.sh, which has already sourced lib.sh and changed
# into the head's working directory.

# gate <working directory, relative to the repository root>
gate() {
  local workdir=$1
  local tmp head_ids base_ids introduced base_tree status
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064 # expand now: $tmp is local
  trap "gate_cleanup '$tmp'" EXIT

  echo "::group::Audit the head"
  run_setup
  status="$(run_audit "$tmp/head.out")"
  echo "::endgroup::"

  case "$status" in
    clean)
      echo "The head audit is clean, so this pull request introduces no advisory."
      set_output advisories ""
      set_output introduced ""
      return 0
      ;;
    error)
      die "The head audit failed three times with no advisory ID in its output, so it's the tool or the registry, not a finding. See the log above."
      ;;
  esac

  head_ids="$tmp/head.ids"
  extract_ids <"$tmp/head.out" >"$head_ids"
  set_output advisories "$(join_ids <"$head_ids")"

  # A new branch's first push has an all-zero github.event.before.
  [[ "${BASE_SHA:-}" =~ ^0*$ ]] && BASE_SHA=""
  [ -n "${BASE_SHA:-}" ] ||
    die "The head has advisories and there's no base commit to compare against. Pass base-sha, or run gate mode on pull_request."

  base_tree="$tmp/base"
  checkout_base "$BASE_SHA" "$base_tree"

  echo "::group::Audit the base ($BASE_SHA)"
  (
    cd "$base_tree/$workdir" || die "working-directory '$workdir' doesn't exist on the base commit."
    run_setup
    run_audit "$tmp/base.out" >"$tmp/base.status"
  )
  echo "::endgroup::"

  base_ids="$tmp/base.ids"
  case "$(cat "$tmp/base.status")" in
    clean) : >"$base_ids" ;;
    findings) extract_ids <"$tmp/base.out" >"$base_ids" ;;
    *) die "The base audit failed three times with no advisory ID in its output, so there's nothing to compare the head against. See the log above." ;;
  esac

  introduced="$(introduced_ids "$head_ids" "$base_ids")"
  set_output introduced "$(join_ids <<<"$introduced")"

  if [ -n "$introduced" ]; then
    local -a list
    mapfile -t list <<<"$introduced"
    {
      echo "### Advisories this pull request introduces"
      echo
      printf -- '- %s\n' "${list[@]}"
    } | summary
    die "This pull request introduces ${#list[@]} advisory ID(s): $(join_ids <<<"$introduced")"
  fi

  echo "::notice::No new advisories. Already on the base, tracked by the scan: $(join_ids <"$head_ids")"
}

# checkout_base <sha> <dir>: a detached worktree of the base commit,
# fetched first if the checkout is shallow and doesn't have it.
checkout_base() {
  local sha=$1 dir=$2
  if ! git cat-file -e "${sha}^{commit}" 2>/dev/null; then
    git fetch --quiet --no-tags --depth=1 origin "$sha" ||
      die "Couldn't fetch the base commit $sha from origin."
  fi
  git worktree add --quiet --detach "$dir" "$sha" ||
    die "Couldn't check out the base commit $sha."
}

gate_cleanup() {
  local tmp=$1
  if [ -d "$tmp/base" ]; then
    git worktree remove --force "$tmp/base" >/dev/null 2>&1 || true
  fi
  rm -rf "$tmp"
}
