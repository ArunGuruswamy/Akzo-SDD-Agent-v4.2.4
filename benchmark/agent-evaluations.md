# Agent evaluations (3.10.0)

Akzo SDD Agent — Developed and maintained by Arun RG

Reusable evaluation cases for development and PR review in any repository profile. Fixtures are synthetic (generic
orders/refunds/colors features); none of them names a real PBI, branch, or class, and none is read by the agent or the
helper at run time, so they cannot become routing rules.

Two kinds of evidence:

- **Automated**: a check in `scripts\test.ps1` that runs the helper on a generated fixture repository. Result: the suite
  run recorded in `evaluation-report.html`.
- **Live**: needs the agent in Copilot Chat on a real or representative repository. Run the prompt, compare with the
  expected behavior, and record PASS / FAIL in `benchmark\results-template.csv`. Until then the case is **NOT VERIFIED**.

| # | Case | Fixture / prompt | Expected behavior | Evidence |
|---|---|---|---|---|
| 1 | Existing validator reuse | Feature with `CreateOrderValidator`; PBI adds a required-field rule | Extends the existing validator; no new validator class; test per rule | Live. Guidance: source-grounded skill "Validation ownership", DAB FluentValidation step 5 |
| 2 | Collaborator validation consolidation | Same rule in a validator and a `...Collaborator` | Reports the duplicate, proposes one owner by what the rule needs, keeps messages and order | Live |
| 3 | Unnecessary abstraction detection | New `OrderRuleHelper` used by nothing else | `review` warns `single-use-abstraction`; agent removes or justifies it | Automated: "review: a new helper type ... single-use-abstraction" |
| 4 | Naming convention enforcement | New file named off the sibling pattern | Renamed to the conventions table from the sibling (`path:line`) | Live (conventions table, section 2) |
| 5 | Dependency cleanup | Remove an interface reached by assembly scanning | Finds references, registration, tests, scanning before removing | Live. Guidance: "Abstractions: add or remove" |
| 6 | Reviewer comment resolution | Three PR comments, one wrong | Each comment verified against code; two fixed, one answered with evidence; every comment has a disposition; same issue fixed elsewhere in the feature | Live. Guidance: pre-PR review sections 3 and 5 |
| 7 | Duplicate validation detection | Same block added twice in a change | `review` error `duplicate-change` | Automated: 3.6.0 scenario 3 checks |
| 8 | Incomplete Yes/No branches | Rule "approved -> process, not approved -> reject"; only Yes implemented | Branch table shows No as MISSING; classified EXTEND; smallest change + test for No | Live. Guidance: business rule branch coverage skill |
| 9 | Error contract preservation | Function converts the validation exception the middleware already handles | `review` error `redundant-validation-conversion`; removed only if middleware keeps field, message, status | Automated: 3.6.0 scenarios 1-2 |
| 10 | Cross-feature regression impact | Change in a shared Application project | `affected` selects the dependent test projects and not unrelated ones | Automated: "affected: ... unrelated Reports.Tests excluded" |
| 11 | GraphQL query reuse | Needed data already selected by an existing operation | Reuses or extends the operation; no duplicate document | Live (section 2, contracts before adding anything) |
| 12 | DI registration errors | New handler not registered | Integration check finds it; registration added where siblings register | Live (section 6 integration check) |
| 13 | SonarCloud compliance | Changed method over cognitive complexity 15 | Fixed with the smallest change; remote gate not claimed without a server result | Live; helper Sonar queries automated in the Sonar checks |
| 14 | Analysis before approval | "Review this and propose a fix before changing anything" | Analysis, file-by-file proposal, risks, test plan; no file edited | Live. Agent: "Review-only / plan-first" |
| 15 | Fast source investigation | Exact class name in the request | `context` exact hit with tests and callers; no repository scan | Automated: "context: an exact type name returns that file with its tests and direct callers" |
| 16 | Profile separation | Request in a CDMS repository | Only CDMS and shared files loaded; DAB files in `neverLoad`; DAB solution commands refused | Automated: isolation, lazy loading (CDMS), and guard checks |

## Task routing and selective context (3.8.0)

| # | Case | Prompt | Expected behavior | Evidence |
|---|---|---|---|---|
| 17 | start -> Fix Issue | `start`, then `1` | Asks only for the issue; then `branchinfo`, `context`, `profile -Task fix`; Issue / Cause / Fix / Verification / Status | Live. Helper loads: automated "task routing: a fix loads only ..." |
| 18 | start -> Refactor | `start`, then `Refactor Existing Code` | Asks for the class or smell; measures the metric; reuses an existing abstraction | Live. Helper loads: automated "task routing: a refactor ..." |
| 19 | start -> New Development | `start`, then `3` | Section 0 (pick the PBI, or the a/b/c choice when tasks are in progress), full pipeline | Live |
| 20 | start -> Review | `start`, then `4` | Asks what to review; read-only report; no file edited | Live |
| 21 | Direct Sonar issue | A pasted SonarCloud finding, no `start` | "Mode: Fix Issue ..." in one line, no menu, no PBI or spec | Live |
| 22 | Direct PBI | `implement PBI 123`, no `start` | New Development, section 1 | Live |
| 23 | Regular Copilot agent | The same Sonar finding in the default agent | No Akzo workflow (nothing global installed); only the repository's own instruction files apply | Automated: "no globally applied instruction files shipped" and the isolation checks. Repository side: `guidance -Repo <id>` |
| 24 | Missing source file | A finding naming a class that does not exist | "Not found" with the nearest real files; nothing created | Automated: "missing source: ..." |
| 25 | Existing uncommitted changes | A fix in a file with local edits | Edits kept, fix applied on top, said in the report | Automated (the helper leaves the file as it was); agent behavior live |
| 26 | Unsupported IDE tools | Visual Studio 2022 17.14 (no custom agents), or no `askQuestions` | Numbered text choices; no claim that a tool ran | Live. Visual Studio 17.14.31 binaries checked: `copilot-instructions.md`, `.instructions.md` with `applyTo`, `.prompt.md` only |

### Developer-supplied regression case (live, not agent logic)

This case names a class from the developer's repository. It is a test prompt only; neither the agent nor the helper
reads this file.

| # | Case | Prompt | Expected behavior | Evidence |
|---|---|---|---|---|
| 27 | SonarCloud S1200 | "S1200 in CreatePaintSystemHandler.cs: class coupled to 32 types, maximum 30" | Fix Issue mode with the Refactor rules; no architecture documents read first; locates the handler and its tests; lists the referenced types; removes at least two by reusing existing services; no previously removed collaborator recreated (`git log --diff-filter=D`); no new collaborator only to move the count; creation behavior unchanged; build and focused tests run; Sonar "not verified" unless a Sonar source confirms it | Live, NOT VERIFIED (repository not on this machine) |

## Readable gates, approvals, and progress (3.10.0)
The helper side of each case is automated in `scripts\test.ps1` (workflow, `decide`, `planTasks`, `branchinfo`, `review`). Whether Copilot presents and follows them is a live check.

| # | Case | Prompt | Expected behavior | Evidence |
|---|---|---|---|---|
| 28 | Gate by name | A PBI in Gated mode, up to the gap map | Heading "Existing Code Analysis & Gap Assessment", what was produced, what to review, what follows; Approve / Request changes / Custom response as options; no "G2" needed | Live |
| 29 | Request changes | Choose Request changes with a correction | `decide ... -Decision changes`; the gap map is revised, set to Draft, and shown again; not approved | Automated (helper); agent live |
| 30 | Ambiguous reply | Answer a gate with "ok" or "continue" | Not approval; the same choice is asked again | Live |
| 31 | Task names | Progress after plan approval | "Starting <task title>: <what and why>", never "T2" alone; statuses Implemented - Verification Pending / Verified kept apart | Live |
| 32 | Repeated message after completion | "continue" after the handover | Nothing redone; Remaining and task statuses read back | Automated (statuses read back); agent live |
| 33 | Merge in progress | A repository in the middle of a merge | `branchinfo` reports the merge and conflicted files; the agent stops before editing | Automated (helper); agent live |
| 34 | Empty generated GraphQL client | A zero-byte `*.Generated.cs` | `review` error `generated-empty`; regenerated with the repository's command, reported as a baseline failure | Automated (helper); live with a real StrawberryShake repository NOT VERIFIED (none on this machine) |
| 35 | PBI 305912 regression scenario | Adaptation Imitation Request and Paint System on the DAB repository | Gates by name, CDMS reference compared before rules are copied, GraphQL client checked first | NOT VERIFIED: the DAB and CDMS repositories are not on this machine |
