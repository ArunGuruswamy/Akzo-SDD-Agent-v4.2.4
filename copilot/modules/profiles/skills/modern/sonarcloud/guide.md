# Modern SonarCloud

> Profile skill `modern-sonarcloud`: Modern SonarCloud rules and how their status is reported. Load only when the helper's profile is modern.

Shipped baseline from the 3.6.0 brief (see `profiles/README.md`). Applies only when `profile` reports `modern`.

- Rule catalog: `instructions/modern/sonar-rules.instructions.md`, or its profiles-custom replacement. Apply it while
  writing code, not only afterwards.
- Framework-only requirements (200-character lines, mandatory XML documentation on every public API, the optional-parameter
  and parameter-name rules as Framework policy) are **not** Modern requirements unless the Modern analyzer configuration or quality
  profile enforces them.
- Check the real configuration first: `sonar -Repo <id>` (project key, analyzers, rule configuration, exclusions),
  `.editorconfig`, `Directory.Build.props`, rule sets.
- Report the source of every Sonar result (agent section 6a). Local build warnings are analyzer results, not a SonarCloud
  analysis; without a server result write "SonarCloud: not verified - <reason>".
- Never suppress, exclude, or downgrade a rule to pass.
