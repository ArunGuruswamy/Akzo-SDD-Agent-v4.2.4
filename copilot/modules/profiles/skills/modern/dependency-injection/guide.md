# Modern dependency injection

> Profile skill `modern-dependency-injection`: Modern service registration. Load only when the helper's profile is modern.

Shipped baseline from the 3.6.0 brief; the Formula agent instructions in profiles-custom replace it (see
`profiles/README.md`). Applies only when `profile` reports `modern`.

- Read the function app's `Program.cs` and the registration extension methods it calls. Register new handlers,
  validators, and services in the same extension and style as their siblings, with the same lifetime.
- Do not import Framework assumptions: no Scrutor assembly scanning unless the Modern solution itself already uses it, and no CRM
  service registration.
- No scoped service captured by a singleton; HTTP and GraphQL clients registered the way existing ones are.
- Verify every new registration is reached: the function resolves the handler through the dispatcher, and the handler
  resolves its service. A missing registration is found by running the tests or the host, not by reading.
