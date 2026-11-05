# Framework XRM service

> Profile skill `framework-xrm-service`: Framework XRM services built on CrmOperationBase and the CRM SDK. Load only when the helper's profile is framework.

Shipped baseline from the 3.6.0 brief; the Portable.Legacy agent instructions in profiles-custom replace it (see
`profiles/README.md`). Applies only when `profile` reports `framework`.

- New CRM access goes into a service interface under Data/XRMService and an implementation that follows the existing
  `CrmOperationBase` pattern (read the base class and two implementations first: constructor dependencies, how the
  organization service is obtained, logging, and error handling).
- Use the CRM SDK types and query style the siblings use (QueryExpression, FetchXML, LINQ, early-bound or late-bound
  entities). Do not mix in another style.
- Entity logical names, attribute names, and option-set values come from the code (constants, early-bound classes,
  existing queries). If one cannot be found, mark it UNVERIFIED in existing PBI evidence or direct-fix context and
  report the blocker; ask only when the unresolved requirement needs a user decision. Never guess it or create a plan for a fix.
- Select only the columns used; page large queries as siblings do; never query inside a loop when one query can serve.
- Interface and implementation parameter names must match (the Framework rule catalog), and optional parameters follow the
  catalog's guidance.
- Unit-test the service with NSubstitute substitutes for the organization service, as existing service tests do.
