> **HYPOTHETICAL EXAMPLE.** See the banner in spec.md. Shows a plan that stopped for business decisions,
> then resumed after authorization. Checks are reported exactly as they ran on the synthetic fixture.

# Plan: DEMO-101 Validate gloss measurement range

Status: Approved (by product owner and developer, 2026-10-19 — "range 0-150 inclusive, same for DAB; go ahead and implement")  
Spec: ./spec.md · Task folder: `%USERPROFILE%\.akzo-agent\tasks\demo-backend\DEMO-101\`

## 1. Approach
- Add one rule to the existing `AddMeasurementValidator`, following the `RuleFor(...).WithMessage(...)` style at `AddMeasurementValidator.cs:9`.
- Why: validation already sits in the application layer and runs for both CDMS and DAB paths (`AddMeasurementCommand.cs:8`), so one rule covers both sources without touching the writers.
- Rejected: checks inside each writer (duplicates the rule and allows drift between CDMS and DAB).

## 2. Tasks
| T | Task | Repo | Files | Depends on | ACs | Status |
|---|------|------|-------|------------|-----|--------|
| T1 | Add gloss range rule | demo-backend | `src/Demo.Application/Measurements/AddMeasurementValidator.cs` | Q1, Q2 | AC1-AC4 | done |
| T2 | Boundary tests for both sources | demo-backend | `tests/Demo.Application.Tests/AddMeasurementValidatorTests.cs` | T1 | AC1-AC4 | done |
| T3 | Localize message | demo-ui | `src/assets/i18n/en.json` | — | — | follow-up (not authorized) |

## 3. Code generation
None (no GraphQL document or schema change).

## 4. Validation
| V | Command | Scope | Result |
|---|---------|-------|--------|
| V1 | `dotnet test tests/Demo.Application.Tests` | narrow | **not run** — fixture has no .csproj/.sln; the registry has no verified test command |
| V2 | solution build | wide | **not run** — same reason |
| V3 | `git status --porcelain` | scope check | ran: ` M README.md` (pre-existing, untouched), ` M ...AddMeasurementValidator.cs`, ` M ...AddMeasurementValidatorTests.cs` |

## 5. Risks and rollback
| Risk | Mitigation | Rollback |
|------|------------|----------|
| Existing clients send gloss > 150 | Product owner confirmed range | Revert T1 (single rule) |

## 6. Progress and evidence
- 2026-10-19 Plan mode: investigation, spec, plan. **Stopped**: Q1 and Q2 blocking (range and DAB parity change behavior). No source changes.
- 2026-10-19 Run mode after answers and authorization: T1, T2 done. Pre-existing change in `README.md` preserved.
- Unavailable checks: V1, V2 (no runnable project in the fixture). AC1-AC3 are covered by written tests that have **not** been executed.
- Gap found in evaluation: AC4 (other kinds unaffected) has no test yet; V3 is planned, not written.
- Handover: changes left uncommitted; T3 proposed for demo-ui.
