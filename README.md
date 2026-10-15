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

## Status

Under construction: the action itself lands in
[#1](https://github.com/alrayyes/advisory-scan/issues/1). This first change
sets up the repo's own tooling, CI and releases.

## Development

The checks live in `lefthook.yml` and `.github/workflows/ci.yml`, which run
the same commands. You need [bun](https://bun.sh), shellcheck and
actionlint on your `PATH`.

```sh
bun install --frozen-lockfile   # installs the tooling and the git hooks
lefthook run pre-push           # everything CI runs, in check mode
```

Run `scripts/lint-vale.sh` once with no arguments on a fresh clone to fetch
the Vale styles. `CONTRIBUTING.md` has the rest.

## Licence

GPL-3.0, see `LICENSE`.
