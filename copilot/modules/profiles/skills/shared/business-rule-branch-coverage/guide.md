# Business rule branch coverage (shared, every profile)

> Profile skill `business-rule-branch-coverage`: Every approved business rule is checked branch by branch against the real code before it is called implemented; uncovered branches get the smallest safe change and a regression test.

A rule is not implemented because one of its branches is. Applies in every repository; the active profile decides in
which layer each branch belongs. Shipped baseline (see `profiles/README.md`).

## 1. Decision table (per approved rule)

Keep one row per path from the confirmed requirement, current source, and valid approved decisions. For PBI work,
use its existing spec/plan; direct fixes keep the affected branches in working context, not a planning document:

| Rule | Branch (condition) | Expected result | Owner today (`path:line` or "none found") | Test (`path:line` or "none") | Status |
|---|---|---|---|---|---|

Cover every kind of path the rule has: positive and negative outcome, each Yes/No answer, required fields, conditional
execution, duplicate detection, state transitions (from -> to), side effects (records created or changed, messages
sent), error behavior and failed downstream operations, and data consistency (what happens to work already done when a
later step fails; transaction boundaries). Status is **COVERED** (code and a test prove it), **PARTIAL** (code exists,
no test, or only some conditions), **MISSING**, or **UNKNOWN** (evidence not reachable; becomes a question).

## 2. Check each branch against the code

1. Reuse evidence already gathered for this task (the gap map, verified facts, `context` results); re-read a file only
   when its evidence is stale or the branch needs lines not read yet.
2. Follow only the execution path of the operation in question: entry point -> request -> validation -> handler or
   service -> data access -> response. Do not scan every handler, plugin, or workflow of the system.
3. Look for the branch where each layer could own it: validators, handlers, services and factories, collaborators,
   data access, and, where the profile allows it, platform-side logic such as plugins. Note duplicates and conflicts.
4. Never claim COVERED from a method name, a file name, or a comment; cite the condition and the test.

## 3. Close the gaps

For each PARTIAL or MISSING branch: state the missing behavior, its downstream effects (callers, contracts, data), the
existing code that can be reused or extended, and the smallest safe change in the layer the profile assigns. Add a test
per branch (data-driven when the rule is a table) that fails without the change. A branch whose expected result nobody
has approved is an unresolved business decision: ask, never invent it.

## 4. Legacy-derived rules

When the PBI says a rule comes from older logic (platform plugins, workflows, custom activities, client-side scripts,
web resources, another backend), read that source only for the rule it names, and only when its text or code is
available. Port the behavior, not the mechanism: no runtime dependency on the legacy platform, and no UI-only behavior
(field visibility, client formatting) reproduced in back-end code unless the PBI asks for it. Follow the active
profile's ownership rule for logic that the platform still executes.

## 5. Report

For PBI work, the decision table goes into the existing spec and plan's verification rows. Direct fixes report the
changed branches and actual test results without creating those documents. A branch left PARTIAL, MISSING, or UNKNOWN
keeps the work out of Ready; a test must have actually run before its branch is reported verified.
