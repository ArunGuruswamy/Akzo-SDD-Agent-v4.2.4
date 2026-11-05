# Framework coverage

> Profile skill `framework-coverage`: Framework changed-code coverage target and how it is measured and reported. Load only when the helper's profile is framework.

Shipped baseline from the 3.6.0 brief (see `profiles/README.md`). Applies only when `profile` reports `framework`.

- Target: at least the repository's threshold (provisional default **85%**) line coverage of changed code where it can be measured:
  the server gate's coverage condition when SonarCloud answers, else `quality.coverage` in the registry, else 85% as a
  provisional objective (not an organizational requirement).
- Before adding tests for low SonarCloud coverage, check `sonar -Repo <id>` `coverageImport`: when the tests produce a
  format Sonar does not import (Cobertura while the pipeline reads OpenCover), fix the import, not the tests.
- Measure: run the tests with `--collect:"XPlat Code Coverage"` writing to the task's evidence folder, then
  `coverage -Repo <id> -Report "<evidence>\...\coverage.cobertura.xml"`. It returns coverable, covered, and uncovered
  changed lines and partly covered branches per file.
- Report the measured line coverage and the partly covered branches as the helper reports them. Never estimate or round up
  a number, and never report coverage for a run that did not finish.
- Below the target: add tests for the uncovered new behavior. Never exclude code from coverage or lower the target.
- SonarCloud's new-code coverage, when a server is configured, is reported separately and named as such.
