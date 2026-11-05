namespace Akzo.ArchitectureAnalyzer;

// The cached architecture index of one repository (index.json under the agent home, never in the repository).
public sealed class ArchIndex
{
    public int Schema { get; set; } = 1;
    public string Tool { get; set; } = "";
    public string Root { get; set; } = "";
    public string ScannedAt { get; set; } = "";
    public string InputsHash { get; set; } = "";   // project, solution, and build-configuration files: a change reloads everything
    public CoverageInfo Coverage { get; set; } = new();
    public List<SolutionInfo> Solutions { get; set; } = new();
    public List<ProjectInfo> Projects { get; set; } = new();
    public List<DocumentInfo> Documents { get; set; } = new();
    public List<PatternInfo> Patterns { get; set; } = new();
    public List<string> Conventions { get; set; } = new();
}

public sealed class CoverageInfo
{
    public int Projects { get; set; }
    public int Semantic { get; set; }
    public int Partial { get; set; }
    public int Syntax { get; set; }
    public int Documents { get; set; }
    public string Summary { get; set; } = "";
}

public sealed class SolutionInfo
{
    public string Path { get; set; } = "";
    public List<string> Projects { get; set; } = new();
}

public sealed class ProjectInfo
{
    public string Name { get; set; } = "";
    public string Path { get; set; } = "";
    public string Style { get; set; } = "";                          // sdk | legacy
    public List<string> TargetFrameworks { get; set; } = new();       // declared (project file or Directory.Build.props)
    public string? ResolvedFramework { get; set; }                    // from the reference assemblies a load resolved
    public List<string> ProjectReferences { get; set; } = new();
    public List<string> Packages { get; set; } = new();
    public bool Test { get; set; }
    public string Analysis { get; set; } = "syntax";                  // semantic | partial | syntax
    public List<string> LoadErrors { get; set; } = new();
    public int CompilationErrors { get; set; }
    public List<string> CompilationDiagnostics { get; set; } = new();
}

public sealed class DocumentInfo
{
    public string Path { get; set; } = "";
    public string Hash { get; set; } = "";
    public string Project { get; set; } = "";
    public string Analysis { get; set; } = "syntax";
    public List<SymbolInfo> Symbols { get; set; } = new();
    public List<CallInfo> Calls { get; set; } = new();
    public List<RegistrationInfo> Registrations { get; set; } = new();
    public List<TestInfo> Tests { get; set; } = new();
    public List<string> Unresolved { get; set; } = new();
    public List<ValidationInfo> Validation { get; set; } = new();   // FluentValidation API use: registration, invocation, async rules
    public string? Surface { get; set; }   // hash of the declarations without bodies; null when directives make it unsafe to compare
}

public sealed class ValidationInfo
{
    public string Kind { get; set; } = "";     // registration | validate-sync | validate-async | async-rule
    public string Method { get; set; } = "";
    public string? Model { get; set; }         // the validated type id; "<generic>" for an open pipeline; null when unknown
    public int Line { get; set; }
}

public sealed class SymbolInfo
{
    public string Id { get; set; } = "";
    public string Kind { get; set; } = "";
    public string Name { get; set; } = "";
    public string? Namespace { get; set; }
    public string? Container { get; set; }
    public int Line { get; set; }
    public int EndLine { get; set; }
    public string? Signature { get; set; }
    public string? Base { get; set; }
    public List<string>? Interfaces { get; set; }
    public string? BaseId { get; set; }
    public List<string>? InterfaceIds { get; set; }
    public List<string>? Attributes { get; set; }
    public List<string>? Dependencies { get; set; }
    public List<string>? DependencyIds { get; set; }
}

public sealed class CallInfo
{
    public string From { get; set; } = "";
    public string To { get; set; } = "";
    public int Line { get; set; }
}

public sealed class RegistrationInfo
{
    public string Service { get; set; } = "";
    public string? Implementation { get; set; }
    public string Lifetime { get; set; } = "";
    public int Line { get; set; }
}

public sealed class TestInfo
{
    public string Test { get; set; } = "";
    public List<string> Covers { get; set; } = new();   // type ids; '~Name' when only the name is known (syntax analysis)
    public int Line { get; set; }
}

public sealed class PatternInfo
{
    public string Name { get; set; } = "";
    public bool Observed { get; set; }
    public int Count { get; set; }
    public List<string> Evidence { get; set; } = new();
    public string Basis { get; set; } = "";
}
