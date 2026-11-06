# SDD Agent 4.2.4 RC

## Changes
- **Mechanical GraphQL validation**: `graphql -Repo <id> [-Query <terms>]` parses the
  repository's SDL and operation documents per scope. It validates fields,
  arguments, input objects, enum values, variable nullability, fragments and
  leaf/composite selections with `file:line` evidence, and compares operation
  names with StrawberryShake-generated interfaces. Results are cached per scope
  by content.
- **G4 plan approval** reruns that validation when the plan marks the GraphQL
  schema VERIFIED. Errors return `GRAPHQL_BLOCKED` and record nothing.
- **FluentValidation (Roslyn)**: registration, invocation, async rules, and
  async rules reached through a synchronous `Validate` (a run-time exception).
- **Incremental analysis**: an edit confined to member bodies no longer reloads
  dependent projects; declaration changes still do.
- **Concurrency**: memory and task writes use unique temporary files, an atomic
  replace and per-file named mutexes. Concurrent chats or processes no longer
  lose updates or leave a missing file.
- **Recovery**: an interrupted document extraction is rebuilt from its source;
  a legacy `.tmp` sidecar is removed only after the content-addressed cache is
  atomically restored.
- **Repository purge**: confirmation gates deletion; default purge removes only
  the selected repository's memory. Task removal remains opt-in and scoped.
- **Profile upgrade**: edited shipped profile files are backed up and restored;
  `profiles-custom` remains untouched. Regression output is whitespace-normalized
  so Windows console wrapping does not hide the warning.
- **Agent efficiency**: related C# symbols use one batched `arch -Queries` call;
  same-revision evidence and solution discovery are reused. Token savings are
  not claimed without host telemetry.
- **Interaction**: optional empty multi-select (`allowEmpty`); Enter in the
  Custom Answer box no longer submits.
- **Tests**: two environment-dependent test oracles corrected (legacy net48
  toolset detection; long-path backup names); new regression checks added.
- **Launchers** report Windows' download mark and point to the
  "Blocked or unsigned scripts" guide section; policy is never bypassed.
- Archive: `Akzo-SDD-Agent-v4.2.4.zip`, with a per-file integrity manifest and
  an adjacent SHA-256.

## Installation and portability
Extract the complete archive to a short folder; run `Install-MasterAgent.cmd`.
The installer checks the manifest before modifying the selected installation.
Upgrade/repair preserves registrations, custom profiles, tasks and verified caches.
Under RemoteSigned/AllSigned policies, see "Blocked or unsigned scripts" in
`installation-guide.html`. Checksums establish integrity, not publisher identity
or corporate approval. No VSIX, IDE modification or GitHub publication is included.

## Verification scope
Run against clean, extracted v4.2.4 packages:
- **Full agent regression**: `scripts/test.ps1` — 487 passed, 0 failed, 0 skipped.
- **Analyzer**: `scripts/test-analyzer.ps1` — 6 passed, including incremental
  semantic invalidation and the FluentValidation sync-over-async evidence case.
- **Contract readiness**: 23 passed; GraphQL is mechanically checked on fixtures,
  with bounded context retrieval and unchanged-scope cache reuse.
- **Interactions**: 17 passed. **Portability**: 69 passed.
- **Installer GUI**: 9 passed, 0 failed; package Validate, repository Validate,
  Save, Install, restart/reload, and clean-package integrity verified. The
  simulated old copy with 20 extra build files is rejected.
- **Configuration and safety**: existing repository registration reloads once;
  purge confirmation and scope, profile backup/restore, repair, rollback, and
  application-repository preservation are covered by the full suite.
- **Package**: 250 files plus `release-manifest.json`; extracted package integrity
  verified. Release builder rejects personal paths and excludes `bin`/`obj`.
- **Token telemetry**: NOT VERIFIED. The local Copilot log has no model usage,
  token, or tool-call counts, so no measured token savings are claimed.

## RC blockers and limitations
- Live Visual Studio 2026 Chat controls, live Sonar, and end-to-end model
  implementation time are **NOT VERIFIED**.
- Corporate code-signing certification and any organization-specific signing
  requirement are **NOT VERIFIED**; this ZIP is a Release Candidate, not a
  production-approved or published artifact.
- GraphQL: field-merge conflicts, directive locations and custom scalar formats
  are not validated; code-first schemas are not read (NO_SCHEMA); the generated
  client is compared by interface name only.
- The lesson store's read-modify-write remains single-writer.

This package is an RC, not production-ready or native-Chat certified.
