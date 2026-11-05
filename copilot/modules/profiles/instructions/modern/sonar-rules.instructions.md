# Modern SonarCloud rules

> Profile rules: SonarCloud and code rules for the Modern repository (Portable.Backend). Read by the Akzo Master SDD agent only when the helper's profile is modern.

Canonical Modern catalog. Shipped baseline: the team's Modern rules were not available when this was written. Save them as
`profiles-custom/instructions/modern/sonar-rules.instructions.md` to replace this file (see `profiles/README.md`).

**How to use:** apply while writing code. Keys are SonarC# rules (`csharpsquid:<key>`). Each key must be checked against
the Modern SonarCloud quality profile and analyzer configuration (`sonar -Repo <id>`; `sonar -Check rule -Key
csharpsquid:<key>` with a server). A rule that is not active in the profile is applied as code quality, and reported as
a policy or code-rule finding, not as a SonarCloud finding. Local compilation does not prove remote SonarCloud success.

## Async and Task
- No `async void` outside event handlers (S3168). Await instead of `.Result`, `.Wait()`, or `GetAwaiter().GetResult()`.
- Pass `CancellationToken` through to the calls that accept it; name async methods `...Async` as siblings do.
- Validate arguments of an async method before the first `await` where siblings do (S4457).

## Exception handling
- No empty catch blocks (S108, S2486); never swallow an exception without handling or logging it.
- Do not throw `Exception`, `SystemException`, or `ApplicationException` (S112); keep the original as inner when wrapping.
- Catch only exceptions you handle. Validation errors reach the exception middleware; functions do not re-translate them.

## Null safety
- No dereference of a possibly null value (S2259); respect nullable reference types; guard public inputs.

## Collections and LINQ
- Simplify LINQ chains (S2971); prefer `Any()` to `Count() > 0` (S1155); use the collection's own `Find`, `Exists`,
  `TrueForAll` where they apply (S6602, S6603, S6605).

## Strings
- A literal repeated three or more times becomes a constant (S1192).
- No string concatenation in loops; use `StringBuilder` (S1643). Culture-sensitive formatting states the culture where
  siblings do (S6580).

## Fields and properties
- Fields never reassigned are `readonly` (S2933). No public mutable fields. No new mutable static state.

## Method complexity
- Cognitive complexity at most 15 (S3776); at most 7 parameters (S107); keep methods short (S138); no complex boolean
  expressions (S1067).

## Control flow
- Merge collapsible `if`s (S1066); no identical branches (S1871); no nested ternaries (S3358); no conditions that are
  always true or false (S2583); no assignments inside sub-expressions (S1121).

## Type design
- Classes with only static members have no public constructor (S1118); private classes that are not derived from are
  `sealed` (S3260); members that use no instance data are `static` (S2325).

## IDisposable
- Dispose what you create (S2930); implement the dispose pattern correctly when you implement `IDisposable` (S3881).

## Naming
- Types and members follow the repository's naming (S101, S100); no unused locals, parameters, or private members
  (S1481, S1172, S1144); no dead stores (S1854).

## Security
- No hard-coded credentials, secrets, or connection strings (S2068, S6418); no hard-coded IP addresses (S1313); strong
  cryptography and secure random where security depends on it (S5547, S4790, S2245); no SQL built from strings (S2077).

## Testing
- Every test asserts something (S2699); test classes contain tests (S2187); assertion arguments in the expected/actual
  order (S3415).

## Code style
- No commented-out code (S125); no new TODO or FIXME (S1135); no empty methods without a comment that says why (S1186).
- Follow `.editorconfig` and the analyzer configuration of the solution.

## Rules to confirm against the quality profile
Apply these only after confirming each is active in the project's quality profile (`activeInProject` of
`sonar -Repo <id> -Check rule -Key csharpsquid:<key>`, with its parameters, or the Sonar tools in chat); until then they
are code-quality guidance, never reported as SonarCloud findings.
- Validate arguments of public methods against null before use (S3900).
- Do not pass string literals as localized parameters (S4055): use the repository's existing constants or messages
  class as siblings do. Never add `.resx` files, a `ResourceManager`, or a localization framework for it; when only
  those would satisfy the rule, report the conflict instead.
- Keep cyclomatic complexity of methods within the profile's threshold (S1541).
- Keep a class coupled to a limited number of other classes; split responsibilities instead (S1200).
- Call the overload that takes an `IFormatProvider` when one exists, for example `string.Format(CultureInfo.InvariantCulture, ...)` (S4056).

## Build warnings (compiler and .NET analyzers, not Sonar rules)
Fix these from the build output and list them with the build results, never in the Sonar table:
- CS1572: an XML `<param>` names a parameter the method does not have; CS1573: a parameter has no `<param>` while
  others do. Update the documentation with the signature.
- CA1860: use `Count`, `Length`, or `IsEmpty` instead of `Any()` on collections that have them (`Any()` stays right for
  plain `IEnumerable<T>`, S1155).
- CA2254: the logging message template stays a constant with named placeholders (`"Deactivated {RequestId}"`, value as
  an argument); never build it with interpolation or concatenation. Keep event ids, levels, and property names.
- CA1303: a literal passed to a parameter marked localizable. Log messages are not user-facing; moving it to a
  `const` field does not resolve it (the analyzer checks the constant value). Fix it the way the module's existing code does, or report the conflict;
  never add `.resx` or a `ResourceManager` for it.

## Not Modern requirements unless the Modern configuration enforces them
Framework policy items (200-character lines, mandatory XML documentation on all public APIs, Framework registration conventions)
are not applied here by default.
