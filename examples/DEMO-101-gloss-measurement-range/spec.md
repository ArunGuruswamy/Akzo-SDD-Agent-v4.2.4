> **HYPOTHETICAL EXAMPLE.** Produced by following the akzo-sdd skills against synthetic fixture repositories
> (`akzo-demo-backend`, `akzo-demo-ui`) created for this dry run. Not Akzo source; the business rule below is invented.
> The workflow was followed manually outside GitHub Copilot, using the real helper script; it is not a Copilot run or benchmark.

# Spec: DEMO-101 Validate gloss measurement range

Status: Approved  
Primary repo: demo-backend · Other repos: demo-ui (reference, read-only)  
Source: "Reject gloss measurements outside the valid range when adding a measurement to an imitation request."

Evidence tags: **[E]** confirmed in source, **[A]** assumption, **[Q]** open question.

## 1. Problem and objective
- Problem: out-of-range gloss values are accepted and written to CDMS or DAB.
- Objective: reject them at the API with a validation error before any write.

## 2. Scope
- In scope: validation of `Value` for `Kind == "Gloss"` in the add-measurement command.
- Out of scope: other measurement kinds, existing stored data, UI changes.

## 3. Current behavior
- [E] `POST measurements` dispatches `AddMeasurementCommand` through the mediator — `src/Demo.Functions/Measurements/AddMeasurementFunction.cs:7`
- [E] Validator checks id, kind, and source only; no value rule — `src/Demo.Application/Measurements/AddMeasurementValidator.cs:7-9`
- [E] Handler routes to DAB when `Source == "DAB"`, otherwise CDMS — `src/Demo.Application/Measurements/AddMeasurementCommand.cs:8`
- [E] UI posts to `/api/measurements` and has no gloss-specific message — demo-ui `src/app/measurements/measurement.service.ts:4`, `src/assets/i18n/en.json:1`

## 4. Required behavior and acceptance criteria
| AC | Given / When / Then | Verified by |
|----|---------------------|-------------|
| AC1 | Given Kind=Gloss and Value < 0 or > 150, when added, then validation fails and nothing is written | V1, V2 |
| AC2 | Given Kind=Gloss and 0 ≤ Value ≤ 150, when added, then it is accepted | V1 |
| AC3 | AC1-AC2 hold for Source=CDMS and Source=DAB | V1 |
| AC4 | Other kinds are unaffected | V1 |

## 5. Business rules and examples
| Rule | Status | Source / owner | Example |
|------|--------|----------------|---------|
| BR1 Gloss range 0-150 GU inclusive | Confirmed (Q1 answer) | Product owner, 2026-10-19 | 150 → accepted; 150.1 → rejected |
| BR2 Same range for CDMS and DAB | Confirmed (Q2 answer) | Product owner, 2026-10-19 | DAB, -0.1 → rejected |

## 6. Interface and data implications
- API: route and request unchanged; invalid gloss now returns the existing validation error response.
- GraphQL: no change (`GetMeasurements.graphql` reads only).
- UI: no change required; the existing error display shows the server message. [A] Localization of the new message is a follow-up for demo-ui.
- Data: no migration; existing out-of-range rows untouched.

## 7. Validation and failure behavior
- Invalid input → validator message "Gloss must be between 0 and 150 GU." via the existing pipeline.
- CDMS/DAB writes never happen for invalid input (validation runs before the handler). [A] pipeline behavior assumed from the mediator pattern; confirm in a real repo.

## 8. Dependencies and assumptions
- [A] Validation pipeline behavior registered for all commands.

## 9. Open questions and decisions
| # | Question | Blocking? | Answer / decision | Date |
|---|----------|-----------|-------------------|------|
| Q1 | What is the valid gloss range and are bounds inclusive? | yes | 0-150 GU inclusive | 2026-10-19 |
| Q2 | Does DAB/OneColor accept the same range as CDMS? | yes | Yes, identical | 2026-10-19 |
| Q3 | Localize the message in the UI now? | no | Follow-up in demo-ui | 2026-10-19 |

## 10. Verification strategy
| V | Check | Covers |
|---|-------|--------|
| V1 | Validator unit tests: boundaries -0.1, 0, 150, 150.1 for CDMS and DAB | AC1-AC3 |
| V3 | Validator unit test: a non-gloss kind with value 500 stays valid | AC4 |
| V2 | Build and test the application test project | AC1 |
