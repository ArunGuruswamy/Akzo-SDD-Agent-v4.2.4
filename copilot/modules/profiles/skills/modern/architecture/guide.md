# Modern .NET architecture discovery

Optional reference, not an application blueprint. Use only through an explicit user profile or when relevant source
confirms the framework. Project names, namespaces and folder suffixes do not establish layers.

- Identify the actual solution and evaluated project references with `arch`.
- Record declared and resolved frameworks, load failures, source ownership and test projects independently.
- Trace the affected entry point, collaborators, registration, persistence, response mapping and tests.
- If handlers, validators, GraphQL clients, middleware or layered boundaries exist, reuse the closest implementation;
  otherwise follow the repository's real pattern. Do not introduce them merely because this guide mentions them.
- Scrutor, direct DI and manual construction are different registration mechanisms. Resolve the actual registration.
- A referenced repository is read-only unless explicitly selected for application development.
- Contracts and business-rule ownership require code evidence, not assumptions about a "modern" backend.
- Any new layer/framework/pattern outside the approved plan needs user approval.
