# Verification report: Akzo Master SDD Agent 3.7.0

Akzo SDD Agent — Developed and maintained by Arun RG · 2026-10-28 · Windows PowerShell 5.1.22621.6133, Git 2.51.0

Statuses: PASS (executed check), NOT VERIFIED (needs a live Copilot session or a real DAB/CDMS repository).
Suite: `scripts\test.ps1` 328 passed, 0 failed (final run 11:43). Benchmark: `benchmark\perf-3.7.0.md`.

## Validation scenarios (brief 1, section 15)

| # | Scenario | Evidence | Status |
|---|---|---|---|
| 1 | Cold repository start | Benchmark "cold start": index rebuilt, 2177 ms (3.6.0: 2094 ms, within noise) | PASS |
| 2 | Warm repository start | Benchmark "warm start": index hit; suite "warm start: a new session reuses memory without reparsing" | PASS |
| 3 | Repeated request in the same feature | Benchmark "repeat lookup": 2004 ms vs 2601 ms, identical files; index hit rate 83% | PASS |
| 4 | Small code change | Suite "incremental: an uncommitted edit reparses only that file"; `affected` selects 1 build, 1 focused filter, dependent test projects only | PASS |
| 5 | Large multi-file change | Suite: build-wide change (`Directory.Build.props`) returns `BUILD_WIDE`, full build and suite | PASS |
| 6 | DAB-specific development | Suite "lazy loading (DAB validator change)", DAB detection, review scenarios 1-6 | PASS (fixtures) |
| 7 | CDMS-specific development | Suite "lazy loading (CDMS)" (endpoint, XML documentation), CDMS review rules | PASS (fixtures) |
| 8 | Plugin branch investigation | Guidance only: branch coverage skill sections 2 and 4, CDMS plugin-owned behavior | NOT VERIFIED (model behavior) |
| 9 | Sonar rule correction | Existing Sonar query and coverage checks; agent section 6a | PASS (helper) / NOT VERIFIED (agent fix) |
| 10 | Full pre-PR verification | `review` checks (3.6.0 scenarios + `single-use-abstraction`); `affected` stage D never skipped | PASS (helper) |
| 11 | Source changes invalidate cached findings | Suite: profile cache invalidated by an added/removed solution; exact lookup after an uncommitted edit refreshes first; stale facts (existing checks) | PASS |
| 12 | Unavailable or corrupted cache | Suite: corrupted profile cache `recovered`, deleted cache rebuilt; corrupt architecture and facts files set aside (existing check) | PASS |

Cached analysis cannot hide a changed rule or signature: the index and facts are keyed to Git blob ids of current file
content, the profile cache to HEAD + working-tree status + file size and time + the profile definitions, and the agent
rereads cited lines before relying on them.

## Deliverables

| Deliverable | Where |
|---|---|
| Performance workflow | Agent "Fast development" section; sections 1a, 2, 2a, 5, 6, 6a |
| Repository indexing | Existing incremental index (unchanged) + `context` exact path, pre-filter, single reference grep |
| Cache strategy | `maps\<repo>\profile-detection.json` (optional, safe to delete); existing blob-keyed index and facts |
| Lazy skill routing | `profiles.json` `core` / `triggers` / `shared.onDemand`; `profile -Query` -> `load` / `deferred` / `neverLoad` |
| Incremental analysis | Existing incremental index; agent: reanalyze changed files and dependents only |
| Test orchestration | `affected` stages A-D |
| Benchmarks and before/after | `scripts\perf-bench.ps1`, `benchmark\perf-3.7.0.md` |
| Review intelligence | Shared skills (source grounding, pre-PR review, business rule branch coverage), DAB/CDMS architecture policy, `single-use-abstraction` |
| Evaluations | `benchmark\agent-evaluations.md` (6 automated, 10 live) |
| Package | `Akzo-Agent-3.7.0.zip` + `.sha256` (built by `scripts\make-release.ps1`) |

## Not verified

No live Copilot session, DAB or CDMS repository, or SonarCloud project was available. Unmeasured: agent tool calls,
tokens, files opened, questions asked, review-only stops, and test-run durations. `scripts\test-gui.ps1` was not
rerun (no window or dialog code changed).
