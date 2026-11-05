# TypeScript architecture analyzer

Requires local Node.js and the selected workspace's installed TypeScript dependency. No network/download, application
emission, npm restore or application file edits occur during analysis.

```text
node analyze.cjs scan --root <workspace> --out <agent-cache>
node analyze.cjs query --root <workspace> --out <agent-cache> --terms <symbol-or-requirement>
```

Discovers angular.json projects and tsconfig programs; uses the compiler checker for symbols, aliases, imports,
resolved calls and diagnostics. Source metadata includes decorators, providers, inject calls, routes and resolved
HttpClient expressions. Queries return at most eight candidates with bounded context. Dynamic metadata is labeled
source evidence, not runtime validation; Angular templates are not compiled.

Versioned root/analyzer/compiler/input/declaration fingerprints reuse unchanged indexes. Changed inputs revalidate
all programs so unchanged consumers do not retain stale edges. This is not a compiler-watch incremental engine.
Multiple TS workspaces and mixed-language roots require explicit workspace registration rather than guessed selection.
All indexes are user-local and contain workspace paths; none belongs in the distributed package.

`scripts/test-typescript.cjs` uses isolated renamed fixtures and an explicitly supplied existing compiler via
`SDD_TEST_TYPESCRIPT`. No compiler means a visible skip, not a passing semantic test.
