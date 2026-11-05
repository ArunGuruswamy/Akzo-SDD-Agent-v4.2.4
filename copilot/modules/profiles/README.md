# Portable development profiles

The distributed registry is empty. Shared source-grounding and review policies apply without assuming a particular
application, solution name, layer or framework. `workset` detects workspace/project structure; `arch` provides Roslyn
or TypeScript evidence. Native multi-select is preferred for ambiguous scope, with numbered choices as fallback.

Optional team profiles can be defined in `{{AKZO_HOME}}/profiles-custom/profiles.json`, using the existing schema
(`shared`, `profiles`, solution/markers, skills, commands, review and risk rules). A profile is not architecture evidence.
The helper loads at most one explicitly matched profile per repository, never another repository's rules.
Generic technology guides under `skills/modern` and `skills/framework` are opt-in references, not default architectures.
Commands still require verification against the selected repository.

Save customized guides at the same relative path under `profiles-custom`. This directory and personal registrations
are not overwritten by upgrades. Existing custom files remain intact; associate them with an explicit team profile
when migrating from the former application-specific defaults.

Profiles are installed outside Copilot's discovery folders, so they cannot affect unrelated agents or New Chat.
Repository caches may be reused when valid; task decisions and approvals require explicit task resume.
