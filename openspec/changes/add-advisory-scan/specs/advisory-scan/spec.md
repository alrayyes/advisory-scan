## ADDED Requirements

### Requirement: Advisory IDs come from the audit's output

The action SHALL treat an audit exit of 0 as clean, a non-zero exit whose output
names at least one GHSA, CVE, PKSA, GO, PYSEC or RUSTSEC ID as findings, and any
other non-zero exit or a timeout as an error.

#### Scenario: Registry failure

- **WHEN** the audit exits non-zero without naming an advisory on all three attempts
- **THEN** the step fails and reports a tool error, not a finding

#### Scenario: Real finding

- **WHEN** the audit exits non-zero and names an advisory
- **THEN** it is not retried

### Requirement: Gate mode fails only on introduced advisories

In gate mode the action SHALL audit the head and, if it has findings, the base
commit, and SHALL fail only when the head names an ID the base does not.

#### Scenario: Pre-existing advisory

- **WHEN** head and base both name GHSA-aaaa-bbbb-cccc
- **THEN** the step passes

#### Scenario: Introduced advisory

- **WHEN** the head names GHSA-dddd-eeee-ffff and the base does not
- **THEN** the step fails naming only GHSA-dddd-eeee-ffff

### Requirement: Scan mode keeps one ticket

In scan mode the action SHALL keep at most one open issue with the configured
title: create it on findings, replace its body when the recorded set of IDs
differs, close it with a comment when the audit is clean, and make no API call
when the audit errors.

#### Scenario: Findings appear

- **WHEN** the audit names GHSA-aaaa-bbbb-cccc and no open ticket exists
- **THEN** one issue is created listing GHSA-aaaa-bbbb-cccc

#### Scenario: Audit is clean

- **WHEN** the audit exits 0 and a ticket is open
- **THEN** the ticket gets a comment and is closed

#### Scenario: Registry is down

- **WHEN** every attempt fails with no advisory ID
- **THEN** the job fails and the ticket is left as it was
