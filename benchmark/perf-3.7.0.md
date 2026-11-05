# Development-loop benchmark: 3.6.0 vs 3.7.0

Generated 2026-10-28 11:38 by `scripts\perf-bench.ps1`: 612 tracked files (60 features, 5 projects + 5 test projects), 5 interleaved rounds, Windows PowerShell 5.1.22621.6133, git version 2.51.0.windows.1. Each value is the median over the rounds; every call is a fresh helper process, as in the IDE.

| Scenario | 3.6.0 ms | 3.7.0 ms | change | peak MB (3.6.0 / 3.7.0) | output chars | files returned | index event (3.7.0) |
|---|---:|---:|---:|---|---|---|---|
| cold start (task, index removed) | 2094 | 2177 | +4% | 140 / 141 | 4161 / 4161 | - / - | rebuild |
| warm start (task again) | 1322 | 1361 | +3% | 128 / 128 | 4157 / 4157 | - / - | hit |
| exact-symbol lookup | 2566 | 1403 | -45% | 127 / 128 | 8709 / 961 | 22+20 more / 1+0 more | hit |
| handler investigation | 2629 | 1993 | -24% | 127 / 128 | 8736 / 8750 | 19+20 more / 19+20 more | hit |
| business-rule lookup | 2666 | 1748 | -34% | 127 / 127 | 8405 / 8419 | 26+19 more / 26+19 more | hit |
| repeat lookup, same feature | 2601 | 2004 | -23% | 127 / 128 | 8738 / 8752 | 19+20 more / 19+20 more | hit |
| lookup after a one-file edit | 2894 | 2267 | -22% | 134 / 136 | 8561 / 8575 | 21+20 more / 21+20 more | refresh |
| profile detection, first call | 894 | 977 | +9% | 112 / 121 | 3008 / 3284 | - / - | profile cache miss |
| profile detection, repeat | 878 | 810 | -8% | 112 / 101 | 3008 / 3283 | - / - | profile cache hit |
| guarded build command | 881 | 839 | -5% | 115 / 103 | 148 / 148 | - / - |  |
| staged test selection (affected) | n/a | 1128 | n/a |  / 126 |  / 2404 | - / - |  |

Staged test selection for the one-file edit: status `SELECTED`, build 1 project(s), 1 focused filter(s), 2 of 5 test projects for regression, full suite once at the final gate (`the repository's full test command (section 2, Commands)`).
Index cache hit rate after the rounds (3.7.0, last 50 synchronizations): 83.3%.

**NOT VERIFIED (needs real Copilot runs):** model turns, tokens, tool calls made by the agent, files the agent opened, and test run durations. The helper calls above are what the agent runs; fewer and smaller calls are an input to agent speed, not a measurement of it.
