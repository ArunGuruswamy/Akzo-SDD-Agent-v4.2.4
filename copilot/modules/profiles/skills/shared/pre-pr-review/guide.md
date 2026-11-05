# Pre-PR review (shared, every profile)

> Profile skill `pre-pr-review`: Mandatory before development is marked complete and before "Fix PR comments" or "Review changes" finish. Reviews the actual diff for the recorded PR regression scenarios, architecture, validation, API compatibility, tests, documentation, and Sonar status.

Run on the real change, never on your memory of it. Shipped baseline (see `profiles/README.md`).

## 1. Mechanical review (helper)

`review -Repo <id> -Base <base branch>` compares the working tree with the merge base of `<base>` and HEAD, so committed
and uncommitted work on the feature branch are both reviewed. Without `-Base` it reviews uncommitted changes only and
says so. Every finding with severity `error` is fixed, or shown to be a false positive with the `path:line` that proves
it, before the change is Ready. Warnings are listed in the report.

## 2. Permanent regression scenarios (from earlier PR review comments)

The change is not complete while any of these is present:

| # | Scenario | What to check | Helper rule |
|---|---|---|---|
| 1 | Redundant validation exception conversion in a **PUT** function | The function catches the validation exception and builds its own response although the exception middleware already does | `redundant-validation-conversion` |
| 2 | The same in a **POST** function | as 1 | `redundant-validation-conversion` |
| 3 | Duplicate review changes | The same block added twice (two places, or one fix applied twice); a review comment answered twice | `duplicate-change` (code); comment threads are read by you |
| 4 | Validator not following the existing FluentValidation pattern | Base class, `RuleFor` rules, messages, and placement as in sibling validators | `validator-pattern` |
| 5 | Query and command dependency classes in the wrong place | A dependency under a command folder used by queries (or the reverse); a query type in a command folder | `dependency-organization` |
| 6 | Missing or outdated XML documentation (the case raised on a details factory) | Public members changed without `<summary>`, or `<param>` names that no longer match the parameters | `xml-doc-missing`, `xml-doc-outdated`, `xml-doc-incomplete` |

Before removing a function-level conversion (1, 2), trace the real path: function -> dispatcher -> handler -> validation
-> exception -> middleware -> HTTP response, and confirm the middleware response keeps the field name, the message, the
HTTP status, and the response contract the clients use. If it does not, the function-level translation stays.

## 3. Review categories (any feature, any PR)

These are reusable categories, not rules for one feature. Check the whole affected feature for each, not only the lines
a reviewer mentioned: naming against siblings; business validation in the wrong layer (source-grounded skill,
validation ownership); exception handling that bypasses or duplicates the existing middleware and error contract;
unnecessary collaborators, helpers, or duplicate interfaces (`single-use-abstraction`); wrong or missing dependency
registration and lifetimes; a query owned by the wrong layer or duplicated; incomplete XML documentation; missing tests;
Sonar rule violations; breaking API contract changes; uncovered business decision branches (business rule branch
coverage skill). A problem found once is searched for in the rest of the feature.

## 4. Reviewer judgement (you)

- Architecture boundaries of the active profile; nothing from the other profile.
- Validation rules and messages preserved; no duplicated validation in another layer.
- API contracts: before/after per changed endpoint and model; consumers checked.
- Tests: new behavior covered, including invalid input and dependency failure; no test weakened.
- Sonar: the profile's rule file applied to the changed code; the Sonar table filled with the source used. A local build
  does not show that SonarCloud passes; without a server result, say "SonarCloud not verified".
- No unrelated changes: every changed file is in the approved PBI scope or direct fix's affected-file list; no plan is
  created for a fix. Read the complete diff and untracked files, not only a helper summary.
- Architecture evidence: active solution and affected projects confirmed, changed Roslyn evidence refreshed, closest
  implementation and relevant execution links source-verified; unresolved semantic fallback remains UNVERIFIED.
- Final checks: actual build, required tests, Sonar/analyzer sources, changed-line coverage, layer/dependency direction,
  DI lifetimes and entry-point reachability, and diff verification. State commands/source, results, and blockers;
  no AI-only PASS. Concisely name reused symbols and justify necessary new classes.

## 5. Fixing review comments

Review-only or plan-first requests ("review", "analyse", "propose", "plan first", "before changing anything") stop after
the analysis: issues, file-by-file proposed changes, business-rule impact, regression risk, and the test and Sonar plan.
No application code changes until the developer approves. When implementation is already authorized and no business
decision is open, do not add an approval prompt.

1. Read each comment, the code it points at, the current diff, the tests, and the architecture it concerns, and name the
   underlying concern (not just the line).
2. Verify the comment against the system. Implement it only when the code proves it right; when it is wrong or would break
   a contract, reply with the evidence instead of changing code. Never apply a suggestion blindly.
3. Keep API response contracts and business behavior unless the comment is about them and the developer agrees.
4. Re-run build, the affected tests, and `review`.
5. Reply per comment in one or two sentences: what changed (`path:line`) and the check that proves it, or why nothing
   changed. Never claim a fix that is not in the diff. Every comment ends with a disposition (fixed, answered with
   evidence, or waiting for the developer); the same concern found elsewhere in the feature is listed with it.
