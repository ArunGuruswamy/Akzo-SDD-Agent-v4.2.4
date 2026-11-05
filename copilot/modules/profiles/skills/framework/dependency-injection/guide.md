# Framework dependency injection

> Profile skill `framework-dependency-injection`: Framework registration through Scrutor scanning and the CRM service registration extension. Load only when the helper's profile is framework.

Shipped baseline from the 3.6.0 brief; the Portable.Legacy agent instructions in profiles-custom replace it (see
`profiles/README.md`). Applies only when `profile` reports `framework`.

- Handlers: read the Scrutor scan (assembly, type filter, lifetime). A new handler that matches the filter needs no manual
  registration; one that does not match is a sign it is in the wrong place or has the wrong shape.
- XRM services: register in `ServiceRegistration.CrmServices.cs` (verify the file) next to their siblings, with the same
  lifetime.
- Do not import Modern registration assumptions (Modern `Program.cs` extensions, StrawberryShake client registration).
- Prove registration by running the tests or the host: a handler that is never resolved is a missing registration.
