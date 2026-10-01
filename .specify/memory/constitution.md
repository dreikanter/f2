<!--
Sync Impact Report
Version: 1.0.0 -> 2.0.0 (MAJOR: replace duplicated principles with AGENTS.md;
allow existing test coverage for behavior-preserving refactors).
Templates: tasks-template.md now uses AGENTS.md R01/R02 for testing.
plan-template.md, spec-template.md, and checklist-template.md need no changes.
-->

# Feeder Constitution

[AGENTS.md](../../AGENTS.md) is the canonical source for development rules.
Read it when planning or implementing work; do not duplicate its rules here.
Its stable rule IDs are the basis for the Constitution Check in feature plans.

## Spec Kit workflow

Use the Spec Kit workflow for non-trivial feature work. Trivial fixes,
documentation changes, dependency updates, and behavior-preserving refactors
may skip specification.

1. Specify the user-visible change in `specs/NNN-slug/spec.md`.
2. Clarify missing requirements when needed.
3. Plan the implementation and identify applicable AGENTS.md rules in the
   Constitution Check. Explain any proposed exceptions in Complexity Tracking.
4. Generate dependency-ordered tasks aligned with focused commits and the
   testing requirements in AGENTS.md.
5. Check consistency across the design artifacts when useful.
6. Implement and verify the work using AGENTS.md.

Use the existing application stack. Explain new frameworks or architectural
departures in the plan's Complexity Tracking section.

## Amendments

Change development rules in AGENTS.md and Spec Kit workflow rules here.
Keep dependent templates consistent. For constitution changes, update the sync
report and version: major for changed obligations, minor for additions, patch
for clarifications.

**Version**: 2.0.0 | **Ratified**: 2026-05-12 | **Last Amended**: 2026-10-02
