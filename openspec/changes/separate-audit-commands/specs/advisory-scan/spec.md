## ADDED Requirements

### Requirement: Each audit command has its own verdict

When several audit commands are given, the action SHALL run and classify each
on its own, SHALL treat the step as an error if any command fails without
naming an advisory, and SHALL otherwise combine the IDs of the commands that
found something.

#### Scenario: A finding and an outage

- **WHEN** the first command names GHSA-aaaa-bbbb-cccc and the second fails naming nothing on every attempt
- **THEN** the step fails as an audit error and the scan ticket is not edited

#### Scenario: Two findings

- **WHEN** the first command names GHSA-aaaa-bbbb-cccc and the second names GO-2024-0001
- **THEN** the advisories are GHSA-aaaa-bbbb-cccc and GO-2024-0001
