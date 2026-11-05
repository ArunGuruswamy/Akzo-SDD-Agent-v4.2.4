# Portable multi-repository development

## Intake and isolation

Determine mode from user intent, not the open solution. Agent Maintenance modifies only identified SDD source;
application repositories are read-only references. Missing source is reported once, then maintenance stops.
Application Development may modify only explicitly selected Git roots and approved files/branches.

`workset -Query "<requirement>"` examines the active application and registered workspaces independently. An empty
registry does not prevent read-only active-workspace analysis. Setup continues to register additional repositories.
Classify every returned candidate with affected workflows and source evidence; unavailable repositories remain UNKNOWN.
No match is not proof of no dependency. Use `impact` only when cross-repository links are needed; its name-based links
are retrieval evidence, not cross-repository compiler calls.

Use native multi-select for repositories and single-select for existing/new PBI, approach, branch, business decisions,
implementation approval and validation options when the host supports them. Otherwise use numbered choices.
Inspect the host's actual question schema; do not claim a particular widget exists. Follow
`interactive-decisions.md`: evidence-led safe recommendations, custom answers, no
preselected approval, cancellation without writes and same-task continuation.
Ask only decisions the user must make.

New Chat starts without selected task, branch decisions or approvals. Repository memory/indexes are reusable only
while their version/root/input fingerprints remain valid. Explicit `workset -Id <task> -Resume` loads that task;
never infer resume from a recent-task file or auto-populate another conversation's scope.

## Evidence and coordinated plan

Before any selected application's implementation plan, apply S7's GraphQL preflight and S5's validation discovery
independently per affected project. Do not infer GraphQL or FluentValidation from repository names. REST/API contracts
and Angular reactive forms retain their own conventions and error responses; frontend checks never replace server validation.
Each repository's plan readiness rows cite relevant indexed schema/operation spans, validators/rules, DI/execution,
affected contracts and tests. A cross-repository contract needs evidence from both producer and consumer.
Explicit approval of the concrete plan is required before application writes, including Auto Mode. Planned schema/client
regeneration and validator wiring tasks precede their consumers; unresolved material incompatibilities block dependent tasks.

Run `arch -Repo <id> -Query "<relevant symbols>"` independently for affected workspaces. C# uses Roslyn/MSBuild.
Angular/TypeScript uses the target's installed compiler and real tsconfig/import resolution, not regex-only symbols.
Unresolved frameworks, templates, dynamic providers and HTTP URL expressions are limitations, not passed checks.
Mixed-language roots currently require a separately registered TS workspace. Project references establish dependency
direction; project names alone do not establish an architectural layer.

Trace relevant endpoints, handlers/services, registrations (including assembly scanning), validators, data access,
contracts, clients and tests. Compare reference behavior but follow each target's own closest implementation.
Plan a requirement/repository/file matrix with reuse/modify/new actions, request/response fields, validation ownership,
dependency order and per-repository build/test/Sonar commands. Mark integration links confirmed only with actual
contract/call evidence. Do not translate missing architecture into guessed framework-specific code.

Select/create branches separately using existing `branchinfo`, `branchcreate` and `branchuse` commands; creation/switching
requires user choice and preserves dirty work. Never commit, merge, push or deploy automatically.

## Explicit scope checks

After the user confirms repositories, current branches, files and mode:

```text
scope -Id <task> -Repo "<id>;<id>" -File "<id>=relative-path;<id>=relative-path" -Confirmed -Query "<requirement>"
writecheck -Id <task> -Repo <id> -File <relative-path> -Resume
```

Use `-AllowDirty` only after explicit confirmation to preserve the listed existing changes. New/unlisted files require
scope reconfirmation. Branch/HEAD changes and remapped roots invalidate writes. File escapes, links, .git and unselected
repositories are rejected. Maintenance scope uses `-OperatingMode maintenance -Path <identified-source>` and
`agent-source=<file>` mappings; maintenance write checks use the same mode.

`-Resume` is an explicit task binding, not authentication of a human. The helper cannot intercept arbitrary editor
writes or authenticate model-supplied approvals; these remain host/instruction boundaries. State stays outside Git.

## Execute and verify

Once implementation is requested and approved, continue beyond the plan. Apply contracts/dependencies first, then
implement backend/client changes and focused tests. Check scope before every write, including generated outputs.
Use repository-specific commands and existing code generators; do not hand-edit generated files.

Build/test each selected repository independently. Widen to dependent tests/integration checks only for actual risk;
full suites are for build-wide changes or repository policy, never unrelated maintenance. Run Sonar separately using
each repository's configured sources, credentials and approvals. An architecture result is not a Sonar, build or test
result. Unavailable Sonar/integration infrastructure is NOT VERIFIED with its exact blocker.

Refresh changed projects and transitive consumers before final review. Cache identity includes root/workspace/schema
and analyzer/compiler inputs; dependency signature changes rebind consumers. TypeScript currently revalidates all
programs on changed inputs rather than claiming compiler-watch incremental speed.

Report selected/unselected preservation, actual diff, per-repository builds/tests/Sonar, integration evidence and
remaining deficiencies. Record elapsed cold/warm/incremental/query times and output bytes separately from measured
model/tool/token counts. Unavailable telemetry stays unknown; never infer counts from output size or claim 10/10.
