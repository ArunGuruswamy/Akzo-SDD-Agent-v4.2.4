# Architecture analyzer hosts

Build with `scripts\build-analyzer.ps1` (.NET SDK 8+). The package contains a
net8.0 host at its root and a C# 12/net472 host under `net472`.
`arch` selects the framework executable when Visual Studio MSBuild 18+ is
installed; otherwise it uses `dotnet`.

The build script restores once for both targets. For source-only iteration after
a successful restore, `scripts\build-analyzer.ps1 -NoRestore` skips restore
explicitly. Do not use it after dependency manifests, SDK or NuGet configuration
changes; missing assets fail rather than being silently restored.

`arch -Queries "HandlerName;ValidatorName"` uses one helper/analyzer launch and
one content-validated semantic refresh for up to eight C# queries. Evidence is
the same as individual `-Query` requests. Language routing skips structural
graph/framework/convention discovery; full workspace discovery remains available
through `workset`. Content hashing and transitive caller invalidation are unchanged.
`scripts\test-architecture-retrieval.ps1` checks routing, query equivalence and
signature-change incremental/fresh equivalence through the normal helper.

MSBuild Locator registers the selected instance before workspace code loads.
The framework host launches an isolated copy under the user's short LocalAppData host cache, outside application
repositories. It refuses an overlong user profile rather than claiming unsupported paths worked.
Only older bundled runtime dependencies are overlaid from the selected installed
toolset; metadata references determine the transitive dependency closure.
Binding redirects use actual assembly versions. Installed Visual Studio
assemblies are never added to the distributable package.
The staged child is path-pinned. Roslyn's remote framework host selects independently,
so multiple compatible VS instances are explicitly rejected rather than guessed.

Staging keys include toolset identity/path and SHA-256 content of MSBuild,
its runtime dependency closure, and bundled application/BuildHost files/config.
Scanner input hashes also include that runtime fingerprint and the analyzer MVID.
Unchanged caches stay warm; same-version dependency byte changes invalidate them.
Unique staging directories are atomically published, without modifying shared
published files or the analyzed repository. Unsupported projects remain explicitly
syntax/partial, with detailed load errors.

The test suite invokes `net472\Akzo.ArchitectureAnalyzer.exe cache-test --out <cache>`
when MSBuild 18+ is available. It verifies warm fingerprints and a same-version,
different-byte transitive dependency while leaving the MSBuild assemblies unchanged.
It also checks that changing bundled BuildHost configuration bytes invalidates the key.

Changed and removed declarations rebind all documents in affected projects and transitive consumer projects.
This deliberately trades some incremental speed for valid call/registration edges. `scripts\test-analyzer.ps1`
compares incremental and fresh signature-change edges and verifies deletion invalidation in isolated offline projects.
Common Scrutor assembly/class/interface/lifetime chains resolve through semantic symbols; dynamic predicates and
unresolved assembly selection are listed under `unresolved`, not fabricated registrations.
Query limits are bounded; exact type names suppress unrelated candidates. Orphan syntax documents remain visible in
coverage but cannot be recommended as implementations.
