# Plan: <WORK-ITEM-ID> <title>

Status: Draft | Approved (by <who>, <date>) | In progress | Done

Spec: ./spec.md · Task folder: <path> · Evidence: <task folder>/evidence/

## 0. Start state and resume
- Mode: gated | auto | plan · Authorization: <who, date, "plan approved" or the Auto Mode record below>
- Auto Mode authorization: <authorized by <who> on <date>; scope: repository <id>, branch <branch>, the files and behavior of this plan, existing dependencies only, no contract, data, or permission change beyond the spec, no commit or push> or "not used"
- Repo: <id> · Branch: `<branch>` · HEAD: `<sha>` · Pre-existing changes (do not disturb): <paths or none>
- PBI baseline recorded: <date> · PBI changes reconciled: <date: summary>
- Remaining: <next task or phase>

## 1. Approach
- Selected approach:
- Architecture followed (architecture index rows, sibling features, reference implementation — cite paths):
- Why (architecture fit, existing patterns reused — cite paths):
- Alternatives rejected:

## 1b. Contract and validation readiness
Fill every row from current repository evidence before requesting plan approval. Pending or incompatible evidence blocks
dependent implementation; approval cannot waive it. NOT APPLICABLE needs an architecture-based explanation.
Use one status per row, not the list of allowed values. Planned work names an existing T task in section 2.

| Check | Status | Evidence (schema/operation/type or validator `path:line`, command result, or applicability reason) | Task / blocker |
|-------|--------|-----------------------------------------------------------------------------------------------|----------------|
| GraphQL schema | PENDING | | |
| GraphQL operations | PENDING | | |
| Generated client | PENDING | | |
| FluentValidation | PENDING | | |
| Validator execution | PENDING | | |
| Architecture compliance | PENDING | | |

- GraphQL schema: VERIFIED or NOT APPLICABLE.
- GraphQL operations: VERIFIED, NEW OPERATION PLANNED, or NOT APPLICABLE when GraphQL is absent.
- Generated client: COMPATIBLE, REGENERATION PLANNED, or NOT APPLICABLE with evidence no generated client is used.
- FluentValidation: EXISTING RULES REUSED, NEW VALIDATOR PLANNED, or NOT APPLICABLE for projects not using it.
- Validator execution: VERIFIED or EXPLICIT IMPLEMENTATION TASK, including the actual non-.NET validation path.
- Architecture compliance: VERIFIED.
- User approval: REQUIRED before application code changes, including Auto Mode; record the explicit decision for this plan.
- Required schema, queries/mutations, fragments, input types, arguments, nullability and reusable operations:
- Existing validators/shared rules; new or modified validator types and application-layer locations:
- DI/pipeline registrations; awaited async validation before the business operation:
- Existing error-response behavior to preserve (properties, messages/codes, status, middleware):
- Affected handlers, services, API contracts and frontend consumers:
- Unit tests (valid, invalid, null/empty, boundaries, async cases) and integration tests (execution order, DI, error contract):

## 1a. Consistency gate (spec <-> plan, before code)
| ID | Category (coverage, duplication, ambiguity, inconsistency, guidance) | Severity | Location | Fix / status |
|----|------------------------------------------------------------------------|----------|----------|--------------|
| C1 | | | | |

Prevention (approved lessons from `task`; `review` reports a repeat as `lesson:<KEY>`):
| Lesson | How this plan applies it (existing component reused, `path`) |
|--------|---------------------------------------------------------------|

Target: new implementation only | legacy implementation only | both. For both, every legacy behavior (plugin, client script, workflow, validation, transformation, status transition) maps to a step in the new implementation, an API, or the UI; a task table per repository.
| Legacy behavior (`path`) | New implementation, API, or UI step (layer, file) | Task | Status (planned / MISSING) |
|------------------------|----------------------------------------|------|----------------------------|

## 2. Tasks
Order matters. Every file listed was found in the repo (no invented paths); new files name the existing pattern they copy.
Task: a descriptive title taken from the work itself (e.g. "Implement reference color lookup"); people see this title, the T id stays internal. Objective: what the task delivers and why the PBI needs it.
Task status values: Not Started | In Progress | Implemented - Verification Pending | Blocked: <reason> | Verified | Completed (Completed only when its checks ran and passed).

| T | Task | Objective (what and why) | REQ | Repo | File | Action (reuse / modify / new) | Evidence (`path:line`, or sibling copied) | Depends on | ACs | Status |
|---|------|--------------------------|-----|------|------|-------------------------------|--------------------------------------------|------------|-----|--------|
| T1 | | | REQ-1 | | | | | — | AC1 | Not Started |

Reused without change (components used as they are; no edit planned):
| Component `path` | REQ | Used by task |
|------------------|-----|--------------|

## 3. Code generation
- <e.g. regenerate the generated client with the repo's verified command; never hand-edit generated files> or "None".

## 4. Validation
Quality baseline (before the first edit) and final result:
| Gate | Command | Baseline | Final |
|------|---------|----------|-------|
| Build errors / warnings (changed files: IDs) | | | |
| Tests failing (names) | | | |
| Analyzer issues in changed files (compiler, Sonar S-rules, lint) | | | |

### Sonar (agent section 6a)
Source: <(a) Sonar tools in chat · (b) helper server query · (c) analyzers in build/lint · (d) IDE problems · (e) scanner run (on request) · (f) static review against the code rules, not a Sonar analysis>  
Gate: <project gate from server | defaults: 0 new issues, hotspots reviewed, changed-line coverage >= the repository's threshold (default 80%), new duplication <= 3%>

| Item | Baseline | Final | Evidence |
|------|----------|-------|----------|
| Quality gate (status, failing conditions) | | | |
| New issues in changed files (by severity) | | | |
| Security hotspots to review | | | |
| Coverage of changed lines (`coverage` command) | | | |
| Duplicated lines in new code | | | |
| Issues fixed (rule, `path:line`) / false positives raised | | | |

| V | Command (from registry, verified) | Scope | Result |
|---|-----------------------------------|-------|--------|
| V1 | | narrow: affected test project | not run |

## 5. Risks and rollback
| Risk | Mitigation | Rollback |
|------|------------|----------|

## 6. Progress and evidence
- <date> T1 done — <files changed>, V1 passed (`<command>`, <n> tests)
- Unavailable checks: <check — reason>

Requirement -> test -> code matrix (handover). `trace` reads the Test column: one or more `file::name` per row, separated by commas.
| REQ | Class | AC | Test (file::name) | Code (`path:line`) | Result (passed / failed / not run - reason) |
|-----|-------|----|-------------------|--------------------|---------------------------------------------|

Memory updated: stored <fact ids> · re-verified <ids> · retired <ids> · none
