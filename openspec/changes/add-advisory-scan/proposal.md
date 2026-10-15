## Why

Audit jobs across the account fail every pull request the day an advisory is
published, and the workaround has been an `--ignore` list per repo, which hides
findings from the only place they were visible. `rules/dependencies.md`
("Vulnerability scanning", alrayyes/dotfiles#849, #851) now splits the job: a
pull request check for what the pull request introduces, and a scan of the
default branch that keeps one ticket. Tracked in alrayyes/advisory-scan#1.

## What Changes

- A composite action with `mode: gate` that audits head and base and fails only
  on advisory IDs the head adds.
- `mode: scan` that audits the default branch and creates, updates or closes one
  `Dependency advisories` issue through the GitHub or Forgejo REST API.
- Advisory IDs read from the audit's raw output by regex, so any ecosystem works.
- A bounded retry around the audit that never retries a real finding.

## Impact

- New repo, no existing consumers. Pilot in alrayyes/service-not-ready.
- Runner images need bash and git (gate), plus curl and jq (scan).
