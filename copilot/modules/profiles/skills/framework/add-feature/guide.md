# Framework add feature

> Profile skill `framework-add-feature`: Adding a Framework feature (command or query, handler, XRM service, function, tests) without scaffolding what already exists. Load only when the helper's profile is framework.

Shipped baseline from the 3.6.0 brief; the team's `add-feature` skill replaces it when saved under profiles-custom (see
`profiles/README.md`). Applies only when `profile` reports `framework`.

1. **Find the closest existing feature** (same entity or same kind of operation) and read its command or query, handler,
   service interface, XRM service, function, registration, and tests.
2. **Inventory:** for each of those components decide EXISTING (reuse), EXTEND (add a member), or NEW. Generate only what
   is missing; never replace working code with scaffolding.
3. **Names and namespaces** come from the sibling's real files, not from examples. No placeholder (`<Entity>`, `MyFeature`,
   `TODO`) reaches the final code.
4. **Order:** service interface member -> XRM service implementation (`CrmOperationBase` pattern) -> command or query and
   handler -> function -> registration check -> tests.
5. **Registration:** handlers found by Scrutor need no manual registration if they match the scanned pattern; check the
   scan filter. XRM services are registered in the CRM service registration extension, as siblings are.
6. **Exceptions:** example code that wraps everything in `catch (Exception)` conflicts with the Framework SonarCloud rules.
   Catch only exceptions you handle, in the way sibling services handle them; let the rest reach the function's existing
   error handling. Record the decision in the plan.
7. **XML documentation** on every new or changed public production API (`framework-xml-documentation`).
8. **Tests:** MSTest and NSubstitute, as in `framework-run-tests`; at least the repository's threshold (provisional default 85%) coverage of changed lines where measurable.
