## Why

A job auditing two ecosystems with one compound command is classified as a
whole: once the first tool prints an advisory ID, an outage in the second
reads as a finding. The gate then passes without auditing the second
ecosystem, and the scan drops its IDs from the ticket. Tracked in
alrayyes/advisory-scan#8.

## What Changes

- A `commands` input: one audit per line, each with its own retries, timeout
  and verdict. `command` keeps working and still runs as one command.
- Any command that errors without naming an advisory makes the step an error.
- The IDs of the commands that found something are combined.

## Impact

- Callers with a compound `command` should move to `commands`.
