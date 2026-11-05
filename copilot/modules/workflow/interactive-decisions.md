# Interactive decisions (4.2.4)

Read only when a necessary user decision remains after current source, verified
repository evidence and valid same-task decisions have been checked. No routine
picker for a requirement that already determines the answer.

## Supported mechanism, not promised widgets

1. Inspect the host's actual exposed question tool/schema. When `ask_user` is
   available, use string enum/oneOf for single selection, array items.enum/anyOf
   for multi-selection, labels/descriptions and a default only where supported.
   The current VS Code host also accepts custom free text and accept/decline/cancel.
   Other hosts may expose different tools: use only their documented schema.
2. Radio buttons versus dropdowns, Previous/Next, custom fields and Submit are
   renderer features, not custom-agent Markdown APIs. Do not invent SDK methods,
   tool declarations, VSIX bridges or HTML chat cards. Tool schema availability
   does not certify that an actual Visual Studio widget rendered.
3. If native host input is unavailable and a local interactive Windows desktop
   and terminal are available, the optional installed
   `interaction/scripts/select.ps1 -Request <task-local-json>` returns native
   Windows Forms wizard choices as JSON. It is a **Windows modal fallback, not
   native Copilot Chat UI**. It supports radio/checkbox options, recommended
   defaults, Custom Answer, Previous/Next/Submit and Cancel. No listener, browser,
   VSIX installation or host API is required. Respect terminal/IDE prompts.
4. If neither mechanism is available, show numbered choices plus Custom Answer
   and Cancel; wait for the user's response. Label it text fallback, not a popup.

## Recommendations and sensitive decisions

Derive valid options from actual registered/active repository roots, PBI/task
state, branches, affected files, architecture, GraphQL contracts, validators
and known commands. Explain the recommendation with its evidence and tradeoff.
Preselect only a reversible non-approval choice when supported and evidence
justifies it; otherwise leave selection empty. Let the user change it or provide
a custom answer. Do not invent missing business rules or recommend an invalid
operation/schema/client alternative.

Use the same protocol for repository single/multi selection, PBI Resume/Modify/New,
implementation scope, approach, branch/base, business clarification, GraphQL
alternatives and test options. Reuse valid selected scope instead of prompting
once per repository/file. Ask related questions together where useful.

Implementation-plan, security, installation, deployment and destructive-operation
decisions are approval questions: **no preselected approval**, no timeout/default
acceptance, no recommendation that becomes permission. Offer explicit
Approve/Reject/Cancel (or Request changes/Other where appropriate), wait for an
actual submit and validate the scope. A custom answer is not approval unless it
unambiguously says so. Never run `decide`, install or deploy from a suggested value.

## Result handling and isolation

On SUBMITTED/accepted: validate selected values/custom text against the question,
reconcile changed scope, record the actual answer only in this task's existing
spec/plan or conversation, then continue automatically within authorized scope.
On Cancel: discard incomplete answers; do not record approval, change source or
repeat the picker. On decline: do not infer consent; continue only independent
authorized work. Errors are explicit blockers, never successful empty answers.
Revisit a resolved question only when evidence/scope materially changes.
New Chat inherits no task choice or approval; explicit resume is required.

The modal request format is JSON:

```json
{
  "taskId": "current-task",
  "questions": [
    {
      "id": "scope",
      "title": "Select implementation scope",
      "kind": "multiple",
      "options": [
        { "value": "backend", "label": "Backend" },
        { "value": "ui", "label": "UI" }
      ],
      "recommended": ["backend"],
      "reason": "The verified handler is backend-only.",
      "approval": false,
      "allowCustom": true
    }
  ]
}
```

`kind` is single/multiple; approval questions must be single. A multiple-choice
question may set `"allowEmpty": true` when selecting nothing is a valid answer
(for example optional test types); otherwise at least one choice or a Custom
Answer is required. Enter while typing a Custom Answer does not press Next or
Submit; the user moves on explicitly. The helper ignores
recommended selections for approval questions, returns no choices on cancellation,
does not save state and never executes the selected action. Use `-ValidateOnly`
to check a request without opening UI. Keep request files in existing task/session
evidence outside application source. Output `taskId` must match this request.
