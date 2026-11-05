# Framework CQRS development

> Profile skill `framework-cqrs-development`: Framework commands, queries, handlers, and functions. Load only when the helper's profile is framework.

Shipped baseline from the 3.6.0 brief; the Portable.Legacy agent instructions in profiles-custom replace it (see
`profiles/README.md`). Applies only when `profile` reports `framework`.

- Commands and queries with one handler each in the application project, dispatched through `IDispatcher` from the Framework
  functions, as siblings do. Commands change state; queries do not.
- Handlers depend on XRM service interfaces (or the EF6 context where the siblings use it), never on the CRM SDK directly.
- Folder placement mirrors the sibling feature. A dependency used by both commands and queries lives where the siblings
  keep shared dependencies (pre-PR scenario 5).
- Functions use the Framework response helpers for success and error responses; the response contract stays as it is.
- Validation lives where the Framework siblings put it; check before adding a validator and do not duplicate it in the function.
