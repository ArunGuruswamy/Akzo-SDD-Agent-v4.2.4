# Framework SonarCloud rules

> Profile rules: SonarCloud rules and repository policies for the Framework repository (Portable.Legacy). Read by the Akzo Master SDD agent only when the helper's profile is framework.

Canonical Framework catalog. Shipped baseline: the team's Framework SonarCloud rules were not available when this was written.
Save them as `profiles-custom/instructions/framework/sonar-rules.instructions.md` to replace this file (see
`profiles/README.md`).

**How to use:** apply while writing code. Keys are SonarC# rules (`csharpsquid:<key>`). Check each key against the Framework
SonarCloud quality profile and analyzer configuration (`sonar -Repo <id>`; `sonar -Check rule -Key csharpsquid:<key>` with
a server). Items marked **policy** are Framework repository policy, not necessarily SonarCloud rules; report them as policy
findings. Local compilation does not prove remote SonarCloud success.

## Framework-specific requirements
- **S2360** Optional parameters: do not add optional parameters to public members; use overloads, as the Framework rules
  require.
- **Parameter names consistent between interface and implementation** (the brief lists this as S2345). Check the key: in
  the SonarC# catalog this rule is S927 ("parameter names should match base declaration"), and S2345 is about `[Flags]`
  enumerations. Apply the rule either way; report it under the key the quality profile uses.
- **Line length at most 200 characters** (policy; S103 where the quality profile sets that threshold). `review` checks it
  on changed lines.
- **XML documentation** on new or changed public production APIs (policy; see `framework-xml-documentation`). `review` checks
  it.
- **Coverage of changed code at least the repository's threshold (provisional default 85%)** where measurable (policy; see
  `framework-coverage`).
- **Registration and XRM conventions** (policy): handlers discovered by the Scrutor scan; XRM services registered in the
  CRM service registration extension; CRM access through `CrmOperationBase` implementations.
- **No broad `catch (Exception)`** in new code unless the sibling pattern at that layer does exactly that; example code
  that catches everything is not a pattern to copy. `review` warns on it.

## Async and Task
- No `async void` outside event handlers (S3168). Await instead of `.Result`, `.Wait()`, or `GetAwaiter().GetResult()`.
- Pass `CancellationToken` through where the CRM and EF6 calls accept it; validate arguments before the first `await`
  (S4457).

## Exception handling
- No empty catch blocks (S108, S2486); never swallow an exception.
- Do not throw `Exception`, `SystemException`, or `ApplicationException` (S112); keep the original as inner when wrapping.

## Null safety
- No dereference of a possibly null value (S2259); CRM attribute values are checked before use, as siblings check them.

## Collections and LINQ
- Simplify LINQ chains (S2971); `Any()` instead of `Count() > 0` (S1155); `Find`, `Exists`, `TrueForAll` where they apply
  (S6602, S6603, S6605).

## Strings
- A literal repeated three or more times becomes a constant (S1192): entity and attribute logical names especially.
- No string concatenation in loops (S1643); culture stated where siblings state it (S6580).

## Fields and properties
- `readonly` for fields never reassigned (S2933); no public mutable fields; no new mutable static state.

## Method complexity
- Cognitive complexity at most 15 (S3776); at most 7 parameters (S107); short methods (S138); no complex boolean
  expressions (S1067).
- Cyclomatic complexity at most 10 per method (S1541; reported by Framework SonarCloud on a PR with this threshold). Count
  the branches before handing over: each `if`, `case`, `&&`, `||`, `?:`, `??`, `?.`, and loop adds one. Lower it with
  guard clauses and by extracting a step with its own responsibility (status conversion, validation, response
  building), never by moving branches into a helper that only hides them, and never by changing a business rule.

## Formatting and culture
- S4056 (reported by Framework SonarCloud on a PR): call the overload that takes an `IFormatProvider` when one exists.
  Look at the whole flagged expression: `string.Format(<message constant>, ...)` is the usual cause, fixed as
  `string.Format(CultureInfo.InvariantCulture, <message constant>, ...)`; `Guid` and `bool` values inside it need no
  change of their own. Keep the message text, response shape, and status code unchanged.

## Control flow
- Merge collapsible `if`s (S1066); no identical branches (S1871); no nested ternaries (S3358); no always-true or
  always-false conditions (S2583); no assignments inside sub-expressions (S1121).

## Type design
- Static-only classes have no public constructor (S1118); private classes not derived from are `sealed` (S3260); members
  using no instance data are `static` (S2325).

## IDisposable
- Dispose what you create, including EF6 contexts you own (S2930); correct dispose pattern (S3881).

## Naming
- Repository naming (S101, S100); no unused locals, parameters, or private members (S1481, S1172, S1144); no dead stores
  (S1854).

## Security
- No hard-coded credentials, secrets, or connection strings (S2068, S6418), including CRM connection strings; no
  hard-coded IP addresses (S1313); strong cryptography and secure random (S5547, S4790, S2245); no SQL built from strings
  (S2077).

## Testing
- MSTest tests assert something (S2699); test classes contain tests (S2187); expected/actual order (S3415).

## Code style
- No commented-out code (S125); no new TODO or FIXME (S1135); no empty methods without a reason (S1186).

## Rules to confirm against the quality profile
Apply these only after confirming each is active in the project's quality profile (`activeInProject` of
`sonar -Repo <id> -Check rule -Key csharpsquid:<key>`, with its parameters, or the Sonar tools in chat); until then they
are code-quality guidance, never reported as SonarCloud findings.
- Validate arguments of public methods against null before use (S3900).
- Do not pass string literals as localized parameters (S4055): use the repository's existing constants or messages
  class as siblings do. Never add `.resx` files, a `ResourceManager`, or a localization framework for it; when only
  those would satisfy the rule, report the conflict instead.
- Keep a class coupled to a limited number of other classes; split responsibilities instead (S1200).

## Build warnings (compiler and .NET analyzers, not Sonar rules)
Fix these from the build output and list them with the build results, never in the Sonar table:
- CS1572: an XML `<param>` names a parameter the method does not have; CS1573: a parameter has no `<param>` while
  others do. Update the documentation with the signature (`review` also reports it).
- CA1860: use `Count`, `Length`, or `IsEmpty` instead of `Any()` on collections that have them (`Any()` stays right for
  plain `IEnumerable<T>`, S1155).
- CA2254: the logging message template stays a constant with named placeholders (`"Deactivated {RequestId}"`, value as
  an argument); never build it with interpolation or concatenation. Keep event ids, levels, and property names.
- CA1303: a literal passed to a parameter marked localizable. Log messages are not user-facing; moving it to a
  `const` field does not resolve it (the analyzer checks the constant value). Fix it the way the module's existing code does, or report the conflict;
  never add `.resx` or a `ResourceManager` for it.
