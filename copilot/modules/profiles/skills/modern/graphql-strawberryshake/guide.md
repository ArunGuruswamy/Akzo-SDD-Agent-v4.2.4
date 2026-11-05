# Modern GraphQL with StrawberryShake

> Profile skill `modern-graphql-strawberryshake`: Modern GraphQL access through StrawberryShake generated clients. Load only when the helper's profile is modern.

Shipped baseline from the 3.6.0 brief; the Formula agent instructions in profiles-custom replace it (see
`profiles/README.md`). Applies only when `profile` reports `modern`.

- Reach GraphQL through the existing service interfaces in the data layer. Handlers depend on the interface, not on the
  generated client, unless the siblings do otherwise.
- Before using an operation, find its `.graphql` document, the operation name, and the generated interface and result
  types. Never write a generated type, property, or operation name you have not seen in the generated output.
- Apply S7's mandatory pre-implementation check: use current indexed declarations and relevant schema/fragment/input
  spans to verify field names, arguments, types, required values and nullability before planning. Compare the actual
  operation and generated signatures, reuse existing operations, and record compatibility or explicit regeneration
  tasks in plan section 1b. Unresolved material incompatibilities block dependent work.
- Present the schema evidence, client generation command, affected consumers and tests for explicit plan approval
  before application writes, even in Auto Mode. A generator or build that writes files also waits for approval.
- A new or changed operation: follow the siblings' document layout and naming, select only the fields used, reuse
  fragments, use variables; then run the repository's StrawberryShake generation step and build. Confirm the generated
  types exist before writing code against them.
- Never edit generated files by hand, and do not regenerate when no document or schema changed.
- Map generated results to application response models in the data layer as the siblings do; generated types do not leak
  into function responses.
- Handle client errors the way sibling services do (check the result's errors as they do); never swallow them.
