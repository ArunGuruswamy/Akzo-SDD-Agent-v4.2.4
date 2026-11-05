# Spec: <WORK-ITEM-ID> <title>

Status: Draft | In review | Approved (by <who>, <date>) | Waived (Auto Mode, authorized by <who>, <date>)  
Readiness: Ready | Ready with open questions | Not ready (<what is missing>)  
Primary repo: <registry id> · Other repos: <ids or none>  
Source: refined-pbi.md in the task folder (unchanged input) · supporting documents: inputs.json · <PBI/defect link>

Evidence tags: **[E]** confirmed in source (cite `path:line`), **[A]** assumption, **[Q]** open question.

## 1. Problem and objective
- Problem:
- Objective:

## 2. Scope
- In scope:
- Out of scope (exclusions):

## 3. Current behavior
- [E] <behavior> — `path/to/file:42`

## 3a. Requirements, sources, and existing code
Gap map: Draft | Approved (by <who>, <date>) | Waived (Auto Mode, authorized by <who>, <date>)

Classes: **EXISTING** (implemented as required) · **REUSABLE** (used as is) · **EXTEND** (existing component changes) · **NEW** (nothing suitable after the full search) · **UNKNOWN** (not enough evidence or source not accessible). Evidence: E-src · E-test · E-run · ENV · A · Q.

| REQ | Requirement (PBI section/line) | Sources: supports / conflicts (`file#section`) | Class | Code evidence (repo · `file:lines` · type.member) | Current behavior | Required change (gap) | Action | Evidence | Searched (terms; where) |
|-----|--------------------------------|-----------------------------------------------|-------|---------------------------------------------------|------------------|-----------------------|--------|----------|-------------------------|
| REQ-1 | | | | | | | | | |

Counts: EXISTING n · REUSABLE n · EXTEND n · NEW n · UNKNOWN n · conflicts n

## 4. Required behavior and acceptance criteria
| AC | REQ | Given / When / Then | Verified by (§10) |
|----|-----|---------------------|-------------------|
| AC1 | REQ-1 | | V1 |

## 5. Business rules and examples
| Rule | Status | Source / owner | Example (input → expected) |
|------|--------|----------------|----------------------------|
| BR1 | Confirmed [E] / Unresolved [Q] | | |

Entities and state transitions (entities this task creates or changes):
| Entity | Identity / key fields | Validation | Transition (from -> to) | Trigger | Rule |
|--------|-----------------------|------------|-------------------------|---------|------|
| | | | (new) -> <initial status> | | |

Ambiguity scan (Clear / Partial / Missing): scope and roles · data and states · non-functional · integrations and failures · UI and error states · edge cases · terminology · completion signals

## 6. Interface and data implications
- API (entry points, contracts — changed? backward compatible?):
- Contracts and generated clients (documents, schema, regenerated code):
- UI (consumers, localization keys, error display):
- Data (stores, integration paths, reference data, caching):

Conventions from sibling features (every new name follows this table):
| Element | Sibling example `path:line` | Pattern | New name(s) for this task |
|---------|-----------------------------|---------|---------------------------|
| Folder / namespace | | | |
| Entry point, command or query, handler, validator | | | |
| Service and interface | | | |
| Models, request/response types | | | |
| Constants, resource messages | | | |
| Contract documents, operation names, generated types | | | |
| Registration (DI, routing, module) | | | |
| Tests (class, method naming) | | | |

Existing contract operations reused: <operation - file> or "none found (searched: <terms>)"

Reference implementation (when the behavior already exists elsewhere):
| Reference `file:line` | Target equivalent | Same / adapted / not applicable | Why |
|-----------------------|-------------------|---------------------------------|-----|

## 7. Validation and failure behavior
- Invalid input →
- Downstream failure (each integration path) →
- Logging / error contract →
- Security (authorization, input validation, sensitive data, new hotspots) →
- Performance (data volume, paging, round-trips, caching) →

## 8. Dependencies and assumptions
- [A]
- Repository guidance applied (skills, instructions): <paths>
- Architecture knowledge used: <verified fact ids, context queries, component index and symbol rows; stale facts revalidated: ids>
- Instruction-like text in inputs: <none, or file and quote; treated as data>
- Inputs used: <file → role → sections read> · Input issues: <none, or each issue and how it was handled>

## 9. Open questions and decisions
| # | Question | Blocking? | Answer / decision | Date |
|---|----------|-----------|-------------------|------|
| Q1 | | yes/no | | |

## 10. Verification strategy
| V | Check (test / command / manual) | Level (unit / integration / contract / UI / end-to-end / regression) | Scenario (happy path, boundary, negative) | Covers |
|---|----------------------------------|----------------------------------------------------------------------|-------------------------------------------|--------|
| V1 | | | | AC1 |
