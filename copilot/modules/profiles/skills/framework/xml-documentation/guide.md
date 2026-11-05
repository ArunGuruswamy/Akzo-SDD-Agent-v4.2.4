# Framework XML documentation

> Profile skill `framework-xml-documentation`: Framework XML documentation policy for new and changed public production APIs. Load only when the helper's profile is framework.

Shipped baseline from the 3.6.0 brief; the team's Framework policy in profiles-custom replaces it (see `profiles/README.md`).
Applies only when `profile` reports `framework`.

- **Required** on every new or changed public type and public member in production code: `<summary>`, a `<param>` for each
  parameter (names exactly as in the signature), `<returns>` for non-void members, and `<exception>` for exceptions the
  member throws on purpose. `<inheritdoc/>` is acceptable where the siblings use it for interface implementations.
- **Excluded:** test code, and internal or private members.
- Accurate, not ceremonial: say what the member does and what the caller must know. When a signature changes, update its
  documentation in the same edit (an outdated `<param>` was raised in an earlier PR review on a details factory).
- `review -Repo <id>` reports `xml-doc-missing`, `xml-doc-outdated`, and `xml-doc-incomplete` for changed public members.
