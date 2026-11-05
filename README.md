# Akzo Master SDD Agent

**Akzo SDD Agent — Developed and maintained by Arun RG** · Version: see [VERSION](VERSION) and [CHANGELOG.md](CHANGELOG.md)

One GitHub Copilot custom agent, **`akzo-master-sdd`**, for spec-driven development in any registered repository. It discovers the repository's architecture, maps every requirement of a refined PBI (plus your supporting documents) to existing code as **EXISTING / REUSABLE / EXTEND / NEW / UNKNOWN**, writes `spec.md` and `plan.md`, implements test first, and validates build, tests, and analyzers. It stops for your approval after the gap map, the spec, and the plan. It runs in Copilot Chat in **VS Code** and **Visual Studio 2026** (18.5+ for user-level agents), and only when you select it. Nothing in the agent is tied to a particular project, framework, or organization: stack-specific rules apply only when the repository's architecture index detects that stack.

> **Version 4.2.4 RC.** Corporate readiness is **NOT VERIFIED**: see the [security controls and approval limits](#corporate-security-gate-g8-340). Native Visual Studio Chat selection controls and end-to-end implementation speed improvements are not certified. See the adjacent release notes for exact checks and blockers; machine-specific evaluation reports are not distributed.

### Focused maintenance and retrieval

Necessary finite decisions use the host's supported single/multi-select question
tool, evidence-backed recommendations and editable/custom answers. Approval is
never preselected. Widget shapes/navigation depend on the host. An optional
native Windows Forms wizard is installed under
`modules\interaction\scripts\select.ps1`; it is a modal fallback, **not native
Copilot Chat UI**. Without either UI use numbered choices and Cancel.
See [interaction protocol](copilot/modules/workflow/interactive-decisions.md).
The setup Browse button uses the Windows Shell Explorer-style folder picker;
PBI/supporting documents retain native multi-file dialogs.

The portable package is `Akzo-SDD-Agent-v4.2.4.zip`. Check the adjacent release
notes and SHA-256 for the exact archive and its validation results.

Agent maintenance uses targeted source reads, focused component tests and diff inspection;
application tests are not agent validation. Full release regression is a packaging gate,
not the default for every small edit. Analyzer/workflow changes also require relevant
semantic and integration checks. GUI/installer and integrity checks remain required for releases.

For several independent C# symbols, use
`arch -Repo <id> -Queries "OrderHandler;OrderValidator;OrderService"`.
This returns ordered query results from one content-validated semantic refresh and
one helper/analyzer launch (maximum eight nonempty, semicolon-separated queries).
`-Query` remains unchanged; do not combine it with `-Queries`. TypeScript currently
supports single `-Query` only and explicitly rejects `-Queries`.
Language routing for `arch`, `affected` and `review` now reads only workspace paths
and necessary language manifests, without redundant project-graph/framework/pattern
discovery. Complete `workset` architecture output remains available.
>
> **Known limitation:** The developer's authorization is stored in `%USERPROFILE%\.akzo-agent\authorizations.json`. Any process running as that user, including a model with file-edit or terminal tools, can write that file directly. The `authorize` command asks the IDE for confirmation, but the helper cannot tell a command from a direct file write, so the developer's approval is enforced by the IDE's prompts and the agent's instructions, and instructions alone do not enforce approval. Where approval must be enforced, an administrator places a `policy.json` that users cannot write, with `allowDeveloperAttestation` set to `false`: developer statements are then ignored and only listed repositories are processed. G8 reports a developer statement as NOT VERIFIED in every case.

## Four steps
1. **Install:** double-click **`Install-MasterAgent.cmd`** → *Add Repository…* (type, paste, or browse to your local clone; saved at once) → *Install / Upgrade*.
2. **Open** VS Code or Visual Studio 2026 (restart it after installing) and select **`akzo-master-sdd-v<version>`** (for example `akzo-master-sdd-v4.2.4`; the name shows the installed version) in the Copilot Chat agent picker.
3. **Type `Start Development`.** A Windows file dialog opens (it may appear behind the IDE): choose the refined PBI (`.md`, `.txt`, `.docx`; `.pdf` when `pdftotext` is installed). A second dialog lets you select any number of supporting documents at once (business rules, specs, API contracts, schemas, test cases, sample data, diagrams…); Cancel skips it.
4. **Review at three gates.** The agent stops after the **gap map** (what exists, what is reused, extended, or new), after the **spec**, and after the **plan**. Reply `approve` to continue, `approve all` to let it finish without further stops, or describe changes. After plan approval it implements, builds, tests, and reports.

Alternative to step 3: double-click **`Start-Development.cmd`** (same two dialogs), then type `start` in Copilot Chat (the launcher puts `start` on the clipboard). Add documents later with `attach <files> to <PBI>`.

| Launcher | What it does |
|----------|--------------|
| `Install-MasterAgent.cmd` | Resizable window: **Install / Upgrade**, **Repair**, **Verify Installation** (Agent Installation Status panel), **Uninstall**, and a repositories table with **Add / Edit / Remove / Open in Explorer / Validate / Refresh** |
| `Start-Development.cmd` | Dialogs for the PBI and supporting documents → queued in the inbox → tells you the next step |
| `Uninstall-MasterAgent.cmd` | Asks, then removes only installer-owned files (keeps repos.json, tasks, inbox, specs, knowledge, backups) |

Command-line equivalents (no window): `scripts\Install-MasterAgent.ps1 -Action Install|Repair|Verify|Uninstall -NoGui [-Repo <path>]`, or the engine `scripts\install.ps1` (`-DryRun`, `-Verify`, `-Uninstall`, `-AddRepo <path>`, `-CleanMemory`, `-ConfigureVSCode`, `-Target VSCode|VisualStudio`, `-VisualStudioAgentsDir`).

All launchers and command examples respect the effective PowerShell execution policy and required signing/organizational approvals. A blocked script needs the authorized approval process, never a bypass, policy change, or workaround for a declined host prompt.

## Chat commands
**Portable multi-repository work:** the package ships an empty registry and no application-specific profile
defaults. Open your application for dynamic discovery, or register additional/nested workspaces using the unchanged
setup interface. `workset` inspects every candidate; `scope` records confirmed roots/branches/files; `writecheck`
rejects unselected files, changed branches and path escapes. Any selected combination is supported. See
[portable workflow](copilot/modules/workflow/portable-development.md). Optional team profiles live in
`profiles-custom/profiles.json` and survive upgrades. Native selectable decisions are preferred, with numbered fallback.
New Chat does not reuse task approvals without explicit resume. Scope checks are helper-level controls, not global
editor hooks or human-authentication mechanisms.

`arch` dispatches to Roslyn for C# and to the workspace's installed TypeScript compiler for TS-only workspaces.
No compiler is downloaded during analysis. See [TypeScript analyzer](copilot/modules/analyzers/typescript/README.md)
for coverage and incremental limitations. Architecture and Sonar remain independent; neither substitutes for build,
tests or integration evidence.

**Internal agent maintenance:** requests to correct or upgrade the agent first identify the workspace role and verify
the agent source checkout. They do not require a routine PBI ID or run application tests. If source is unavailable,
the agent reports that once and makes no code changes. Existing application edits are inspected read-only, never
discarded automatically. These are agent instructions, not a deterministic edit-blocking mechanism.

For policy-only maintenance, run `powershell -NoProfile -File scripts\test.ps1 -StaticOnly` from the agent source
checkout. Runtime edits need focused agent checks for the affected component. Application analysis reuses current
semantic indexes and real dependency evidence; verification starts with relevant projects and tests.
Record latency and actual model/tool/token telemetry, including its source and cache state, using
[the benchmark template](benchmark/results-template.csv). Keep proxy fields separate; unavailable metrics and live
IDE behavior are NOT VERIFIED, not zero. A source version bump does not install or package the upgrade.

| You type | Mode | What happens |
|----------|------|--------------|
| `Start Development`, `New Development`, `Start Implementation` | Gated (default) | Always a **fresh task**: dialogs for PBI + supporting documents, branch decision, then the run with stops at G2 (gap map), G3 (spec), G4 (plan). Never resumes the previous PBI |
| `start` | Routed from context | Takes an explicitly queued PBI or the unambiguous active task; otherwise asks "What would you like to work on?" in free text |
| `develop 305912` | Gated | Same, for a PBI already in the tasks folder |
| `implement PBI 305912` | Gated | Finds the PBI (task folder or inbox), uses the open workspace as the repository when it is registered, loads repository memory, then as `develop` |
| `implement PBI 305912 in Auto Mode` | Auto | Analysis, gap map, spec and plan; always stops for explicit approval of the concrete plan and contract/validation readiness. After approval continues implementation, generation if required, tests, analyzers/Sonar and handover. Also stops for business ambiguity, destructive/production actions, permission changes, new dependencies and out-of-scope work |
| `develop 305912 end to end` | Auto | The earlier name for Auto Mode |
| `plan 305912` | Plan | Gap map, spec, plan, and consistency gate; stops before any code |
| `attach C:\docs\notes.docx to 305912` | — | Adds supporting documents to an existing task |
| `review and align 305912` | Align | Code exists: compares it with siblings and the gap map, fixes deviations, validates |
| `debug <symptom>` | Debug | Root-cause fix with a regression test |
| `modify 305912` | Modify | Snapshots spec, plan, and statuses into the task history, takes in the change, and reopens the gates for the changed parts |
| `resume 305912` | Resume | Reuses valid same-task decisions and continues from Remaining; an old waived plan still needs concrete plan approval before application writes |
| `Implement this requirement` | Gated / Auto | The requirement becomes the task's PBI; the repository profile is selected first, then the full pipeline in the mode in force |
| `Fix PR comments` | — | Verifies each comment against the code before changing anything, fixes what the code proves right, reruns build, tests, Sonar sources, and the pre-PR review, then drafts a short reply per comment |
| `review ... before changing anything`, `plan first` | — | Analysis only: issues, proposed file-by-file changes, business-rule impact, regression risk, test and Sonar plan; stops before any code change |
| `Review changes` | — | Read-only: pre-PR review of the branch, the diff, architecture, validation, API compatibility, tests, Sonar; reports Ready / Ready with Warnings / Not Ready |
| `Run tests` | — | The detected profile's test command (never another repository's solution) |

## Optional repository profiles
Portable defaults contain only shared source-grounding and review policies. Architecture comes from actual workspace
and semantic evidence, never a distributed repository-name map. Optional team definitions live in
`profiles-custom/profiles.json`; their solution/marker matching and on-demand guide loading remain compatible.
Generic technology guides are optional references, not application blueprints.
- Isolation: the other profile's files are returned as `neverLoad`, and `guard -Repo <id>` refuses a `dotnet` command that names a solution not in that repository.
- `review` checks applicable source patterns, explicit team rules and `git diff --check`. TypeScript compiler findings
  are independent of Angular builds, tests and Sonar.
- Custom profile definitions/guides survive upgrades and remain outside Copilot's global discovery folders.

## Fast development and review intelligence (3.7.0)
- **Only the files a request needs:** `profile -Repo <id> -Query "<request>"` loads shared and explicitly matched team rules; irrelevant guides are deferred. Detection is cached until roots, HEAD, working inputs or profile definitions change.
- **Exact names first:** `context -Query "<ExactTypeOrFile>"` answers with `exact: true`, the file, its tests, and its direct callers. Free-text ranking returns the same results, 22-34% faster in the benchmark.
- **Staged tests:** `affected` selects affected builds, focused tests and dependent regressions independently per repository. Full suites require build-wide inputs, demonstrated integration risk or repository policy. Unknown TS focused selectors are not silently replaced by full tests.
- **Business rule branch coverage** (new shared skill): every approved rule is checked path by path (Yes/No, required fields, duplicates, state transitions, side effects, failures, transaction boundaries) against the code and tests; one implemented branch is not "existing".
- **Validation ownership and abstraction review** in the source-grounded skill, twelve reusable **review categories** and a disposition per PR comment in the pre-PR review skill, and a new `single-use-abstraction` review warning for a new helper/collaborator-style type with one consumer or none.
- **Rule ownership:** trace whether backend, plugin, workflow or UI already enforces a rule; preserve proven ownership and port behavior only within approved repository scope.
- **Review-only or plan-first** requests stop after the analysis, with the proposed file-by-file changes, impact, risks, and test plan. Authorized implementation runs without extra prompts.
- Measured helper timings against 3.6.0: [benchmark/perf-3.7.0.md](benchmark/perf-3.7.0.md) (`scripts\perf-bench.ps1`).

## Task routing: small work stays small (3.8.0)
- **Natural conversation:** give informal free-text instructions, errors, PR comments, or a PBI; no routine multiple-choice picker, numbered menu, or approval loop. `start` uses established context or asks one short question. Source evidence and valid prior approved decisions are consulted before any genuinely unresolved question. A PBI number needs no title or fix/review question. Ordinary tasks need no approval reference or classification; explicit PBI gates, policy restrictions, and host prompts still apply.
- **Fix Issue** runs understand -> inspect -> apply -> review -> test -> report, with actual build and quality checks after edits, and reports Issue / Cause / Fix / Verification / Status. No PBI, spec, plan, planning document, or routine technical approvals. **Refactor** measures the smell, reuses existing abstractions, and never adds a single-use collaborator only to move a metric.
- **Only what the mode needs:** `profile -Task fix` loads the source-grounding skill and the Sonar rules (2 files instead of 7-8); `-Task refactor` adds the guides the smell triggers; New Development and Review keep the full lazy-loading set.
- **Why Copilot reads documents you did not ask for:** `guidance -Repo <id>` lists each repository instruction file, when the IDE adds it (every request, matching files, by description, when invoked), and every document it tells Copilot to read, marking unconditional reads with file and line. The agent no longer reads `copilot-instructions.md`/`AGENTS.md` itself (the IDE already adds them).

**Scoping repository instructions** (VS Code 1.143 / Copilot Chat 0.71 defaults, read from the installed product): `.github/copilot-instructions.md`, a root `AGENTS.md` or `CLAUDE.md`, and any `.instructions.md` with `applyTo: '**'` go into every request of every agent, the regular one included. Linked documents are not attached automatically (`chat.includeReferencedInstructions` is off), but a line such as "always read X before any task" makes the model read them. Keep those files to short rules for all tasks; move each document rule into `.github/instructions/<topic>.instructions.md` with an `applyTo` glob for the files it concerns, or into a skill with a description, worded "read X when <task or files>". This agent cannot unload those files; scoping them is the repository team's change. Visual Studio 2022 17.14 reads `copilot-instructions.md` and `.instructions.md` files but has no custom agents or skills.

## Change risk, test trace, and PR text (3.11.0)
- **Change risk:** `review` reports per-file reasons. Verify high-risk dependents/integration; widen full suites only for demonstrated risk, build-wide inputs or repository policy.
- **Trace:** `trace -Id <PBI>` checks every acceptance criterion against the tests the plan names for it and their TRX results: COVERED, FAILING, NOT RUN, MISSING. G5 waits while one is MISSING or FAILING.
- **PR text:** `prtext -Id <PBI>` writes the pull request description to the task's evidence folder; you paste it.
- **Your own review rules:** `%USERPROFILE%\.akzo-agent\profiles-custom\review-rules.json`, a list of `{ id, profile, pathGlob, regex, severity, message }`, is checked by `review` on changed lines. The agent proposes a rule for a recurring PR comment; you decide whether to add it.
- **Coverage threshold:** `"quality": { "coverage": <percent> }` per repository in `repos.json`, copied from the SonarCloud gate; 85% (a provisional objective) when it is not set.

## Lessons from PR reviews (3.12.0)
- **Fix PR comments** records each verified comment as a lesson (`lesson -Action add`): what was wrong, why, the fix, and the PR reference. Comments that say the same thing become one lesson.
- **You approve** a reusable lesson once (`lesson -Action approve`, only when you say so). From then on `task` puts it into every new plan of that repository, and `review` reports a repeat as an error naming the existing component to reuse.
- Unverified feedback, business clarifications, and contradicting comments are kept but never become rules. Lessons stay in their repository: `%USERPROFILE%\.akzo-agent\learning\<repo-id>.json`.
- `lesson -Action report` shows what the lessons caught and what was fixed before the PR, or "NOT YET MEASURABLE".
- **Fresh evidence:** `trace` reports whether the test results are older than the code, and a readiness per acceptance criterion; old results never verify a change.

## Fixes and changed-file analysis (4.0.0)
- **One call to start a fix:** `issue -Repo <id> -Query "<ClassName>" -Text "<rule or error>"` returns the branch and your uncommitted edits, the profile files to read, and the located class with its tests and callers. The fix follows the closest existing implementation, and the report names it.
- **Every changed C# file gets a status** in `review`: ANALYZED (compiled in a logged build after its last change; its analyzer warnings are listed, changed lines first), EXCLUDED (generated code, by the compiler's own rules), or NOT VERIFIED (never treated as clean). The build commands `affected` prints write the logs `review` reads.
- **SonarQube for IDE:** `sonar -Repo <id>` names the installed Visual Studio or VS Code extension and its version, and compares a Connected Mode binding shared in the repository with the project key. The agent reads IDE diagnostics only through the IDE's own tools, and says so when it cannot.
- **Rules and coverage:** `sonar -Check rule -Key <rule>` says whether the rule is active in the project's quality profile, with its parameters. `coverageImport` shows when the pipeline produces a coverage format Sonar does not read, so you fix the import instead of adding tests. `coverage` reads OpenCover too.

## Architecture compliance and a lighter agent (4.1.0)
- **Every change follows the repository's own architecture:** fixes, refactoring, PR comments, tests, and new features alike. `issue` and `profile` return the conventions (which project references which, and the folders where handlers, validators, services, and the rest live). `review` warns when a new file lands outside its role's folders (`architecture:placement`) or a new project reference points up the dependency direction (`architecture:dependency`).
- **A smaller always-on agent file:** the detailed PBI pipeline and the engineering skills are reference files the agent reads only for New Development (`modules\workflow\`). Fixes and reviews no longer carry them with every request.
- **Faster helper calls:** each command is compiled only when it runs, and `branchinfo` and `issue` start fewer git processes.

## Impact across repositories (4.1.0)
- Each link is CONFIRMED (the matching line shows the actual use: the HTTP call, the registration, the implemented interface) or CANDIDATE (the same name only).
- `impact -Query "<business operation>"` looks at every registered repository (API, UI, legacy platform). It lists each repository's matching components and the links between them: a route to the UI service that calls it, an entity's logical name to the plugins, web resources, and step registrations that use it, each with `path:line`.
- A plugin counts as registered only when a registration file in a repository names it. A repository without a link is reported as "not shown affected", not as unaffected. Repositories explicitly blocked by policy are not read; missing approval records do not block investigation.

## Architecture intelligence
- **Architecture first for every code change:** identify the active solution and affected projects, then refresh `arch -Repo <id> -Query "<work's words>"` before PBI work, direct fixes, refactoring, PR corrections, and test edits. Source-verify the closest implementation and a compact internal execution map of relevant entry point, command/query, handler, validator, service/interface, repository, mappings, DI, and tests; fixes create no planning document. Roslyn and MSBuild return existing types with:
  - their `path:line`, members, DI registrations, callers, and tests;
  - the sibling of the same kind to follow, and the reusable abstractions they depend on;
  - the expected impact (projects, dependents, call sites).
  The agent uses it before the gap map and before changing shared code.
- **Honest coverage:** each project reports the target framework it declares and the one the load resolved, and whether it was analyzed semantically, loaded without its framework references (`partial`), or only parsed because MSBuild could not load it (`syntax`, with the reason). The agent never claims callers, DI registrations, or tests it could not resolve.
- **Observed, not recommended:** patterns (CQRS handlers, validators, repositories, DI, GraphQL, Azure Functions, controllers, Dataverse plugins, Clean Architecture layering) and conventions come with `path:line` evidence.
- **Dual local analyzer hosts:** `net8.0` runs with `dotnet` for SDK projects; `net472` runs on installed .NET Framework for compatible Visual Studio MSBuild (18+). Both use Roslyn **5.3.0** and MSBuildLocator **1.11.2**. The chosen installed toolset owns its runtime dependency closure: matching dependencies are staged only in a local runtime cache, never patched into shipped hosts or Visual Studio. Runtime cache fingerprints use **SHA-256 content hashes** of the toolset dependency closure and relevant analyzer/host inputs, so an in-place toolset update invalidates evidence.
- **Fast and local:** the index and runtime cache live under `%USERPROFILE%\.akzo-agent\maps\<repo-id>\roslyn`, never as source in the target repository. Only changed documents and affected projects are refreshed; do not force full scans for unchanged evidence. No install/runtime download or network probe is needed. Missing compatible hosts/toolsets fall back to bounded source reads with unresolved semantic links explicitly UNVERIFIED, never a compiler-grade PASS.
- **Evidence-driven handover:** actual final build, required tests, Sonar/analyzer source, changed-line coverage, layer/dependency direction, DI lifetimes/reachability, and complete diff verification are reported with decisive `path:line` references, reused symbols, necessary new-class justification, and exact blockers. No AI-only PASS, invented GraphQL/Dataverse contracts, or hand-edited generated output. Repository memory/profile isolation remains unchanged; UI work requires an actual authorized UI repository, not an inferred UI profile.

## SonarQube for IDE in Visual Studio
- **The agent finds the Sonar issues itself:** "fix the Sonar issues in OrderService.cs" is enough; you no longer give the rule id. `sonar -Repo <id> -Check issues` (`get_sonar_issues`) returns each finding's rule, message, file, line, column, severity, and source.
  - It reads Visual Studio's Error List, through the IDE's automation interface while Visual Studio has the repository's solution open; it also reads the last logged build and the Sonar server.
  - A finding several sources report appears once. Its rule id comes from the build or the server, because the IDE's interface does not expose it.
  - Each finding names the method or type that holds it (from the `arch` index) and links the rule's documentation.
- **Files open and analyze automatically:** with `-Update` the agent opens the files in Visual Studio, saves them, and waits up to 30 seconds for the analysis. Your active document stays in front and your Error List filters stay as they were. A file counts as analyzed only when its findings changed after that; an opened file alone is not a Sonar result.
- **During development:** each implementation stage, each fix, and the pre-PR review check the changed files this way. Each finding gets at most three fix rounds, and a fix counts only when the finding is gone after a new analysis.
- **Limits:**
  - Findings shown only in the SonarQube Report window cannot be read; there is no interface for it.
  - With several Visual Studio instances of one version open, the helper reaches the one Windows registered first.
  - In VS Code the agent uses the problems tool and SonarQube for IDE's own tools.
- **A failing tool is not a cancellation:** the agent fixes the cause or uses the next source, retries a command at most twice, then names the blocker.

## How a PBI is analyzed
1. **Inputs:** the refined PBI is authoritative. Supporting documents are copied to the task (`supporting\`, originals untouched; duplicates detected; same names never overwritten) and listed in `inputs.json` with hash, type, guessed role (correct it with `role`), status, and source path. `.docx`, `.pdf` (with `pdftotext`), and `.xlsx` are converted once into cached text keyed by content hash; images and unknown formats are listed, never guessed at. The agent reads only the sections it needs.
2. **Architecture knowledge:** per-repository indexes identify stack, layers, roles, symbols, and affected projects; current content fingerprints detect committed and uncommitted changes, not just HEAD moves. Incremental Roslyn refresh and bounded source reads verify the relevant execution path, alongside current evidence-backed memory.
3. **Gap map (G2):** every requirement gets an id (REQ-n), the documents that support or contradict it, a recorded multi-angle code search, and a class: EXISTING, REUSABLE, EXTEND, NEW (only after the full search), or UNKNOWN (not enough evidence), with `file:line` evidence and an evidence level (source, test, run). Conflicts between documents become questions, never silent choices.
4. **Spec (G3):** ambiguity scan, at most 5 questions, measurable acceptance criteria linked to requirements, existing behavior kept as "no change", entities and state transitions.
5. **Plan (G4):** tasks with requirement ids and a per-file action (reuse / modify / new) following the discovered folders and naming; a "reused without change" list; a consistency gate that blocks re-implementing anything classified EXISTING, REUSABLE, or EXTEND.
6. **Implement and validate:** test first; build → test → analyzers/Sonar → fix until 0 build errors, 0 newly failing tests, 0 new issues in changed files; never suppressions or skipped tests.
6a. **SonarQube and code rules:** code is written to a built-in rule set (complexity, unused code, error handling, literals, security, resources, async) and checked against the project's Sonar quality gate using the strongest source available: SonarQube MCP tools in chat, read-only server queries through the helper (gate, issues, hotspots, coverage, duplication, rule details; token from `SONAR_TOKEN`, never shown), Sonar analyzers in the build, or SonarQube for IDE (Visual Studio's Error List, read with `sonar -Check issues`). Coverage of changed lines is measured from the repository's own Cobertura or LCOV reports. Without a server it uses stated defaults (0 new issues, hotspots listed for review, changed-line coverage ≥ 85% provisionally, new duplication ≤ 3%). It never uploads an analysis unless asked. Setup: [installation-guide.html#sonar](installation-guide.html#sonar).
7. **Handover (G5):** requirement → class → acceptance criterion → evidence table, baseline vs final counts, open questions, proposed commit message. It never commits or pushes.

## Each PBI is its own task (3.5.0)
- Task folder `<tasks>\<repo-id>\<PBI-ID>\` and a spec folder unique per work item: `<specsDir>\<id>-<title>\` (e.g. `300186-create-order-export\spec.md`). Approvals, gate statuses, plan progress, and completion belong to that task only; a folder that belongs to another PBI is never reused.
- Before any repository edit, the agent confirms repository, branch, HEAD, and uncommitted changes. It reuses a valid explicit branch/base decision or asks once in free text which branch to use, recommending a feature branch when needed. Creation/base and switching with uncommitted changes require your agreement; no routine branch menu, stash, reset, or discarded changes.
- A new PBI reuses architecture memory (after checking its evidence is current), not another PBI's progress; earlier tasks that look like the same feature are listed so the gap map checks whether the requirement is already satisfied instead of reimplementing it.

## Repository memory (3.4.0)
Per repository, under `%USERPROFILE%\.akzo-agent\maps\<repo-id>\`, never mixed between repositories and never uploaded:
- `architecture.json`, `component-index.tsv`, `symbols.tsv`: languages, frameworks (from manifests), inferred patterns, files by role, and the types, methods, functions, routes, and imports of C#, TypeScript/JavaScript, Python, Java/Kotlin, and Go (regex extraction, not a parser: good for finding and ranking, never proof).
- Every file is fingerprinted by content (git blob id), so committed and uncommitted edits, staged and untracked files, deletions, and renames are noticed on the next call and only the changed files are re-read.
- `facts.json`: verified facts (end-to-end patterns, reusable components, validation and testing conventions, integrations, decisions, commands, pitfalls), each with `path:line` evidence and the evidence's content fingerprint. A fact turns **stale** when its evidence changes (and so do facts that depend on it), and **expires** when the evidence file is gone or the policy's retention period passes. The agent must revalidate a stale fact before using it. Values that look like secrets are refused.
- `context -Query "<terms>" [-Mode compact|balanced|deep]`: ranked files with key symbols, linked tests, and matching facts within a size budget (balanced by default; set `retrieval.mode` and `retrieval.budgets` in `repos.json`). Ranked by deterministic matching, not proof: the agent reads the cited lines.
- Unreadable memory is set aside as `*.corrupt-<time>` and rebuilt. `purge -Repo <id> -Confirmed` deletes a repository's memory.

## Corporate security gate (G8, 3.4.0)
Mandatory in every mode, including Auto Mode; never waived. Controls and limitations are listed below. Task-specific evidence and outstanding approvals belong in the task's generated security report, not a packaged developer-machine report.
- **Preflight (technical):** ordinary tasks do not require an approval reference or classification prompt. Missing approval records return `authorization.status: NOT_REQUIRED` and processing continues. An administrator policy (`%ProgramData%\AkzoAgent\policy.json`, or `policy.json` in the Akzo folder) can still explicitly restrict processing; an unreadable or forbidding policy returns `BLOCKED_BY_POLICY`. Restricted data needs an administrator policy. Optional developer statements (`authorize`) remain supported as evidence and are reported as NOT VERIFIED, never as corporate approval.
- **Command guard:** the agent checks every non-helper terminal command with `guard`: ALLOW, NEEDS_APPROVAL (git commit/push, dependency installs, deployments, database changes, destructive deletes, analysis uploads), or BLOCK (external transfer, remote code execution, security-tool tampering, execution-policy and registry changes, elevation, credential access). A blocked command is never run and no approval releases it. Checks are logged to the task's evidence with secrets redacted. The guard is run by the agent: Copilot offers no hook that forces it, so the log shows what the agent reported (see the report's limitations).
- **Network:** the helper's only network call is the read-only Sonar query, and only to a host the policy or authorization lists.
- **Data protection:** secret-looking values are redacted from logs, notes, and output; memory and task folders are restricted to the owner, SYSTEM, and Administrators; retention and `memory: disabled` come from the policy.
- **Gate (`security -Id <PBI>`):** 13 controls with PASS / FAIL / NOT VERIFIED / NOT APPLICABLE and the evidence for each, written to `<task>\evidence\corporate-security-report.html`. FAIL blocks the handover; NOT VERIFIED allows DONE_WITH_CONCERNS at best; only PASS allows DONE. Automated verification is never corporate approval.
- **Release integrity:** `scripts\make-release.ps1` builds the zip with `release-manifest.json` (SHA-256 of every file) and a `.sha256` file; `install.ps1` refuses a package whose files differ. Hashes show the package is unchanged, not who made or approved it.

**Approval limits:** the gates are enforced by the agent's instructions and by the statuses recorded in spec.md and plan.md (the helper reports them on every call, so a resumed session respects them). Copilot offers no hook that blocks file edits, so the IDE cannot technically stop a model error or an explicit instruction from skipping a gate.

## Where files go
| What | Where |
|------|-------|
| Chosen PBI and supporting documents (before intake) | `%USERPROFILE%\.akzo-agent\inbox\<name>\` (`refined-pbi.md`, `source\`, `supporting\`) |
| Task workspace | `%USERPROFILE%\.akzo-agent\tasks\<repo-id>\<PBI-ID>\` (`refined-pbi.md`, `supporting\`, `inputs.json`, `.extract\`, `evidence\`) |
| spec.md, plan.md | `<repo>\<specsDir>\<FeatureName>\` when the repo has a spec folder, otherwise in the task workspace |
| Project knowledge | `%USERPROFILE%\.akzo-agent\maps\<repo-id>.md` (verified facts) and `maps\<repo-id>\architecture.json`, `component-index.tsv` |
| Code changes | your repository, uncommitted, visible in Git Changes |
| Registry, backups | `%USERPROFILE%\.akzo-agent\` |

## Upgrading from 3.3.0 or earlier
Run **Install / Upgrade** (or `install.ps1`) from the new package; nothing else is needed for tasks, `repos.json`, inputs, or specs. Two things change, both by design:
1. **No repository approval setup prompt.** Registered repositories start ordinary tasks and architecture discovery without an approval record. Existing statements and administrator policies are retained; explicit policy restrictions still apply. A PBI number without a title resumes saved context or defaults to New Development; explicit fix or review wording determines the mode without asking.
2. **Memory is rebuilt once.** The old `architecture.json` is replaced by the new format on first use; your notes in `maps\<repo-id>.md` are kept and shown as unverified hints. Roll back by installing the previous package's zip over this one (backups of replaced files are in `%USERPROFILE%\.akzo-agent\backups\`).

## What install, upgrade, and repair do
- Copies the agent to `%USERPROFILE%\.copilot\agents` (VS Code) and `%USERPROFILE%\.github\agents` (Visual Studio 2026), and the helper and templates to `%USERPROFILE%\.akzo-agent\modules`.
- **Idempotent:** unchanged files are skipped; a rerun never duplicates anything. **Repair** restores missing or modified files and cleans leaked Akzo text from Copilot memory.
- **Upgrade/migration:** files from earlier versions that are no longer shipped are removed via the install manifest; an older `akzo-sdd` agent found without a manifest entry is removed too (only if it is an Akzo agent file). Existing tasks keep working: their manifest is built on the next `task` call.
- **Backups and rollback:** every file replaced or removed is first copied to `%USERPROFILE%\.akzo-agent\backups\<timestamp>\` (deep paths listed in `index.txt`). If a write fails, every file changed by that run is restored.
- **Repositories:** *Add Repository…* (or `-AddRepo`; `-RegistryOnly` skips the install; `-EditRepo`, `-RemoveRepo`, `-ValidateRepo`, `-ListRepos`) registers a folder in `repos.json` as given (backed up first; a folder that is not a Git clone only with a warning; never the same folder twice). Remove deletes only the registration; editing a path or removing withdraws the authorization recorded for that id. It uses an existing spec folder (`openspec/changes`, `src/.github/specs`, `.github/specs`, `docs/specs`, `specs`), and builds its first architecture index. Nothing is written into your repositories by the installer.
- **VS Code (optional, on by default in the window):** a marked settings block auto-approves only the helper's own commands (a `;` is allowed only inside a quoted path list), grants read access to the Akzo folders, and raises the agent step limit to 400.
- `Verify` also warns when Visual Studio 2026 18.5+ (needed for user-level agents) is not installed.

## Other agents keep their normal behavior
The agent's rules live only in its agent file. Nothing is written to `AGENTS.md`, `.github/copilot-instructions.md`, `.github/instructions`, prompt files, or skills: Copilot applies those to **every** agent. If another agent still behaves like the Master agent: (1) **Copilot memory** — VS Code loads the first 200 lines of user memory into every agent; **Repair** (`-CleanMemory`) removes memory files that mention Akzo after a backup, `Verify` reports them as `LEAK`; (2) **same chat** — switching agents keeps the history, start a new chat; (3) **leftover agent files** — `Verify` reports them, Install migrates them.

## Develop and test this package
- Contract/validation preflight uses current indexed GraphQL schema/operation/fragment declarations and bounded source reads, plus the affected project's existing validators, async execution/DI and error-response contracts. Every implementation plan carries section 1b readiness and test coverage; direct fixes use compact chat readiness. Explicit concrete-plan approval is required even in Auto Mode. `task` reports `implementationReadiness`; `decide` refuses plan approval for missing/invalid evidence rows or planned work without task references. These are recorded-evidence checks, not a GraphQL semantic validator, human-approval authentication or an editor-write lock.
- `scripts\test-contract-readiness.ps1` verifies declaration lookup (including large schemas), warm/incremental reuse, readiness refusal without side effects, explicit plan decisions, legacy Auto Mode handling, REST and non-.NET applicability in isolated fixtures. It is also run by the full agent suite.
- `scripts\build-analyzer.ps1` — builds both analyzer hosts from `src\ArchitectureAnalyzer` into `copilot\modules\analyzers\architecture` and records source/bundle hashes. It needs the .NET SDK and approved dependencies available in the local package cache for an offline build; installation and runtime staging download nothing. Missing packages are a blocker, not permission to contact an unapproved feed. `make-release.ps1` refuses a package whose analyzer is not the build of the current source.
- `scripts\make-release.ps1` — builds `Akzo-Agent-<version>.zip` with `release-manifest.json` and a `.sha256` file. `scripts\ab-bench.ps1` — interleaved timing of up to three helper versions on one repository (results in `benchmark\interleaved-3.4.1.md`). `scripts\benchmark.ps1` — timing of the previous package against this one on a generated repository (results in `benchmark\results-3.4.1.md`; single-run cold and warm figures are superseded by the interleaved ones; model tokens and Copilot interactions are not measurable here).
- `scripts\test.ps1` — 449 checks in a temporary profile (repository memory on C#, Angular, and Python fixtures, incremental indexing, facts, retrieval, G8 preflight, command guard, scanning, policy, purge, release integrity, Sonar against a local stand-in server, and changed-line coverage included): static agent checks (incl. project-agnostic wording, gates, gap map), install, upgrade/migration, rerun, repair, rollback, AddRepo with first discovery, repository add/edit/remove/validate and installation-status checks, memory-leak cleanup, VS Code settings and auto-approve rule, intake, `pick` with supporting documents, `attach`, `role`, manifest, duplicate/missing/unsupported/second-primary detection, `.docx`/`.xlsx` extraction and cache reuse, change detection, interrupted-processing recovery, architecture index (roles, refresh on new commit, per-repository isolation), launchers, uninstall. Never touches your real profile.
- `scripts\test-gui.ps1` — drives the real windows through the `.cmd` launchers (PBI dialog, multi-select supporting dialog, setup window, uninstall confirmation) in a temporary profile. Needs a desktop session.
- `scripts\test-ide.ps1` — starts Visual Studio 2022 or 2026 with a temporary solution and checks `sonar -Check issues -Update` against its real Error List: opening, analysis, rule ids from the build, your filters and active document kept, no reopening, and validation after a fix. Needs no other Visual Studio running; closes the instance it started.

## Ownership and licensing
- Original implementation by Arun RG. No third-party code, prompts, or documentation are bundled; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
- License: **not yet selected.** It will be chosen once ownership and organizational requirements are confirmed. Until then, no license is granted.
