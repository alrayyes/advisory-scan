# advisory-scan

A composite action for GitHub Actions and Forgejo Actions that runs your
ecosystem's dependency audit in two ways:

- **gate**, on a pull request: audit the base and the head, and fail only on
  advisories the head introduces. A pull request that changed nothing goes
  green the morning an advisory is published.
- **scan**, on the default branch: audit everything and keep one open issue,
  `Dependency advisories`, that lists what's there. It's created when
  findings appear, updated when they change and closed when the audit is
  clean.

Neither mode takes a list of advisories to ignore. A known advisory with no fix lives in
the scan issue until a fix ships, instead of being hidden from the only
place that tracks it.

## Usage

Pin the action to a full commit SHA, with the release in a comment. On
Forgejo, use the full URL: `uses: https://github.com/alrayyes/advisory-scan@<sha>`.

```yaml
- uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
- uses: oven-sh/setup-bun@0c5077e51419868618aeaa5fe8019c62421857d6 # v2.2.0
  with:
    bun-version: "1.4.3"
- uses: alrayyes/advisory-scan@<sha> # vX.Y.Z
  with:
    mode: gate
    command: bun audit
```

And on the default branch, for the ticket:

```yaml
on:
  schedule:
    - cron: "17 5 * * *"
  push:
    branches: [main]
    paths: [package.json, bun.lock]
  workflow_dispatch:

jobs:
  scan:
    runs-on: ubuntu-24.04
    permissions:
      contents: read
      issues: write
    steps:
      # checkout and setup-bun as above
      - uses: alrayyes/advisory-scan@<sha> # vX.Y.Z
        with:
          mode: scan
          command: bun audit
          labels: dependencies
```

`examples/` has complete workflows for GitHub with bun, GitHub with
Composer and Forgejo with bun.

### Inputs

| Input               | Default                              | What it does                                                                                                                              |
| ------------------- | ------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `mode`              | required                             | `gate` or `scan`.                                                                                                                         |
| `command`           | required                             | The audit, run in bash. It must exit non-zero when it finds an advisory.                                                                  |
| `setup`             | none                                 | Run before the audit in the same directory, and again on the base checkout in gate mode. For an audit that needs an installation first.   |
| `working-directory` | `.`                                  | Where to run, relative to the workspace.                                                                                                  |
| `base-sha`          | the pull request's base, or `before` | Gate mode: the commit to compare against.                                                                                                 |
| `timeout-seconds`   | `300`                                | Time limit per audit attempt.                                                                                                             |
| `token`             | `github.token`                       | Scan mode: a token that can create, edit and comment on issues.                                                                           |
| `title`             | `Dependency advisories`              | Scan mode: the ticket's title, which is also how the next run finds it. Give each a different one if a repo scans more than one lockfile. |
| `labels`            | none                                 | Scan mode: comma-separated labels for a new ticket. On Forgejo they must already exist.                                                   |

Outputs: `advisories` (every ID the audit named) and `introduced` (gate
mode: the IDs the head adds), both space-separated, and `issue` (scan mode:
the ticket's number).

### Commands per ecosystem

| Ecosystem | `command`                                               | Notes                                                                                           |
| --------- | ------------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| bun       | `bun audit`                                             | Reads `bun.lock`; no install needed.                                                            |
| Composer  | `composer audit --locked --abandoned=report`            | `--locked` reads `composer.lock` without an installation. An abandoned package isn't a finding. |
| Go        | `go run golang.org/x/vuln/cmd/govulncheck@v1.8.0 ./...` | Needs `actions/setup-go` first. Prints `GO-` IDs.                                               |
| Python    | `pip-audit -r requirements.txt`                         | Install `pip-audit` with a pinned version in `setup`, or before the action.                     |
| Rust      | `cargo audit`                                           | Install `cargo-audit` first. Prints `RUSTSEC-` IDs.                                             |

## How it works

The action runs `command` and reads advisory IDs out of whatever it prints:
`GHSA-`, `CVE-`, `PKSA-`, `GO-`, `PYSEC-` and `RUSTSEC-`. No tool's JSON
format is parsed, so any audit that prints its IDs works.

- **Exit 0** is clean, whatever the output says.
- **A non-zero exit that names an advisory** is a finding. It isn't retried,
  since a real finding fails every attempt the same way.
- **A non-zero exit that names nothing**, or a timeout, is the tool or the
  registry failing. It's retried up to three times, then the step fails.

**Gate mode** audits the head. If that's clean it stops there. Otherwise, it
checks out the base commit in a separate worktree (fetching it if the
checkout is shallow), runs `setup` and the audit there, and fails only on
IDs the head has that the base doesn't. A pull request that touches nothing,
or fixes an advisory, passes. If the base audit errors, the gate fails
rather than guessing.

**Scan mode** audits the working tree and finds the oldest open issue (not
pull request) with the configured title. The first line of the body it
writes is a comment recording the IDs, which is what the next run compares
against:

| Audit                   | Open ticket   | Action                                     |
| ----------------------- | ------------- | ------------------------------------------ |
| findings                | none          | create it, then add `labels`               |
| findings                | same IDs      | leave it                                   |
| findings                | different IDs | replace the body                           |
| clean                   | yes           | comment with the commit and run, and close |
| clean                   | none          | nothing                                    |
| error (no IDs, 3 tries) | either        | fail the job, no API call at all           |

The body lists the sorted IDs, linked to [OSV](https://osv.dev) where it
has a page, then the command, commit, date, a link to the run and the raw
output in a code block (cut at 50,000 characters to fit). Scan mode passes
when it has recorded findings: the ticket is the signal, and a red default
branch every morning would only train people to ignore it.

The forge comes from the environment: Forgejo's runner sets
`FORGEJO_ACTIONS`, and its `GITHUB_API_URL` ends in `/api/v1`. Both forges
take the same issue paths under that URL. The differences handled are the
authorization header, the page size parameter, Forgejo's `type=issues`
filter against GitHub's `pull_request` field, `state_reason` on close
(GitHub only), and the run link, which uses the run number on Forgejo.

One advisory can carry several IDs: Composer prints the PKSA, CVE and GHSA
of each. Both sides of the comparison see the same set, so this changes
nothing about what fails.

There's no `ignore` input, on purpose. A pipeline that needs an ignore list
to go green is gating on the wrong thing.

## Runner requirements

GitHub's `ubuntu-24.04` and `ubuntu-22.04` images have everything. A
Forgejo `docker` runner needs these in the job's container:

- bash, which every step of the action runs in
- git, to fetch and check out the base commit (gate mode)
- curl and jq, for the issues API (scan mode)
- GNU coreutils or BusyBox: `timeout`, `grep`, `sed`, `sort`, `paste`,
  `awk`, `mktemp`

On `oven/bun:*-alpine` that's `apk add --no-cache nodejs bash git curl jq`:
the `nodejs` package because `actions/checkout` needs real Node.js, and that
image's `node` is bun's fallback wrapper. The example in
`examples/forgejo-bun.yml` hasn't run on a real Forgejo runner yet. The
action names anything missing before it runs the audit. CI runs the whole
test suite on Alpine as well as Ubuntu, so BusyBox's versions of the
coreutils are covered.

On Forgejo, `github.token` needs to be allowed to write issues in the repo.
If it isn't, pass a token from a secret as `token`.

## Development

The logic is bash in `scripts/`, tested with
[bats-core](https://github.com/bats-core/bats-core) under `tests/`. The
checks live in `lefthook.yml` and `.github/workflows/ci.yml`, which run the
same commands. You need [bun](https://bun.sh), bats 1.5 or newer,
shellcheck, actionlint, curl, jq and python3 on your `PATH`. The scan-mode
tests run against `tests/fake_forge.py`, a fake issues API that records
every request, so they need no network and no token.

```sh
bun install --frozen-lockfile   # installs the tooling and the git hooks
bats tests/                     # the test suite
lefthook run pre-push           # everything CI runs, in check mode
```

CI runs the tests under kcov and puts line coverage in the job summary. Its
`audit` job runs this action, from the pull request's own head, against
the repo's tooling lockfile.

Run `scripts/lint-vale.sh` once with no arguments on a fresh clone to fetch
the Vale styles. `CONTRIBUTING.md` has the rest.

## Licence

GPL-3.0, see `LICENSE`.
