# Interleaved timing, 3.3.0 / 3.4.0 / 3.4.1

Akzo SDD Agent — Developed and maintained by Arun RG

Measured 2026-10-26 with `scripts\ab-bench.ps1` (6 rounds, order rotating, medians), on the 663-file generated repository of `scripts\benchmark.ps1`; Windows PowerShell 5.1.22621.6133, Git 2.51.0, i7-13620H, 16 GB. Wall clock per helper call including PowerShell start-up. Machine load varies, which is why versions are interleaved and compared within the same rounds.

| Version | Cold `task` (index rebuilt) | Warm `task` |
|---|---|---|
| 3.3.0 | 1682 ms (min 1609, max 1952) | 1484 ms (min 1414, max 1788) |
| 3.4.0 | 3424 ms (min 3059, max 4002), +104% | 2249 ms (min 2100, max 2658), +52% |
| 3.4.1 | 3078 ms (min 2822, max 3260), +83% | 1820 ms (min 1691, max 2102), +23% |

3.4.1 against 3.4.0, same rounds: cold about 10% faster, warm about 19% faster. Both are still slower than 3.3.0: the cost of content fingerprinting, symbol extraction, and the G8 checks. Single-run cold and warm figures in `results-3.4.1.md` are superseded by this table (they were taken one after another while machine load changed). Model interactions, tokens, files read, and manual interactions in Copilot: NOT VERIFIED.