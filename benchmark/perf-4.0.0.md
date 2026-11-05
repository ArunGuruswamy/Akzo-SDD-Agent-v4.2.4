# Development-loop benchmark: 3.12.0 vs 4.0.0

Generated 2026-10-31 12:49 by `scripts\perf-bench.ps1`: 612 tracked files (60 features, 5 projects + 5 test projects), 5 interleaved rounds, Windows PowerShell 5.1.22621.6133, git version 2.51.0.windows.1. Each value is the median over the rounds; every call is a fresh helper process, as in the IDE.

| Scenario | 3.12.0 ms | 4.0.0 ms | change | peak MB (3.12.0 / 4.0.0) | output chars | files returned | index event (4.0.0) |
|---|---:|---:|---:|---|---|---|---|
| cold start (task, index removed) | 2432 | 2351 | -3% | 139 / 139 | 4405 / 4602 | - / - | rebuild |
| warm start (task again) | 1575 | 1591 | +1% | 133 / 139 | 4401 / 4598 | - / - | hit |
| exact-symbol lookup | 1568 | 1563 | +0% | 131 / 131 | 961 / 961 | 1+0 more / 1+0 more | hit |
| handler investigation | 2111 | 2151 | +2% | 131 / 131 | 8750 / 8750 | 19+20 more / 19+20 more | hit |
| business-rule lookup | 1908 | 1962 | +3% | 131 / 131 | 8419 / 8419 | 26+19 more / 26+19 more | hit |
| repeat lookup, same feature | 2090 | 2133 | +2% | 131 / 131 | 8752 / 8752 | 19+20 more / 19+20 more | hit |
| lookup after a one-file edit | 2405 | 2509 | +4% | 135 / 131 | 8575 / 8575 | 21+20 more / 21+20 more | refresh |
| profile detection, first call | 1103 | 1205 | +9% | 128 / 127 | 3455 / 3305 | - / - | profile cache miss |
| profile detection, repeat | 883 | 876 | -1% | 107 / 106 | 3454 / 3304 | - / - | profile cache hit |
| guarded build command | 906 | 909 | +0% | 110 / 109 | 148 / 148 | - / - |  |
| staged test selection (affected) | 1300 | 1233 | -5% | 129 / 129 | 2404 / 2564 | - / - |  |
| Fix Issue start, cold (index removed) | 4768 | 3372 | -29% | 133 / 153 | 5830 / 3640 | - / - |  |
| Fix Issue start, warm | 3728 | 2309 | -38% | 131 / 131 | 5824 / 3634 | - / - |  |

Staged test selection for the one-file edit: status `SELECTED`, build 1 project(s), 1 focused filter(s), 2 of 5 test projects for regression, full suite once at the final gate (`the repository's full test command (section 2, Commands)`).
Index cache hit rate after the rounds (4.0.0, last 50 synchronizations): 83.3%.
Fix Issue start: 3.12.0 makes 3 helper calls (branchinfo, profile -Task fix, context), 4.0.0 makes 1 (issue); in the IDE each helper call is also one agent tool call. Times are the sum of the calls.

**NOT VERIFIED (needs real Copilot runs):** model turns, tokens, tool calls made by the agent, files the agent opened, and test run durations. The helper calls above are what the agent runs; fewer and smaller calls are an input to agent speed, not a measurement of it.
