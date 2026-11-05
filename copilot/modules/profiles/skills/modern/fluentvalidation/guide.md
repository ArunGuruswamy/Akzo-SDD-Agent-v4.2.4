# Modern FluentValidation

> Profile skill `modern-fluentvalidation`: Modern FluentValidation conventions. Load only when the helper's profile is modern.

Shipped baseline from the 3.6.0 brief; the Formula agent instructions in profiles-custom replace it (see
`profiles/README.md`). Applies only when `profile` reports `modern`.

1. Read two or three existing validators for the same kind of request before writing or changing one.
2. Mirror them: base class (`AbstractValidator<T>` where the siblings use it), `RuleFor` chains, how messages are written
   (`WithMessage`, resource keys, or constants), `When`/`Unless` conditions, child validators, and file location.
3. Preserve existing messages and business conditions exactly; a changed message is a contract change for clients.
4. Validation belongs in the application layer. Do not repeat it in the function, and do not catch the validation
   exception in the function when the middleware translates it (pre-PR scenarios 1, 2, and 4).
5. Extend the feature's existing validator before adding a standalone validator or a validation collaborator. Not every
   rule belongs in FluentValidation: rules that change state or orchestrate calls stay in the handler or application
   service (source-grounded skill, validation ownership).
6. Test each rule: valid input passes; each invalid case fails with the expected property name and message.
7. New request, command and side-effect-free business-rule validation uses the existing FluentValidation pattern.
   Reuse shared rules and child validators; use `Must`, `MustAsync`, `When` and dependent rules where appropriate.
   External-service/database checks are async and reached through awaited `ValidateAsync` with cancellation, never
   a synchronous pipeline that cannot execute async rules.
8. Trace DI and the actual pipeline or explicit invocation: the validator must run before the corresponding business
   operation. Keep domain invariants and security checks in their proper layers, and preserve the existing validation
   error-response contract rather than duplicating checks in Functions, Controllers or Handlers.
9. Before implementation, list existing/new/modified validators, registrations, execution tasks, error translation,
   valid/invalid/null/empty/boundary tests and execution-order/DI/error-contract integration tests in plan section 1b.
   Obtain explicit plan approval. Do not introduce this framework into unrelated projects.
