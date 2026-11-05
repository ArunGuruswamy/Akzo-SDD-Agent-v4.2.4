# .NET Framework architecture discovery

Optional reference, not a fixed application architecture. Use only when the user's selected projects confirm it.

- Evaluate SDK and non-SDK projects independently. Declared net4x does not prove references resolved successfully.
- Use the compatible framework BuildHost where installed; report partial/syntax analysis explicitly.
- Trace real project references, service interfaces, factories, DI registrations, API entry points and tests.
- XRM, EF, plugins and workflow activities are optional technologies: inspect them only when the affected execution
  path and package/source evidence actually use them.
- Resolve entity names, option values and validation ownership from source. Never invent them or duplicate a rule
  already enforced on the affected execution path.
- Do not impose CQRS, layered architecture, GraphQL or any other backend's conventions.
- Compare another implementation for behavior, then use this repository's proven patterns.
- Confirm separate Git roots, branches and file scope before any coordinated application changes.
