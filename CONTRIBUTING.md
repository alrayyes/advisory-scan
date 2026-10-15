# Contributing

This is a personal project. Issues and pull requests are welcome, but there's
no roadmap beyond what the maintainer needs.

## Toolchain

- [bun](https://bun.sh) for the JavaScript-side tooling (commitlint,
  markdownlint, prettier). Nothing here is a JavaScript project;
  `package.json` just pins those tools like everything else.
- [lefthook](https://github.com/evilmartians/lefthook) for git hooks, which
  `bun install --frozen-lockfile` wires up.
- [shellcheck](https://www.shellcheck.net/) and
  [actionlint](https://github.com/rhysd/actionlint) lint the scripts and the
  action and workflow YAML.

## Git hooks

`pre-commit` judges only what the commit contains: each job takes the staged
files and makes no network fetch. Prettier writes only to staged files and
restages them.

`pre-push` runs the whole-tree checks in check mode: shellcheck, actionlint,
prettier, markdownlint, Vale and the grammar check. CI runs the same checks.

## Commits

[Conventional Commits](https://www.conventionalcommits.org/), enforced by
commitlint on every commit message. One logical change per commit.

## Pull requests

Every change lands through a pull request against `main`. CI has to be green
before it merges. The `ci-ok` job is the one required check: it passes when
every other CI job passed or was skipped because the pull request didn't
touch its files.

## Releasing

[release-please](https://github.com/googleapis/release-please) opens a
release pull request from the Conventional Commit history; merging it cuts
the release. Nobody picks a version number by hand.
