# Architecture analyzer timing (4.2.0)

Akzo SDD Agent — Developed and maintained by Arun RG

Measured 2026-11-01 with `benchmark\arch-bench.ps1 -Projects 20 -FilesPerProject 40 -Rounds 3` on an idle machine (13th Gen Intel Core i7-13620H, 16 GB RAM, .NET SDK 9.0.313, Roslyn 4.14). The generated `net9.0` solution is a chain of 20 projects, each referencing the one before it, with 800 C# files and 1,600 types. Every class implements an interface and calls the layer below. The analyzer analyzed all 20 projects semantically. Times are medians of 3 rounds, and each includes starting the `dotnet` process.

| Run | Time |
|---|---|
| Cold scan (no index: MSBuild loads every project) | 9,079 ms |
| Warm scan (nothing changed: file hashes only, no load) | 282 ms |
| Incremental scan (1 file changed in the top project: it and the 19 projects below it reload; 1 file re-extracted) | 8,912 ms |
| Query (after the incremental scan) | 438 ms |

On the controlled samples used by the regression tests (same machine):

| Sample | Cold scan | Warm scan | Incremental (1 file) |
|---|---|---|---|
| Modern layered solution, 5 projects, 13 files (`.slnx`) | 9.1 s | 0.31 s | 6.1 s (a file in Infrastructure: it, Application, and Domain reload) |
| Legacy .NET Framework 4.8 project (Visual Studio's MSBuild) | 6.5 s | not measured | not measured |

What the numbers show:
- **Loading dominates.** Most of a scan is MSBuild loading the projects; extracting symbols, calls, and tests from 800 files takes well under a second. A warm scan skips the load entirely.
- **An incremental scan saves extraction, not loading.** A change in a project that references many others reloads them all, so it costs nearly as much as a cold scan. The 8.9 s above is that worst case; a change in a project lower in the chain reloads fewer projects.
- **Queries are cheap** once the index is fresh. The agent runs one `arch -Query` per PBI or shared-code change, not per edit.

Not measured: implementation time and remediation time with the analyzer. Both need the Copilot agent working real tasks in Visual Studio 2026 or VS Code, which this machine cannot run. No speed improvement for development work is claimed.
