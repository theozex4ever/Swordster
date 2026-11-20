# Swordster agent instructions

## Agent skills

### Issue tracker

Track specs and tickets in GitHub Issues for `theozex4ever/Swordster`.
Before reading, creating or updating issues, read `docs/agents/issue-tracker.md`.

### Triage labels

Before classifying issues or applying workflow labels, read `docs/agents/triage-labels.md`.

### Domain docs

Single-context domain: before exploring or changing game behavior, read
`GLOSSARY.md`, relevant ADRs, and the consumer rules in `docs/agents/domain.md`.

## Scope and pace

Avoid scope creep. A PR delivers what its issue asks; a review-fix round
delivers the accepted blocking findings. Put every other idea (refactors,
extra checks, tooling, wider coverage) in the PR body or report as a proposed
follow-up issue.

Validation before asking for review:

- `./build-godot.sh --checks-only` passes on the PR head.
- `tools/godot/mutation-check.sh` in its default fast mode (`FAST=1`) catches
  every mutation in the sections the change touches (`SECTIONS=...`, rerun
  fixes with `ONLY=...`).
- Classic mode (`FAST=0`) and full mutation passes run in CI; they are not part
  of a PR's plan or a merge condition.
