# Helper benchmark: 3.3.0 vs 3.4.1

Akzo SDD Agent — Developed and maintained by Arun RG

- Date: 2026-10-26 02:58 · Command: `scripts\benchmark.ps1 -Features 60 -Runs 5`
- Environment: Windows PowerShell 5.1.22621.6133, Git 2.51.0.windows.1, 13th Gen Intel(R) Core(TM) i7-13620H, 16 GB RAM
- Repository: generated, 663 tracked files (60 features: command, handler, validator, service, repository, DTO, controller, test, UI component, UI service, UI spec), one commit
- Times are wall clock per helper call including Windows PowerShell start-up (median of 5 where noted). Characters are the size of the helper's output, which is what enters the model's context.

| Metric | 3.3.0 | 3.4.1 | Change | Kind |
|---|---|---|---|---|
| First discovery (cold `task`, builds the index) | 1229 ms | 2398 ms | 95% | measured |
| Same task again (warm, median) | 1056 ms | 1361 ms | 29% | measured |
| Second PBI start-up (index exists) | 1069 ms | 1284 ms | 20% | measured |
| Start-up after an uncommitted new file | 1045 ms | 1763 ms | 69% | measured |
| Uncommitted new file appears in the index | False | True | | measured |
| `task` output size (warm) | 2482 chars | 3746 chars | 51% | measured |
| Selection for one requirement: index term search ("approve", "invoice", "validator", 2 of 3) | 41 lines, 2646 chars, target listed: True | 41 lines, 2646 chars | | measured |
| Selection for one requirement: `context -Query "approve invoice amount validation"` | not available | 8493 chars, 2938 ms (median), first file: `src/App/Invoice/ApproveInvoice/ApproveInvoiceValidator.cs` (expected: True) | | measured |
| Memory hit rate over this run's synchronizations | not recorded | 78.6% | | measured |
| Upgrade 3.3.0 -> 3.4.1 keeps an existing task working (the repository needs a one-time `authorize` first: blocked until then, then the same spec path and task) | | PASS | | measured |
| Model interactions, tokens, files read, manual interactions in Copilot | | | | NOT VERIFIED (needs IDE runs; see benchmark/results-template.csv) |

Notes
- The index term search row shows what the agent had to read next in 3.3.0 (matching index lines, then whole files). 3.4.1 returns ranked files with symbol line numbers and linked tests in one call; files are still read at the cited lines (retrieval level L3), so this row is not a claim of end-to-end token savings.
- 3.4.1 fingerprints every file by content on each call. Its warm time is the cost of that check; the benefit is that edits, untracked files, deletions, and renames are seen without a commit (row 5), and only changed files are reparsed.