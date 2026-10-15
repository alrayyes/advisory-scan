# shellcheck shell=bash
# Scan mode: audit the default branch and keep one open ticket that lists
# what it finds. Sourced by advisory-scan.sh, which has already sourced
# lib.sh and changed into the working directory.

# The most an issue body holds is 65,536 characters on GitHub. The output
# gets what's left after everything else, less room for the fence and the
# note that it was cut.
BODY_LIMIT=65536
BODY_MARGIN=512

# decide <status> <open issue number> <recorded IDs> <current IDs>: prints
# create, update, close, leave or fail. IDs are space-separated, any order.
decide() {
  local status=$1 number=$2 recorded current
  recorded="$(tr ' ' '\n' <<<"$3" | sed '/^$/d' | sort -u | join_ids)"
  current="$(tr ' ' '\n' <<<"$4" | sed '/^$/d' | sort -u | join_ids)"
  case "$status" in
    error) echo fail ;;
    clean) if [ -n "$number" ]; then echo close; else echo leave; fi ;;
    findings)
      if [ -z "$number" ]; then
        echo create
      elif [ "$recorded" = "$current" ]; then
        echo leave
      else
        echo update
      fi
      ;;
    *) echo fail ;;
  esac
}

# detect_forge: forgejo when the runner says so or the API URL has
# Forgejo's /api/v1 suffix, github otherwise. Both set GITHUB_API_URL.
detect_forge() {
  if [ "${FORGEJO_ACTIONS:-}" = true ] || [ "${GITEA_ACTIONS:-}" = true ] ||
    [[ "${GITHUB_API_URL:-}" == */api/v1 ]]; then
    echo forgejo
  else
    echo github
  fi
}

# run_url: a link to this run. Forgejo's run pages are numbered by the
# run's index within the repository, which is github.run_number there.
run_url() {
  local id=$GITHUB_RUN_ID
  [ "$(detect_forge)" = forgejo ] && id=$GITHUB_RUN_NUMBER
  echo "${GITHUB_SERVER_URL%/}/${GITHUB_REPOSITORY}/actions/runs/${id}"
}

# advisory_link <id>: Markdown for one ID. OSV indexes every database here
# except FriendsOfPHP's PKSA, which has no public page per ID.
advisory_link() {
  case "$1" in
    PKSA-*) echo "$1" ;;
    *) echo "[$1](https://osv.dev/vulnerability/$1)" ;;
  esac
}

# render_body <ids file> <output file>: the ticket's Markdown body. The
# first line records the IDs for the next run to compare against.
render_body() {
  local ids_file=$1 out_file=$2 id count size head budget shown fence longest
  count="$(grep -c . "$ids_file" || true)"
  size="$(wc -c <"$out_file" | tr -d ' ')"
  head="$(
    echo "<!-- advisory-scan ids: $(join_ids <"$ids_file") -->"
    echo "The dependency audit on the default branch reports $count advisory ID(s)."
    echo "[advisory-scan](https://github.com/alrayyes/advisory-scan) keeps this ticket:"
    echo "it updates the list when the set changes and closes the ticket when the audit"
    echo "is clean. Edits by hand are overwritten on the next change."
    echo
    echo "## Advisories"
    echo
    while IFS= read -r id; do
      [ -n "$id" ] && echo "- $(advisory_link "$id")"
    done <"$ids_file"
    echo
    echo "## Audit output"
    echo
    echo "\`${AUDIT_COMMAND}\` on ${GITHUB_SHA:0:7}, $(date -u +%Y-%m-%d), in [this run]($(run_url))."
  )"
  budget=$((BODY_LIMIT - ${#head} - BODY_MARGIN))
  [ "$budget" -gt 0 ] || budget=0
  shown="$(head -c "$budget" "$out_file")"

  # CommonMark closes a tilde fence on a line of at least as many tildes,
  # indented up to three spaces. Audit output is third-party text, so the
  # fence is one longer than any such line in it, and never under six.
  longest="$(grep -oE '^ {0,3}~+' <<<"$shown" | tr -d ' ' | awk '{ if (length($0) > m) m = length($0) } END { print m + 0 }')"
  [ "$longest" -ge 6 ] || longest=5
  fence="$(printf '%*s' "$((longest + 1))" '' | tr ' ' '~')"

  printf '%s\n\n' "$head"
  echo "${fence}text"
  # $(...) dropped trailing newlines, so the fence closes on its own line.
  printf '%s\n' "$shown"
  echo "$fence"
  if [ "$size" -gt "$budget" ]; then
    echo
    echo "Output cut at $budget characters to fit the issue; the run log has the rest."
  fi
}

# recorded_ids < body: the IDs a previous run recorded in the marker line.
recorded_ids() {
  tr -d '\r' |
    sed -n 's/^<!-- advisory-scan ids: \(.*\) -->$/\1/p' |
    head -n 1 |
    tr ' ' '\n' |
    extract_ids |
    join_ids
}

# api <method> <path> [json body]: one request to the forge's REST API,
# printing the response body. Fails, naming the status, on anything but
# 2xx. The token goes in a header file, not on curl's command line.
api() {
  local method=$1 path=$2 data=${3:-} headers out code
  headers="$(mktemp)"
  out="$(mktemp)"
  {
    if [ "$(detect_forge)" = forgejo ]; then
      echo "Authorization: token $API_TOKEN"
      echo "Accept: application/json"
    else
      echo "Authorization: Bearer $API_TOKEN"
      echo "Accept: application/vnd.github+json"
      echo "X-GitHub-Api-Version: 2022-11-28"
    fi
    echo "Content-Type: application/json"
  } >"$headers"
  local -a args=(-sS -o "$out" -w '%{http_code}' -X "$method" -H "@$headers")
  [ -n "$data" ] && args+=(--data-binary "$data")
  code="$(curl "${args[@]}" "${GITHUB_API_URL%/}${path}")" || code=000
  rm -f "$headers"
  if [[ "$code" != 2* ]]; then
    # stderr: stdout is the caller's to capture.
    echo "::error::$method $path returned HTTP $code: $(head -c 300 "$out")" >&2
    rm -f "$out"
    return 1
  fi
  cat "$out"
  rm -f "$out"
}

# find_issue: the oldest open issue (not pull request) titled $ISSUE_TITLE,
# as {"number": n, "body": "..."}, or nothing.
find_issue() {
  local repo="/repos/${GITHUB_REPOSITORY}/issues" page size query items found=()
  if [ "$(detect_forge)" = forgejo ]; then
    size=50
    query="state=open&type=issues&limit=$size"
  else
    size=100
    query="state=open&per_page=$size"
  fi
  for ((page = 1; page <= 100; page++)); do
    items="$(api GET "$repo?$query&page=$page")" || return 1
    found+=("$(jq -c --arg t "$ISSUE_TITLE" \
      '.[] | select(.pull_request == null and .title == $t) | {number, body: (.body // "")}' <<<"$items")")
    [ "$(jq length <<<"$items")" -lt "$size" ] && break
  done
  printf '%s\n' "${found[@]}" | sed '/^$/d' | jq -sc 'sort_by(.number) | first // empty'
}

# add_labels <number>: $ISSUE_LABELS, comma-separated, by name. Both forges
# take names on this endpoint; Forgejo's must already exist.
add_labels() {
  local labels
  labels="$(jq -c -R 'split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(. != ""))' <<<"${ISSUE_LABELS:-}")"
  [ "$labels" = "[]" ] && return 0
  api POST "/repos/${GITHUB_REPOSITORY}/issues/$1/labels" "$(jq -c -n --argjson l "$labels" '{labels: $l}')" >/dev/null
}

# scan: the whole of scan mode.
scan() {
  local tmp status issue number recorded current action body closing
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064 # expand now: $tmp is local
  trap "rm -rf '$tmp'" EXIT

  echo "::group::Audit"
  run_setup
  status="$(run_audit "$tmp/out")"
  echo "::endgroup::"

  [ "$status" = error ] &&
    die "The audit failed three times with no advisory ID in its output, so it's the tool or the registry, not a finding. The ticket is left as it is."

  if [ "$status" = findings ]; then
    extract_ids <"$tmp/out" >"$tmp/ids"
  else
    : >"$tmp/ids"
  fi
  current="$(join_ids <"$tmp/ids")"
  set_output advisories "$current"

  issue="$(find_issue)" || exit 1
  number="$(jq -r '.number // empty' <<<"${issue:-null}")"
  recorded="$(jq -r '.body // ""' <<<"${issue:-null}" | recorded_ids)"
  action="$(decide "$status" "$number" "$recorded" "$current")"
  echo "Ticket action: $action${number:+ (#$number)}"

  case "$action" in
    create)
      body="$(render_body "$tmp/ids" "$tmp/out")"
      number="$(api POST "/repos/${GITHUB_REPOSITORY}/issues" \
        "$(jq -c -n --arg t "$ISSUE_TITLE" --arg b "$body" '{title: $t, body: $b}')" | jq -r .number)" || exit 1
      add_labels "$number" || exit 1
      ;;
    update)
      body="$(render_body "$tmp/ids" "$tmp/out")"
      api PATCH "/repos/${GITHUB_REPOSITORY}/issues/$number" "$(jq -c -n --arg b "$body" '{body: $b}')" >/dev/null || exit 1
      ;;
    close)
      body="The audit (\`${AUDIT_COMMAND}\`) is clean on ${GITHUB_SHA:0:7} as of $(date -u +%Y-%m-%d), in [this run]($(run_url)). Closing."
      api POST "/repos/${GITHUB_REPOSITORY}/issues/$number/comments" "$(jq -c -n --arg b "$body" '{body: $b}')" >/dev/null || exit 1
      if [ "$(detect_forge)" = forgejo ]; then
        closing='{"state":"closed"}'
      else
        closing='{"state":"closed","state_reason":"completed"}'
      fi
      api PATCH "/repos/${GITHUB_REPOSITORY}/issues/$number" "$closing" >/dev/null || exit 1
      ;;
    leave) ;;
    *) die "Couldn't decide what to do with the ticket (status '$status')." ;;
  esac
  set_output issue "$number"

  if [ -n "$current" ]; then
    echo "::warning::Advisories on the default branch, tracked in #$number: $current"
    printf '### Advisories on the default branch\n\nTracked in #%s: %s\n' "$number" "$current" | summary
  else
    echo "The audit is clean."
  fi
}
