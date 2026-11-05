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

## Verification scope (what was and was not run for this RC)
Run by the release author, on fixtures:
- **Analyzer**: built for net8.0 and net472 with 0 warnings.
- **GraphQL**: 11 of 11 planted errors and 2 warnings found, with no findings
  on valid operations; per-scope cache reuse and refresh; syntax errors located;
  real StrawberryShake-style client mismatch reported.
- **FluentValidation**: detected with the real FluentValidation 12.0.0 /
  DependencyInjectionExtensions 11.11.0 packages, including the
  sync-over-async defect.
- **Incremental analysis**: identical to a fresh scan after body edits, block/arrow
  switches, signature changes, a new member, files with directives and file deletion.
- **Concurrency**: an 8-process stress test of the new write helpers kept
  200 of 200 updates; the 4.2.3 pattern lost the file.
- **PowerShell files**: all changed files parse without errors.
- **Performance**: 5 interleaved runs against the 4.2.3 analyzer, medians:
  - body-only incremental: 4584 → 3422 ms (2 projects, −25.3%);
    7413 → 3280 ms (5 projects, −55.8%)
  - cold, warm and signature-change scans: within noise; no speedup claimed

**Not run by the release author:** the PowerShell regression suites (`test.ps1`,
`test-analyzer.ps1`, `test-contract-readiness.ps1`, `test-interactions.ps1`,
`test-portable.ps1`), the installer, and the GUI tests. On the build machine the
execution policy refuses these unsigned, internet-marked scripts, and the policy
was not bypassed. The previous full regression (4.2.3 source) was 483 passed and
2 failed; both failures were traced to test oracles, which are corrected here.
Run the suites under your signing policy before treating this RC as verified.

## RC blockers and limitations
- Live Visual Studio 2026 Chat controls, real DAB/CDMS/UI repositories, live
  Sonar, and end-to-end model implementation time are **NOT VERIFIED**.
- GraphQL: field-merge conflicts, directive locations and custom scalar formats
  are not validated; code-first schemas are not read (NO_SCHEMA); the generated
  client is compared by interface name only.
- The lesson store's read-modify-write remains single-writer.

This package is an RC, not production-ready or native-Chat certified.
