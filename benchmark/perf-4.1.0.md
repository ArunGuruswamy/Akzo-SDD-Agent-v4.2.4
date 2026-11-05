# Development-loop benchmark: 4.0.0 vs 4.1.0

Generated 2026-10-31 17:04 by `scripts\perf-bench.ps1`: 612 tracked files (60 features, 5 projects + 5 test projects), 5 interleaved rounds, Windows PowerShell 5.1.22621.6133, git version 2.51.0.windows.1. Each value is the median over the rounds; every call is a fresh helper process, as in the IDE.

| Scenario | 4.0.0 ms | 4.1.0 ms | change | peak MB (4.0.0 / 4.1.0) | output chars | files returned | index event (4.1.0) |
|---|---:|---:|---:|---|---|---|---|
| cold start (task, index removed) | 2488 | 2459 | -1% | 145 / 168 | 4602 / 4390 | - / - | rebuild |
| warm start (task again) | 1639 | 1547 | -6% | 132 / 168 | 4598 / 4386 | - / - | hit |
| exact-symbol lookup | 1553 | 1410 | -9% | 131 / 166 | 961 / 961 | 1+0 more / 1+0 more | hit |
| handler investigation | 2219 | 2074 | -7% | 131 / 166 | 8750 / 8750 | 19+20 more / 19+20 more | hit |
| business-rule lookup | 1944 | 1920 | -1% | 131 / 166 | 8419 / 8419 | 26+19 more / 26+19 more | hit |
| repeat lookup, same feature | 2175 | 2032 | -7% | 131 / 166 | 8752 / 8752 | 19+20 more / 19+20 more | hit |
| lookup after a one-file edit | 2508 | 2330 | -7% | 132 / 166 | 8575 / 8575 | 21+20 more / 21+20 more | refresh |
| profile detection, first call | 1199 | 1295 | +8% | 130 / 167 | 3635 / 3930 | - / - | profile cache miss |
| profile detection, repeat | 910 | 974 | +7% | 109 / 166 | 3634 / 3929 | - / - | profile cache hit |
| guarded build command | 934 | 782 | -16% | 111 / 128 | 148 / 148 | - / - |  |
| staged test selection (affected) | 1299 | 1249 | -4% | 130 / 165 | 2564 / 2564 | - / - |  |
| Fix Issue start, cold (index removed) | 3443 | 3041 | -12% | 157 / 156 | 3970 / 4116 | - / - |  |
| Fix Issue start, warm | 2320 | 2014 | -13% | 131 / 156 | 3964 / 4110 | - / - |  |

Staged test selection for the one-file edit: status `SELECTED`, build 1 project(s), 1 focused filter(s), 2 of 5 test projects for regression, full suite once at the final gate (`the repository's full test command (section 2, Commands)`).
Index cache hit rate after the rounds (4.1.0, last 50 synchronizations): 83.3%.
Fix Issue start: 4.0.0 makes 1 helper calls (branchinfo, profile -Task fix, context), 4.1.0 makes 1 (issue); in the IDE each helper call is also one agent tool call. Times are the sum of the calls.

**NOT VERIFIED (needs real Copilot runs):** model turns, tokens, tool calls made by the agent, files the agent opened, and test run durations. The helper calls above are what the agent runs; fewer and smaller calls are an input to agent speed, not a measurement of it.
