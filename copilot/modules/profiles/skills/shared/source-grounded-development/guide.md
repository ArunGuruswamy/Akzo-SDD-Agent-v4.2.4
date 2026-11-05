# Source-grounded development (shared, every profile)

> Profile skill `source-grounded-development`: Mandatory before writing code in any repository profile. Establish every type, member, contract, registration, and business rule from the repository itself before changing it; never generate speculative APIs.

Applies in every repository. The active profile's own skills say *how* code is written there; this skill says *what
must be proven first*. Shipped baseline (see `profiles/README.md`).

## Before writing any code

1. **Repository and solution:** use `issue`'s profile result or `profile -Repo <id>`, not both for unchanged evidence.
   Identify the active solution and affected projects. With `DETECTED` or `CONFIRMED`, load only that profile; with
   `NO_PROFILE` or `UNCERTAIN`, no profile-specific rules apply: inspect source and follow the repository's own patterns.
   With `AMBIGUOUS`, resolve from the request/workspace evidence or ask one free-text question and confirm with `-Key`. Never decide
   from a feature or entity name: the same names (for example Formula) exist in more than one system.
2. **Git state:** branch, HEAD, and pre-existing changes (reuse `issue`/`task` output, otherwise `branchinfo`). Pre-existing changes are not yours; do not
   reformat, revert, or include them.
3. **Architecture and feature:** refresh `arch -Repo <id> -Query "<nouns and verbs>"` before any code change, including
   fixes and tests; reuse only unchanged current fingerprints. Read the closest implementation and cited source spans.
   On partial/syntax/unavailable semantic analysis, use bounded `context` and source reads and mark unresolved links
   UNVERIFIED; syntax is not compiler-grade caller, DI, or dependency proof.
4. **Entry point to data:** read the existing function or endpoint, the command or query it dispatches, and its handler.
5. **Service contract:** the service interface and every implementation of it.
6. **Models:** request, response, and domain models the change touches, with nullability and serialization attributes.
7. **Validation:** the validators and business-rule helpers that already own the rule, and how their errors reach the
   caller (exception type, middleware, response shape). Apply S5's FluentValidation discovery when already used in
   the affected .NET project; verify async execution and DI before the business operation. Other stacks retain their
   own validation framework. Preserve domain invariants and security checks.
8. **Callers and dependents:** every caller of a method you will change (search by name and by interface member).
9. **Registration:** where the handler, service, and validator are registered, and with which lifetime.
10. **Tests:** the existing tests for this feature and its closest sibling, and the test framework and mocking library
    they use.
11. **Reuse:** search for an existing helper, constant, mapper, or service that already does the work.
12. **Smallest safe change:** keep a compact internal execution map of relevant verified symbols and `path:line` links,
    affected files, and reuse choices. Use existing PBI spec/plan when applicable; direct fixes keep working context,
    not a new plan or document. Anything outside the authorized affected path stays unchanged.
13. **Readiness and approval:** for GraphQL apply S7 before planning, selecting relevant indexed schemas, operations,
    fragments and inputs without loading whole schemas. Record plan section 1b's readiness, reusable/new validators,
    registration/execution, preserved error contracts and tests. Direct fixes report the same checks in a compact
    chat plan. Explicit approval of the concrete plan is required before application writes, even in Auto Mode;
    material unresolved schema/client incompatibilities block dependent tasks.

## Search order and when to stop

Exact symbol or file name (`context -Query "<ExactName>"` answers with `exact: true`, the file, its tests, and its direct
callers) -> the feature folder -> direct callers and interfaces -> service implementations -> registration -> related
tests -> wider search. Stop widening once every type, member, rule owner, and registration the change relies on has
`path:line` evidence; do not open unrelated large files or re-read whole files you already cited. Independent reads may
be batched or run in parallel; edits, builds, and test runs are never run in parallel on the same files or outputs.

## Validation ownership (every change that adds, moves, or reviews a rule)

1. Find every place the rule or a near copy lives today: validators, handlers, collaborators, services, factories,
   data access, and, when the PBI names one, the legacy source it came from.
2. Report duplicates and conflicts (same rule twice, different messages or conditions for the same input).
3. Decide the owner by what the rule needs: input shape and required fields -> the feature's validator, as siblings do;
   rules that need data lookups or other aggregates -> where siblings already place such rules (a validator with
   injected services, or a business service); orchestration and state changes -> the handler or service. Not every
   rule belongs in a validator, and a validator never changes state.
4. Prefer extending the feature's existing validator or service over a new standalone validator or collaborator.
5. Keep business behavior, error contracts (exception type, property name, message, status), and any validation order
   clients depend on.

## Abstractions: add or remove

- **Before adding** a collaborator, helper, interface, factory, query service, extension method, dependency container,
  or registration: search for an existing equivalent, check its naming against siblings, list its real consumers, and
  check the layer boundary. One consumer and one implementation with no sibling precedent means it is not needed;
  avoid wrappers, duplicate interfaces, and duplicate queries. Justify a necessary new class by the verified gap,
  closest implementation, layer, and why existing symbols cannot serve it.
- **Before removing** one: find every reference (by name and by interface), its registration and lifetime, its test
  dependencies, and any reflection, assembly scanning, or convention-based registration that reaches it. Remove it only
  when nothing at run time or in tests still needs it, and update the registration in the same change.

## Proof rules

- An existing class, interface, method, property, namespace, DTO field, Dataverse/CRM entity or attribute, GraphQL operation or field,
  option-set value, or configuration key may be used only after you have seen it in the repository (or in generated code
  produced by the repository's own generation step). Quote `path:line` in the execution map or existing PBI plan.
  Never infer logical attributes, GraphQL contracts, or generated signatures from examples; never hand-edit generated output.
- Examples in instruction or skill files (including this folder) are patterns, not code that exists. Validate every name
  against the repository before using it; never copy placeholder names into production code.
- Changing a method signature: inspect every implementer and every caller first; update them all or do not change it.
- Changing a response model: inspect every consumer (functions, clients, UI services, contract tests); prefer additive
  changes; a breaking change is a Stop condition.
- Changing validation: confirm which layer owns the rule today and how its error is translated; do not duplicate it in
  another layer.
- A dependency you cannot find (a type, a generated client, a plugin's behavior, a CRM field) is recorded as
  **UNVERIFIED** in working context (existing PBI plan when applicable), with the search and blocker. Never implement it on assumption.
- Assumptions are checked by the build and tests: a type you introduced must compile, an interface implementation must
  match its contract, and a test must exercise the real code path, not a copy of it.

## Anti-hallucination gate (before the plan is approved and again before handover)

Reject the change, or the plan item, if any of these holds: a nonexistent class or member; an unverified method; a wrong
namespace; the wrong solution or repository profile; an interface implemented incorrectly; an invented DTO property;
incorrect service registration or lifetime; an option-set value not found in the source; assumed plugin behavior; an
exception contract that differs from the existing one; an invented GraphQL operation or field; an incorrect CRM SDK model.
Then refresh changed semantic evidence, run the actual affected build and required tests, read analyzer/Sonar results,
measure changed-line coverage, verify layer direction and DI lifetime/reachability, run `git diff --check`, and read the
complete diff plus new files. Report source references, reused symbols, new-class justification, and exact blockers.
No AI-only PASS; an unavailable check is NOT VERIFIED, never converted from static reasoning into a test or Sonar result.
