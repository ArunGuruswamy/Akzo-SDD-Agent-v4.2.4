using System.Collections.Concurrent;
using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Xml.Linq;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;
using Microsoft.CodeAnalysis.MSBuild;

namespace Akzo.ArchitectureAnalyzer;

// Discovery, loading, and extraction. A project MSBuild loads is analyzed semantically (symbols, calls, DI registrations,
// and tests resolved by the compiler); a project it cannot load is parsed with Roslyn's parser only and marked "syntax".
// Unchanged documents keep their cached results; a changed project, solution, or build-configuration file rescans all.
public static class Scanner
{
    internal static readonly HashSet<string> SkipDirs = new(StringComparer.OrdinalIgnoreCase) { ".git", "bin", "obj", "node_modules", "packages", ".vs", ".idea", "TestResults" };
    static readonly Regex InputFile = new(@"(\.csproj|\.sln|\.slnx|(^|/)Directory\.(Build|Packages)\.(props|targets)|(^|/)global\.json|(^|/)packages\.config|(^|/)nuget\.config)$", RegexOptions.IgnoreCase);
    static readonly Regex TestAttribute = new("^(Fact|Theory|Test|TestCase|TestCaseSource|TestMethod|DataTestMethod)$");
    static readonly Regex Registration = new("^(TryAdd|Add)(Scoped|Transient|Singleton|HostedService)$");
    internal static readonly StringComparer Paths = StringComparer.OrdinalIgnoreCase;
    internal static readonly JsonSerializerOptions Json = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase, DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull };

    public static async Task<(ArchIndex Index, Dictionary<string, object?> Summary)> ScanAsync(string root, string outDir, bool syntaxOnly)
    {
        var clock = Stopwatch.StartNew();
        root = Path.GetFullPath(root).TrimEnd('\\', '/');
        var cacheRoot = Path.GetFullPath(outDir).TrimEnd('\\', '/');
        if (Paths.Equals(root, cacheRoot) || cacheRoot.StartsWith(root + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Architecture cache must be outside the analyzed repository.");
        var files = Discover(root);
        var cs = files.Where(f => f.EndsWith(".cs", StringComparison.OrdinalIgnoreCase)).ToList();
        var inputs = files.Where(f => InputFile.IsMatch(f)).ToList();
        var hashes = new ConcurrentDictionary<string, string>(Paths);
        Parallel.ForEach(cs.Concat(inputs), f => hashes[f] = Sha(File.ReadAllBytes(Full(root, f))));
        var inputsHash = Sha(Encoding.UTF8.GetBytes(string.Join("\n", inputs.OrderBy(f => f, Paths).Select(f => $"{f}={hashes[f]}")) + $"\nsyntaxOnly={syntaxOnly}\nanalyzer={typeof(Scanner).Assembly.ManifestModule.ModuleVersionId}\nhost={BuildHostStaging.Fingerprint}"));
        var prev = Read(Path.Combine(outDir, "index.json"), root);
        var full = prev == null || prev.InputsHash != inputsHash;
        var prevDocs = prev?.Documents.ToDictionary(d => d.Path, Paths) ?? new Dictionary<string, DocumentInfo>(Paths);
        var changed = cs.Where(f => full || !prevDocs.TryGetValue(f, out var d) || d.Hash != hashes[f]).ToList();
        var csSet = new HashSet<string>(cs, Paths);
        var removed = prevDocs.Keys.Count(k => !csSet.Contains(k));
        var summary = new Dictionary<string, object?> { ["status"] = "SCANNED", ["full"] = full, ["changedDocuments"] = changed.Count, ["removedDocuments"] = removed };
        if (prev != null && !full && changed.Count == 0 && removed == 0)
        {
            summary["status"] = "UP_TO_DATE"; summary["elapsedMs"] = clock.ElapsedMilliseconds;
            return (prev, summary);
        }
        var projects = full || prev == null ? ReadProjects(root, files) : prev.Projects;
        var owner = Owners(root, cs, projects);
        var affected = new HashSet<string>(full ? projects.Select(p => p.Path) :
            changed.Select(f => owner.GetValueOrDefault(f)).OfType<string>()
                .Concat(prevDocs.Values.Where(d => !csSet.Contains(d.Path)).Select(d => d.Project)), Paths);
        // An edit confined to member bodies keeps every declaration, so other projects' bindings cannot change: only
        // projects whose declarations changed (or lost a file) pull their dependents, transitively, into the reload.
        var bodyOnly = new HashSet<string>(Paths);
        if (!full && !syntaxOnly)
        {
            foreach (var f in changed)
                if (prevDocs.TryGetValue(f, out var old) && old.Surface != null && old.Surface == Surface(CSharpSyntaxTree.ParseText(File.ReadAllText(Full(root, f))).GetRoot()))
                    bodyOnly.Add(f);
            var surfaceChanged = new HashSet<string>(changed.Where(f => !bodyOnly.Contains(f)).Select(f => owner.GetValueOrDefault(f)).OfType<string>()
                .Concat(prevDocs.Values.Where(d => !csSet.Contains(d.Path)).Select(d => d.Project)), Paths);
            bool added;
            do
            {
                added = false;
                foreach (var p in projects)
                    if (!surfaceChanged.Contains(p.Path) && p.ProjectReferences.Any(surfaceChanged.Contains))
                    {
                        surfaceChanged.Add(p.Path); affected.Add(p.Path); added = true;
                    }
            } while (added);
        }
        summary["bodyOnlyDocuments"] = bodyOnly.Count;
        var todo = new HashSet<string>(changed, Paths);
        if (!syntaxOnly)
            foreach (var f in cs)
                if (owner.TryGetValue(f, out var project) && affected.Contains(project)) todo.Add(f);
        summary["revalidatedDocuments"] = todo.Count;
        summary["affectedProjects"] = affected.ToList();
        var extracted = new ConcurrentDictionary<string, DocumentInfo>(Paths);
        if (syntaxOnly)
        {
            foreach (var p in projects) { p.Analysis = "syntax"; p.LoadErrors = new() { "semantic analysis not requested (--syntax-only)" }; }
        }
        else if (affected.Count > 0)
        {
            using var ws = MSBuildWorkspace.Create();
            var failures = new ConcurrentBag<string>();
#pragma warning disable CS0618 // the event is the failure API this Roslyn version offers on every target
            ws.WorkspaceFailed += (_, e) => failures.Add(e.Diagnostic.Message);
#pragma warning restore CS0618
            foreach (var p in affected)
            {
                var path = Full(root, p);
                if (ws.CurrentSolution.Projects.Any(x => Paths.Equals(x.FilePath, path))) continue;   // loaded as another project's reference
                try { await ws.OpenProjectAsync(path); } catch (Exception ex) { failures.Add($"{path}: {ex}"); }
            }
            var byPath = projects.ToDictionary(p => p.Path, Paths);
            var work = new List<(Document Doc, string Rel, string Project, string Analysis)>();
            var seen = new HashSet<string>(Paths);
            foreach (var rp in ws.CurrentSolution.Projects)
            {
                if (!byPath.TryGetValue(Rel(root, rp.FilePath ?? ""), out var info)) continue;
                var comp = await rp.GetCompilationAsync();
                var core = comp?.GetSpecialType(SpecialType.System_Object);
                info.Analysis = core == null || core.TypeKind == TypeKind.Error ? "partial" : "semantic";   // partial: the framework references did not resolve
                var errors = comp?.GetDiagnostics().Where(d => d.Severity == DiagnosticSeverity.Error).ToList() ?? new();
                info.CompilationErrors = errors.Count;
                info.CompilationDiagnostics = errors.Take(5).Select(d => d.ToString()).ToList();
                info.ProjectReferences = rp.ProjectReferences.Select(r => ws.CurrentSolution.GetProject(r.ProjectId)?.FilePath)
                    .OfType<string>().Select(p => Rel(root, p)).Distinct(Paths).ToList();
                info.ResolvedFramework = Framework(rp.MetadataReferences) ?? info.ResolvedFramework;
                foreach (var d in rp.Documents)
                {
                    var rel = Rel(root, d.FilePath ?? "");
                    if (todo.Contains(rel) && seen.Add(rel)) work.Add((d, rel, info.Path, info.Analysis));   // a multi-targeted project's documents once
                }
            }
            foreach (var p in projects.Where(p => affected.Contains(p.Path)))
            {
                var path = Full(root, p.Path);
                p.LoadErrors = failures.Where(m => m.Contains(path, StringComparison.OrdinalIgnoreCase)).Distinct().Take(5).ToList();
                if (!ws.CurrentSolution.Projects.Any(x => Paths.Equals(x.FilePath, path)))
                {
                    p.Analysis = "syntax";
                    if (p.LoadErrors.Count == 0) p.LoadErrors.Add(failures.FirstOrDefault() ?? "MSBuild did not load the project");
                }
                else if (p.Analysis == "partial" && p.LoadErrors.Count == 0) p.LoadErrors.Add("framework references not resolved: restore or build the project for full semantic analysis");
            }
            using var slots = new SemaphoreSlim(Math.Max(1, Environment.ProcessorCount));
            await Task.WhenAll(work.Select(async w =>
            {
                await slots.WaitAsync();
                try { extracted[w.Rel] = await Semantic(w.Doc, w.Rel, hashes[w.Rel], w.Project, w.Analysis); }
                catch (Exception ex)
                {
                    failures.Add($"{Full(root, w.Rel)}: semantic extraction failed: {ex}");
                    lock (byPath[w.Project].LoadErrors) byPath[w.Project].LoadErrors.Add($"semantic extraction failed for {w.Rel}: {ex}");
                    extracted[w.Rel] = Syntactic(File.ReadAllText(Full(root, w.Rel)), w.Rel, hashes[w.Rel], w.Project);
                }
                finally { slots.Release(); }
            }));
        }
        Parallel.ForEach(todo.Where(f => !extracted.ContainsKey(f)), f =>   // not in a loaded project: Roslyn's parser only
            extracted[f] = Syntactic(File.ReadAllText(Full(root, f)), f, hashes[f], owner.GetValueOrDefault(f) ?? ""));
        var docs = new Dictionary<string, DocumentInfo>(Paths);
        if (!full && prev != null) foreach (var d in prev.Documents) if (csSet.Contains(d.Path) && !todo.Contains(d.Path)) docs[d.Path] = d;
        foreach (var d in extracted.Values) docs[d.Path] = d;
        var index = new ArchIndex
        {
            Tool = $"Akzo.ArchitectureAnalyzer {typeof(Scanner).Assembly.GetName().Version} (Roslyn {typeof(CSharpSyntaxTree).Assembly.GetName().Version})",
            Root = root, ScannedAt = DateTime.Now.ToString("s"), InputsHash = inputsHash,
            Solutions = ReadSolutions(root, files), Projects = projects, Documents = docs.Values.OrderBy(d => d.Path, Paths).ToList(),
        };
        Analyze(index, files.Where(f => f.EndsWith(".graphql", StringComparison.OrdinalIgnoreCase)).ToList());
        Directory.CreateDirectory(outDir);
        var target = Path.Combine(outDir, "index.json");
        var pending = target + "." + Guid.NewGuid().ToString("N");
        try
        {
            File.WriteAllText(pending, JsonSerializer.Serialize(index, Json));
            if (File.Exists(target)) File.Replace(pending, target, null);
            else
            {
                try { File.Move(pending, target); }
                catch (IOException) when (File.Exists(target)) { File.Replace(pending, target, null); }
            }
        }
        finally { if (File.Exists(pending)) File.Delete(pending); }
        summary["elapsedMs"] = clock.ElapsedMilliseconds;
        return (index, summary);
    }

    public static ArchIndex? Read(string path, string? root)
    {
        try
        {
            if (!File.Exists(path)) return null;
            var ix = JsonSerializer.Deserialize<ArchIndex>(File.ReadAllText(path), Json);
            return ix == null || ix.Schema != 1 || (root != null && !Paths.Equals(ix.Root, root)) ? null : ix;
        }
        catch { return null; }   // unreadable: rescan
    }

    static List<string> Discover(string root)
    {
        var list = new List<string>();
        var stack = new Stack<string>(); stack.Push(root);
        while (stack.Count > 0)
        {
            var dir = stack.Pop();
            string[] subs, fs;
            try { subs = Directory.GetDirectories(dir); fs = Directory.GetFiles(dir); } catch { continue; }
            foreach (var d in subs)
                if (!SkipDirs.Contains(Path.GetFileName(d)) && !new DirectoryInfo(d).Attributes.HasFlag(FileAttributes.ReparsePoint)) stack.Push(d);
            foreach (var f in fs)
            {
                var rel = Rel(root, f);
                if (rel.EndsWith(".cs", StringComparison.OrdinalIgnoreCase) || rel.EndsWith(".graphql", StringComparison.OrdinalIgnoreCase) || InputFile.IsMatch(rel)) list.Add(rel);
            }
        }
        return list;
    }

    static List<SolutionInfo> ReadSolutions(string root, List<string> files)
    {
        var list = new List<SolutionInfo>();
        foreach (var f in files.Where(f => f.EndsWith(".sln", StringComparison.OrdinalIgnoreCase) || f.EndsWith(".slnx", StringComparison.OrdinalIgnoreCase)))
        {
            var dir = Path.GetDirectoryName(Full(root, f))!;
            var text = File.ReadAllText(Full(root, f));
            var refs = f.EndsWith(".slnx", StringComparison.OrdinalIgnoreCase)
                ? Regex.Matches(text, @"<Project\s[^>]*Path=""([^""]+\.csproj)""", RegexOptions.IgnoreCase).Cast<Match>().Select(m => m.Groups[1].Value)
                : Regex.Matches(text, @"^Project\(""[^""]+""\)\s*=\s*""[^""]*"",\s*""([^""]+\.csproj)""", RegexOptions.Multiline | RegexOptions.IgnoreCase).Cast<Match>().Select(m => m.Groups[1].Value);
            list.Add(new SolutionInfo { Path = f, Projects = refs.Select(r => Rel(root, Path.GetFullPath(Path.Combine(dir, r)))).ToList() });
        }
        return list;
    }

    static List<ProjectInfo> ReadProjects(string root, List<string> files)
    {
        var central = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);   // Directory.Packages.props
        foreach (var f in files.Where(f => Path.GetFileName(f).Equals("Directory.Packages.props", StringComparison.OrdinalIgnoreCase)))
            try { foreach (var e in XDocument.Load(Full(root, f)).Descendants().Where(e => e.Name.LocalName == "PackageVersion")) central[e.Attribute("Include")?.Value ?? ""] = e.Attribute("Version")?.Value ?? ""; } catch { }
        var list = new List<ProjectInfo>();
        foreach (var f in files.Where(f => f.EndsWith(".csproj", StringComparison.OrdinalIgnoreCase)))
        {
            var info = new ProjectInfo { Name = Path.GetFileNameWithoutExtension(f), Path = f };
            list.Add(info);
            XElement el;
            try { el = XDocument.Load(Full(root, f)).Root!; } catch (Exception ex) { info.LoadErrors.Add("project file unreadable: " + ex.Message); continue; }
            string Prop(XElement x, string n) => x.Descendants().FirstOrDefault(e => e.Name.LocalName == n)?.Value.Trim() ?? "";
            info.Style = el.Attribute("Sdk") != null || el.Elements().Any(e => e.Name.LocalName == "Sdk" || (e.Name.LocalName == "Import" && e.Attribute("Sdk") != null)) ? "sdk" : "legacy";
            var tf = Prop(el, "TargetFrameworks");
            if (tf == "") tf = Prop(el, "TargetFramework");
            if (tf == "" && Prop(el, "TargetFrameworkVersion") is { Length: > 0 } v) tf = "net" + v.TrimStart('v', 'V').Replace(".", "");
            for (var d = Path.GetDirectoryName(Full(root, f)); tf == "" && d != null && d.Length >= root.Length; d = Path.GetDirectoryName(d))   // set centrally
            {
                var props = Path.Combine(d, "Directory.Build.props");
                if (!File.Exists(props)) continue;
                try { var x = XDocument.Load(props).Root!; tf = Prop(x, "TargetFrameworks"); if (tf == "") tf = Prop(x, "TargetFramework"); } catch { }
            }
            info.TargetFrameworks = Compatibility.SplitTrim(tf, ';').ToList();
            var dir = Path.GetDirectoryName(Full(root, f))!;
            info.ProjectReferences = el.Descendants().Where(e => e.Name.LocalName == "ProjectReference")
                .Select(e => e.Attribute("Include")?.Value).OfType<string>().Select(r => Rel(root, Path.GetFullPath(Path.Combine(dir, r.Replace('\\', Path.DirectorySeparatorChar))))).ToList();
            foreach (var e in el.Descendants().Where(e => e.Name.LocalName == "PackageReference"))
            {
                var id = e.Attribute("Include")?.Value ?? "";
                var ver = e.Attribute("Version")?.Value ?? e.Elements().FirstOrDefault(c => c.Name.LocalName == "Version")?.Value ?? e.Attribute("VersionOverride")?.Value ?? central.GetValueOrDefault(id);
                if (id != "") info.Packages.Add(string.IsNullOrEmpty(ver) ? id : $"{id} {ver}");
            }
            var pc = Path.Combine(dir, "packages.config");   // legacy NuGet
            if (File.Exists(pc)) try { foreach (var e in XDocument.Load(pc).Descendants("package")) info.Packages.Add($"{e.Attribute("id")?.Value} {e.Attribute("version")?.Value}"); } catch { }
            var refs = el.Descendants().Where(e => e.Name.LocalName == "Reference").Select(e => e.Attribute("Include")?.Value ?? "");
            info.Test = info.Packages.Concat(refs).Any(p => Regex.IsMatch(p, @"^(xunit|nunit|MSTest|Microsoft\.NET\.Test\.Sdk|Microsoft\.VisualStudio\.(QualityTools\.UnitTestFramework|TestPlatform\.TestFramework))", RegexOptions.IgnoreCase))
                || Prop(el, "IsTestProject").Equals("true", StringComparison.OrdinalIgnoreCase) || Regex.IsMatch(info.Name, @"\.(Unit)?Tests?$", RegexOptions.IgnoreCase);
        }
        return list;
    }

    // Each source file belongs to the nearest project folder above it; a legacy project's explicit Compile items win.
    static Dictionary<string, string> Owners(string root, List<string> cs, List<ProjectInfo> projects)
    {
        var dirs = projects.Select(p => (Dir: Path.GetDirectoryName(p.Path)?.Replace('\\', '/') ?? "", p.Path)).OrderByDescending(x => x.Dir.Length).ToList();
        var map = new Dictionary<string, string>(Paths);
        foreach (var f in cs)
        {
            var hit = dirs.FirstOrDefault(d => d.Dir == "" || f.StartsWith(d.Dir + "/", StringComparison.OrdinalIgnoreCase));
            if (hit.Path != null) map[f] = hit.Path;
        }
        foreach (var p in projects.Where(p => p.Style == "legacy"))
        {
            var dir = Path.GetDirectoryName(Full(root, p.Path))!;
            try
            {
                foreach (var e in XDocument.Load(Full(root, p.Path)).Descendants().Where(e => e.Name.LocalName == "Compile" && e.Attribute("Include") != null))
                    map[Rel(root, Path.GetFullPath(Path.Combine(dir, e.Attribute("Include")!.Value.Replace('\\', Path.DirectorySeparatorChar))))] = p.Path;
            }
            catch { }
        }
        return map;
    }

    static string? Framework(IEnumerable<MetadataReference> refs)   // the framework the load resolved, from its core reference assembly
    {
        foreach (var r in refs.OfType<PortableExecutableReference>())
        {
            var p = r.FilePath ?? "";
            if (!Regex.IsMatch(Path.GetFileName(p), @"^(System\.Runtime|mscorlib|netstandard)\.dll$", RegexOptions.IgnoreCase)) continue;
            var m = Regex.Match(p, @"[\\/]\.NETFramework[\\/]v(\d+)\.(\d+)(?:\.(\d+))?[\\/]", RegexOptions.IgnoreCase);
            if (m.Success) return $"net{m.Groups[1].Value}{m.Groups[2].Value}{m.Groups[3].Value} (.NET Framework {m.Groups[1].Value}.{m.Groups[2].Value}{(m.Groups[3].Success ? "." + m.Groups[3].Value : "")} reference assemblies)";
            m = Regex.Match(p, @"[\\/]([^\\/]+)[\\/]([^\\/]+)[\\/]ref[\\/](net\d+\.\d+|netstandard\d+\.\d+|netcoreapp\d+\.\d+)[\\/]", RegexOptions.IgnoreCase);
            if (m.Success) return $"{m.Groups[3].Value} ({m.Groups[1].Value} {m.Groups[2].Value})";
        }
        return null;
    }

    static async Task<DocumentInfo> Semantic(Document doc, string rel, string hash, string project, string analysis)
    {
        var root = await doc.GetSyntaxRootAsync() ?? throw new InvalidOperationException("no syntax");
        var model = await doc.GetSemanticModelAsync() ?? throw new InvalidOperationException("no semantic model");
        var info = new DocumentInfo { Path = rel, Hash = hash, Project = project, Analysis = analysis, Surface = Surface(root) };
        foreach (var node in root.DescendantNodes())
        {
            if (node is BaseTypeDeclarationSyntax t && model.GetDeclaredSymbol(t) is INamedTypeSymbol ts) info.Symbols.Add(TypeSymbol(ts, t));
            else if (node is BaseMethodDeclarationSyntax m && model.GetDeclaredSymbol(m) is IMethodSymbol ms && Identity(ms) is string id)
            {
                info.Symbols.Add(new SymbolInfo
                {
                    Id = id, Kind = ms.MethodKind == MethodKind.Constructor ? "constructor" : "method",
                    Name = ms.MethodKind == MethodKind.Constructor ? ms.ContainingType.Name : ms.Name,
                    Container = ms.ContainingType == null ? null : Identity(ms.ContainingType), Line = Line(NameToken(m)), EndLine = EndLine(m),
                    Signature = ms.ToDisplayString(SymbolDisplayFormat.MinimallyQualifiedFormat), Attributes = NullIfEmpty(ms.GetAttributes().Select(a => Short(a.AttributeClass?.Name))),
                });
                var body = (SyntaxNode?)m.Body ?? m.ExpressionBody;
                if (body == null) continue;
                Calls(info, model, body, id);
                if (ms.ContainingType is { } self && ms.GetAttributes().Any(a => TestAttribute.IsMatch(Short(a.AttributeClass?.Name)))) info.Tests.Add(new TestInfo { Test = id, Line = Line(NameToken(m)), Covers = Covered(model, body, self) });
            }
            else if (node is InvocationExpressionSyntax inv)
            {
                if (RegistrationOf(inv, x => model.GetTypeInfo(x).Type) is RegistrationInfo reg) info.Registrations.Add(reg);
                else if (inv.Expression is MemberAccessExpressionSyntax ma && ma.Name.Identifier.Text is
                    "WithScopedLifetime" or "WithSingletonLifetime" or "WithTransientLifetime")
                    ScanRegistrations(info, model, inv);
                ValidationUse(info, inv, model);
            }
        }
        foreach (var g in root.ChildNodes().OfType<GlobalStatementSyntax>()) Calls(info, model, g, $"top-level:{rel}");   // Program.cs top-level statements
        info.Calls = info.Calls.GroupBy(c => (c.From, c.To)).Select(g => g.First()).ToList();
        return info;
    }

    static void Calls(DocumentInfo info, SemanticModel model, SyntaxNode body, string from)
    {
        foreach (var n in body.DescendantNodes())
        {
            if (n is not (InvocationExpressionSyntax or BaseObjectCreationExpressionSyntax)) continue;
            var si = model.GetSymbolInfo(n);
            if ((si.Symbol ?? si.CandidateSymbols.FirstOrDefault()) is not IMethodSymbol s) continue;
            s = (s.ReducedFrom ?? s).OriginalDefinition;
            if (!s.Locations.Any(l => l.IsInSource) || Identity(s) is not string to) continue;   // calls into this repository's code only
            info.Calls.Add(new CallInfo { From = from, To = to, Line = Line(n) });
        }
    }

    static List<string> Covered(SemanticModel model, SyntaxNode body, INamedTypeSymbol self)   // the repository types a test uses
    {
        var list = new List<string>();
        foreach (var n in body.DescendantNodes().OfType<SimpleNameSyntax>())
        {
            var s = model.GetSymbolInfo(n).Symbol;
            var t = s as INamedTypeSymbol ?? s?.ContainingType;
            if (t == null || SymbolEqualityComparer.Default.Equals(t, self) || !t.Locations.Any(l => l.IsInSource)) continue;
            if (Identity(t) is string id && !list.Contains(id)) list.Add(id);
            if (list.Count == 10) break;
        }
        return list;
    }

    static SymbolInfo TypeSymbol(INamedTypeSymbol ts, BaseTypeDeclarationSyntax t) => new()
    {
        Id = Identity(ts) ?? ts.ToDisplayString(), Kind = Kind(t), Name = ts.Name,
        Namespace = ts.ContainingNamespace is { IsGlobalNamespace: false } ns ? ns.ToDisplayString() : null,
        Container = ts.ContainingType == null ? null : Identity(ts.ContainingType), Line = Line(t.Identifier), EndLine = EndLine(t),
        BaseId = ts.BaseType is { } parent && parent.SpecialType is not (SpecialType.System_Object or SpecialType.System_ValueType or SpecialType.System_Enum) ? Identity(parent) : null,
        InterfaceIds = NullIfEmpty(ts.AllInterfaces.Select(Identity).OfType<string>()),
        DependencyIds = NullIfEmpty(ts.InstanceConstructors.SelectMany(c => c.Parameters).Select(p => Identity(p.Type)).OfType<string>()),
        Base = ts.BaseType is { } b && b.SpecialType is not (SpecialType.System_Object or SpecialType.System_ValueType or SpecialType.System_Enum) ? b.ToDisplayString() : null,
        Interfaces = NullIfEmpty(ts.Interfaces.Select(i => i.ToDisplayString())),
        Attributes = NullIfEmpty(ts.GetAttributes().Select(a => Short(a.AttributeClass?.Name))),
        Dependencies = NullIfEmpty(ts.InstanceConstructors.Where(c => !c.IsImplicitlyDeclared).SelectMany(c => c.Parameters).Select(p => p.Type.ToDisplayString())),
    };

    static DocumentInfo Syntactic(string text, string rel, string hash, string project)
    {
        var root = CSharpSyntaxTree.ParseText(text).GetCompilationUnitRoot();
        var info = new DocumentInfo { Path = rel, Hash = hash, Project = project, Analysis = "syntax", Surface = Surface(root) };
        foreach (var node in root.DescendantNodes())
        {
            if (node is BaseTypeDeclarationSyntax t)
            {
                var ctorParams = t is TypeDeclarationSyntax td
                    ? td.Members.OfType<ConstructorDeclarationSyntax>().SelectMany(c => c.ParameterList.Parameters).Concat(td.ParameterList?.Parameters ?? default).Select(p => p.Type?.ToString() ?? "")
                    : Enumerable.Empty<string>();
                info.Symbols.Add(new SymbolInfo
                {
                    Id = "T:" + QualifiedName(t), Kind = Kind(t), Name = t.Identifier.Text, Namespace = Namespace(t),
                    Container = t.Parent is BaseTypeDeclarationSyntax p ? "T:" + QualifiedName(p) : null, Line = Line(t.Identifier), EndLine = EndLine(t),
                    Interfaces = NullIfEmpty(t.BaseList?.Types.Select(b => b.Type.ToString()) ?? Enumerable.Empty<string>()), Attributes = NullIfEmpty(Attributes(t.AttributeLists)), Dependencies = NullIfEmpty(ctorParams),
                });
            }
            else if (node is BaseMethodDeclarationSyntax m && m.Parent is BaseTypeDeclarationSyntax owner)
            {
                var ctor = m is ConstructorDeclarationSyntax;
                var name = m is MethodDeclarationSyntax md ? md.Identifier.Text : owner.Identifier.Text;
                var id = $"M:{QualifiedName(owner)}.{(ctor ? "#ctor" : name)}({string.Join(",", m.ParameterList.Parameters.Select(p => p.Type?.ToString()))})";
                var attrs = Attributes(m.AttributeLists).ToList();
                info.Symbols.Add(new SymbolInfo
                {
                    Id = id, Kind = ctor ? "constructor" : "method", Name = name, Container = "T:" + QualifiedName(owner), Line = Line(NameToken(m)), EndLine = EndLine(m),
                    Signature = $"{(m as MethodDeclarationSyntax)?.ReturnType} {name}{m.ParameterList}".Trim(), Attributes = NullIfEmpty(attrs),
                });
                if (attrs.Any(a => TestAttribute.IsMatch(a)) && ((SyntaxNode?)m.Body ?? m.ExpressionBody) is SyntaxNode body)
                    info.Tests.Add(new TestInfo { Test = id, Line = Line(NameToken(m)), Covers = body.DescendantNodes().OfType<IdentifierNameSyntax>().Select(i => i.Identifier.Text).Where(n => n.Length > 2 && char.IsUpper(n[0])).Distinct().Take(15).Select(n => "~" + n).ToList() });
            }
            else if (node is InvocationExpressionSyntax inv)
            {
                if (RegistrationOf(inv, null) is RegistrationInfo reg) info.Registrations.Add(reg);
                ValidationUse(info, inv, null);
            }
        }
        return info;
    }

    // Declarations without member bodies, as one hash. Preprocessor directives can change which declarations exist under
    // the project's symbols, which this parse does not know: such files return null and are always treated as changed.
    internal static string? Surface(SyntaxNode root)
    {
        if (root.ContainsDirectives) return null;
        // A member's body (block or "=> expression;") hashes as one marker, so a body edit or block/arrow switch keeps the surface.
        var bodies = new List<(int Start, int End)>();
        void Body(SyntaxNode? body, SyntaxToken semicolon)
        {
            if (body == null) return;
            bodies.Add((body.SpanStart, body is ArrowExpressionClauseSyntax && !semicolon.IsMissing && semicolon.Span.Length > 0 ? semicolon.Span.End : body.Span.End));
        }
        foreach (var n in root.DescendantNodes())
            switch (n)
            {
                case BaseMethodDeclarationSyntax m: Body(m.Body, default); Body(m.ExpressionBody, m.SemicolonToken); break;
                case AccessorDeclarationSyntax a: Body(a.Body, default); Body(a.ExpressionBody, a.SemicolonToken); break;
                case PropertyDeclarationSyntax p: Body(p.ExpressionBody, p.SemicolonToken); break;
                case IndexerDeclarationSyntax i: Body(i.ExpressionBody, i.SemicolonToken); break;
            }
        bodies.Sort();
        var text = new StringBuilder();
        var next = 0;
        foreach (var token in root.DescendantTokens())
        {
            while (next < bodies.Count && bodies[next].End <= token.SpanStart) next++;
            if (next < bodies.Count && token.SpanStart >= bodies[next].Start)
            {
                if (token.SpanStart == bodies[next].Start) text.Append("{body} ");
                continue;
            }
            text.Append(token.Text).Append(' ');
        }
        return Sha(Encoding.UTF8.GetBytes(text.ToString()));
    }

    // FluentValidation's own API only (resolved to the FluentValidation namespace when the project loaded; by name otherwise,
    // where the ambiguous "Validate" is skipped). Model: the validated type, from the validator or the IValidator<T> receiver.
    static readonly Regex ValidationCall = new("^(AddValidatorsFromAssembl(y|ies|yContaining)|AddFluentValidation\\w*|AddValidator|Validate|ValidateAsync|ValidateAndThrow|ValidateAndThrowAsync|MustAsync|CustomAsync|WhenAsync|UnlessAsync|SetAsyncValidator)$");
    static void ValidationUse(DocumentInfo info, InvocationExpressionSyntax inv, SemanticModel? model)
    {
        var name = inv.Expression switch { MemberAccessExpressionSyntax ma => ma.Name.Identifier.Text, SimpleNameSyntax sn => sn.Identifier.Text, _ => "" };
        if (!ValidationCall.IsMatch(name)) return;
        var kind = name.StartsWith("Add", StringComparison.Ordinal) ? "registration" : name is "Validate" or "ValidateAndThrow" ? "validate-sync"
            : name is "ValidateAsync" or "ValidateAndThrowAsync" ? "validate-async" : "async-rule";
        string? subject = null;
        var validator = inv.Ancestors().OfType<ClassDeclarationSyntax>().FirstOrDefault();
        if (model != null)
        {
            var si = model.GetSymbolInfo(inv);
            if ((si.Symbol ?? si.CandidateSymbols.FirstOrDefault()) is not IMethodSymbol s ||
                !(s.ContainingNamespace?.ToDisplayString() ?? "").StartsWith("FluentValidation", StringComparison.Ordinal)) return;
            ITypeSymbol? t = null;
            if (kind == "async-rule" && validator != null && model.GetDeclaredSymbol(validator) is INamedTypeSymbol vs)
                for (var b = vs.BaseType; b != null && t == null; b = b.BaseType) if (b.Name == "AbstractValidator" && b.TypeArguments.Length == 1) t = b.TypeArguments[0];
            if (t == null && kind != "registration")
                t = s.ContainingType is { IsGenericType: true } ct && ct.TypeArguments.Length == 1 ? ct.TypeArguments[0] : s.TypeArguments.FirstOrDefault();
            subject = t switch { null => null, ITypeParameterSymbol => "<generic>", _ => Identity(t) ?? t.ToDisplayString() };
        }
        else
        {
            if (name == "Validate") return;
            var baseType = validator?.BaseList?.Types.Select(b => b.Type).OfType<GenericNameSyntax>().FirstOrDefault(g => g.Identifier.Text == "AbstractValidator");
            if (kind == "async-rule" && baseType != null) subject = "~" + Bare(baseType.TypeArgumentList.Arguments[0].ToString());
        }
        info.Validation.Add(new ValidationInfo { Kind = kind, Method = name, Model = subject, Line = Line(inv) });
    }

    static RegistrationInfo? RegistrationOf(InvocationExpressionSyntax inv, Func<TypeSyntax, ITypeSymbol?>? resolve)   // services.AddScoped<IFoo, Foo>() and typeof forms
    {
        var name = inv.Expression switch { MemberAccessExpressionSyntax ma => ma.Name, SimpleNameSyntax sn => sn, _ => null };
        var m = name == null ? Match.Empty : Registration.Match(name.Identifier.Text);
        if (!m.Success) return null;
        var types = name is GenericNameSyntax g ? g.TypeArgumentList.Arguments.ToList() : inv.ArgumentList.Arguments.Select(a => (a.Expression as TypeOfExpressionSyntax)?.Type).OfType<TypeSyntax>().ToList();
        if (types.Count == 0) return null;
        string Key(TypeSyntax t) => resolve?.Invoke(t) is { TypeKind: not TypeKind.Error } s && Identity(s) is string id ? id : "~" + Bare(t.ToString());
        return new RegistrationInfo { Service = Key(types[0]), Implementation = types.Count > 1 ? Key(types[1]) : null, Lifetime = m.Groups[2].Value, Line = Line(inv) };
    }

    static void ScanRegistrations(DocumentInfo info, SemanticModel model, InvocationExpressionSyntax lifetime)
    {
        var chain = new List<InvocationExpressionSyntax>();
        for (ExpressionSyntax? e = lifetime; e is InvocationExpressionSyntax call && call.Expression is MemberAccessExpressionSyntax member; e = member.Expression)
        {
            chain.Add(call);
            if (member.Name.Identifier.Text == "AddClasses") break;
        }
        string Name(InvocationExpressionSyntax call) => (call.Expression as MemberAccessExpressionSyntax)?.Name.Identifier.Text ?? "";
        var classes = chain.FirstOrDefault(c => Name(c) == "AddClasses");
        var root = lifetime.AncestorsAndSelf().OfType<InvocationExpressionSyntax>().LastOrDefault() ?? lifetime;
        var from = root.DescendantNodesAndSelf().OfType<InvocationExpressionSyntax>().FirstOrDefault(c => Name(c) == "FromAssemblies");
        var assemblies = new HashSet<IAssemblySymbol>(SymbolEqualityComparer.Default);
        if (from != null)
        {
            foreach (var arg in from.ArgumentList.Arguments)
            {
                var expr = arg.Expression;
                if (model.GetSymbolInfo(expr).Symbol is ILocalSymbol local &&
                    local.DeclaringSyntaxReferences.FirstOrDefault()?.GetSyntax() is VariableDeclaratorSyntax v && v.Initializer != null)
                    expr = v.Initializer.Value;
                foreach (var t in expr.DescendantNodesAndSelf().OfType<TypeOfExpressionSyntax>())
                    if (model.GetTypeInfo(t.Type).Type is INamedTypeSymbol type) assemblies.Add(type.ContainingAssembly);
            }
        }
        var assign = classes?.DescendantNodes().OfType<InvocationExpressionSyntax>().FirstOrDefault(c => Name(c) == "AssignableTo");
        var targetSyntax = (assign?.Expression as MemberAccessExpressionSyntax)?.Name is GenericNameSyntax gn
            ? gn.TypeArgumentList.Arguments.FirstOrDefault() : assign?.DescendantNodes().OfType<TypeOfExpressionSyntax>().FirstOrDefault()?.Type;
        var target = targetSyntax == null ? null : model.GetTypeInfo(targetSyntax).Type as INamedTypeSymbol;
        var ends = classes?.DescendantNodes().OfType<InvocationExpressionSyntax>().FirstOrDefault(c => Name(c) == "EndsWith");
        var suffixValue = ends == null || ends.ArgumentList.Arguments.Count == 0 ? default :
            model.GetConstantValue(ends.ArgumentList.Arguments[0].Expression);
        var suffix = suffixValue.HasValue ? suffixValue.Value as string : null;
        var self = chain.Any(c => Name(c) == "AsSelf");
        var interfaces = chain.Any(c => Name(c) == "AsImplementedInterfaces");
        var where = classes?.DescendantNodes().OfType<InvocationExpressionSyntax>().Any(c => Name(c) == "Where") ?? false;
        var predicate = classes?.DescendantNodes().OfType<InvocationExpressionSyntax>().FirstOrDefault(c => Name(c) == "Where")?
            .ArgumentList.Arguments.FirstOrDefault()?.Expression as LambdaExpressionSyntax;
        var simplePredicate = predicate?.Body == ends;
        if (classes == null || assemblies.Count == 0 || (!self && !interfaces) ||
            (assign != null && target == null) || (where && (suffix == null || !simplePredicate)))
        {
            info.Unresolved.Add($"L{Line(lifetime)} assembly scanning registration: unsupported dynamic selection");
            return;
        }
        IEnumerable<INamedTypeSymbol> Types(INamespaceOrTypeSymbol scope)
        {
            foreach (var child in scope.GetMembers())
            {
                if (child is INamedTypeSymbol type) yield return type;
                if (child is INamespaceOrTypeSymbol nested)
                    foreach (var item in Types(nested)) yield return item;
            }
        }
        var life = Name(lifetime).Replace("With", "").Replace("Lifetime", "");
        foreach (var type in assemblies.SelectMany(a => Types(a.GlobalNamespace)).Where(t =>
            t.TypeKind == TypeKind.Class && !t.IsAbstract && t.DeclaredAccessibility == Accessibility.Public &&
            t.Locations.Any(l => l.IsInSource) && (suffix == null || t.Name.EndsWith(suffix, StringComparison.Ordinal))))
        {
            bool Matches(INamedTypeSymbol candidate) => target != null &&
                SymbolEqualityComparer.Default.Equals(candidate.OriginalDefinition, target.OriginalDefinition);
            bool BaseMatches(INamedTypeSymbol? current)
            {
                for (; current != null; current = current.BaseType) if (Matches(current)) return true;
                return false;
            }
            if (target != null && !type.AllInterfaces.Any(Matches) && !BaseMatches(type)) continue;
            var implementation = Identity(type);
            foreach (var service in self ? new[] { type }.AsEnumerable() : type.AllInterfaces)
                if (Identity(service) is string id)
                    info.Registrations.Add(new RegistrationInfo { Service = id, Implementation = implementation, Lifetime = life, Line = Line(lifetime) });
        }
    }

    // Patterns and conventions as the source shows them (observed, with path:line evidence), and the analysis coverage.
    static void Analyze(ArchIndex ix, List<string> graphql)
    {
        var types = ix.Documents.SelectMany(d => d.Symbols.Where(s => s.Kind is not ("method" or "constructor")).Select(s => (Doc: d, Sym: s))).ToList();
        var methods = ix.Documents.SelectMany(d => d.Symbols.Where(s => s.Kind == "method").Select(s => (Doc: d, Sym: s))).ToList();
        var regs = ix.Documents.SelectMany(d => d.Registrations.Select(r => (Doc: d, Reg: r))).ToList();
        bool Is((DocumentInfo Doc, SymbolInfo Sym) x, string rx) => (x.Sym.Base != null && Regex.IsMatch(Bare(x.Sym.Base), rx)) || (x.Sym.Interfaces?.Any(i => Regex.IsMatch(Bare(i), rx)) ?? false);
        void P(string name, IEnumerable<(string At, bool Semantic)> hits)
        {
            var h = hits.ToList();
            ix.Patterns.Add(new PatternInfo { Name = name, Observed = h.Count > 0, Count = h.Count, Evidence = h.Take(5).Select(x => x.At).ToList(), Basis = h.Count == 0 ? "" : h.All(x => x.Semantic) ? "semantic" : "syntax (names only where projects did not load)" });
        }
        IEnumerable<(string, bool)> T(IEnumerable<(DocumentInfo Doc, SymbolInfo Sym)> xs) => xs.Select(x => ($"{x.Doc.Path}:{x.Sym.Line}", x.Doc.Analysis != "syntax"));
        var concrete = types.Where(x => x.Sym.Kind != "interface").ToList();
        P("CQRS handlers (IRequestHandler, ICommandHandler, IQueryHandler, INotificationHandler)", T(concrete.Where(x => Is(x, "^I(Request|Command|Query|Notification)Handler$") || Regex.IsMatch(x.Sym.Name, "(Command|Query)Handler$"))));
        P("Commands and queries (IRequest, ICommand, IQuery)", T(concrete.Where(x => Is(x, "^I(Request|Command|Query)$"))));
        P("Validators (AbstractValidator, IValidator)", T(concrete.Where(x => Is(x, "^(AbstractValidator|IValidator)$"))));
        // FluentValidation wiring as the code shows it: where validators are registered and run, async rules, and the
        // combination FluentValidation rejects at run time (an async rule reached through a synchronous Validate call).
        var uses = ix.Documents.SelectMany(d => d.Validation.Select(v => (Doc: d, Use: v))).ToList();
        IEnumerable<(string, bool)> U(IEnumerable<(DocumentInfo Doc, ValidationInfo Use)> xs) => xs.Select(x => ($"{x.Doc.Path}:{x.Use.Line} {x.Use.Method}{(x.Use.Model == null ? "" : " " + x.Use.Model.Split(':').Last().TrimStart('~'))}", x.Doc.Analysis != "syntax"));
        var validatorRegs = regs.Where(x => Regex.IsMatch(Bare(x.Reg.Service.Split(':').Last().TrimStart('~')), "^IValidator$")).ToList();
        P("FluentValidation registration (AddValidatorsFrom*, IValidator<T> services)", U(uses.Where(x => x.Use.Kind == "registration"))
            .Concat(validatorRegs.Select(x => ($"{x.Doc.Path}:{x.Reg.Line} {x.Reg.Lifetime} IValidator", x.Doc.Analysis != "syntax"))));
        P("FluentValidation invocation (Validate, ValidateAsync, ValidateAndThrow)", U(uses.Where(x => x.Use.Kind is "validate-sync" or "validate-async")));
        P("FluentValidation async rules (MustAsync, CustomAsync, WhenAsync)", U(uses.Where(x => x.Use.Kind == "async-rule")));
        var asyncModels = new HashSet<string>(uses.Where(x => x.Use.Kind == "async-rule" && x.Use.Model != null).Select(x => x.Use.Model!));
        var syncOverAsync = uses.Where(x => x.Use.Kind == "validate-sync" && x.Use.Model != null && (asyncModels.Contains(x.Use.Model) || (x.Use.Model == "<generic>" && asyncModels.Count > 0))).ToList();
        P("FluentValidation risk: async rules reached through a synchronous Validate call (throws AsyncValidatorInvokedSynchronouslyException)",
            U(syncOverAsync.Concat(uses.Where(x => x.Use.Kind == "async-rule" && syncOverAsync.Any(s => s.Use.Model == x.Use.Model || s.Use.Model == "<generic>")))));
        var validatorTypes = concrete.Where(x => Is(x, "^AbstractValidator$")).ToList();
        P("Validators without a registration the analyzer can see (may be registered by reflection or a convention it does not read)",
            uses.Any(x => x.Use.Kind == "registration") ? Enumerable.Empty<(string, bool)>() : T(validatorTypes.Where(v => !validatorRegs.Any(r => r.Reg.Implementation == v.Sym.Id || r.Reg.Implementation == "~" + v.Sym.Name))));
        P("Repository pattern (implementations of I*Repository)", T(concrete.Where(x => Is(x, @"^I\w*Repository$"))));
        P("Dependency injection registrations", regs.Select(x => ($"{x.Doc.Path}:{x.Reg.Line}", x.Doc.Analysis != "syntax")));
        P("Service abstractions (an interface registered with its implementation)", regs.Where(x => x.Reg.Implementation != null && Regex.IsMatch(Bare(x.Reg.Service.Split(':').Last()), "^I[A-Z]")).Select(x => ($"{x.Doc.Path}:{x.Reg.Line}", x.Doc.Analysis != "syntax")));
        P("GraphQL (StrawberryShake, HotChocolate, GraphQL.Client, .graphql documents)", T(types.Where(x => $"{x.Sym.Base} {string.Join(" ", x.Sym.Interfaces ?? new())} {string.Join(" ", x.Sym.Attributes ?? new())}".Contains("GraphQL", StringComparison.OrdinalIgnoreCase) || Regex.IsMatch($"{x.Sym.Base} {string.Join(" ", x.Sym.Interfaces ?? new())}", "StrawberryShake|HotChocolate|IOperationResult"))).Concat(graphql.Select(g => ($"{g}:1", true))));
        P("Azure Functions ([Function], [FunctionName])", T(methods.Where(x => x.Sym.Attributes?.Any(a => a is "Function" or "FunctionName") ?? false)));
        P("ASP.NET controllers", T(concrete.Where(x => Is(x, "^(Controller|ControllerBase)$") || (x.Sym.Attributes?.Contains("ApiController") ?? false))));
        P("Dataverse plugins (IPlugin)", T(concrete.Where(x => Is(x, "^(IPlugin|PluginBase)$"))));
        P("Unit tests", ix.Documents.SelectMany(d => d.Tests.Select(t => ($"{d.Path}:{t.Line}", d.Analysis != "syntax"))));
        // Clean Architecture: layers named by project, references pointing inward (Presentation -> Infrastructure -> Application -> Domain).
        int Layer(ProjectInfo p) => p.Name.Split('.').Last() switch { "Domain" or "Core" => 0, "Application" => 1, "Infrastructure" or "Persistence" or "Data" => 2, "Api" or "Web" or "Function" or "Functions" or "Host" or "Presentation" => 3, _ => -1 };
        var layered = ix.Projects.Where(p => !p.Test && Layer(p) >= 0).ToDictionary(p => p.Path, Paths);
        var edges = layered.Values.SelectMany(p => p.ProjectReferences.Where(layered.ContainsKey).Select(r => (From: p, To: layered[r]))).ToList();
        var outward = edges.Where(e => Layer(e.To) > Layer(e.From) || (Layer(e.From) == 1 && Layer(e.To) == 2)).ToList();
        var cleanSeen = layered.Values.Select(Layer).Distinct().Count() >= 3;
        ix.Patterns.Add(new PatternInfo
        {
            Name = "Clean Architecture layering (Domain <- Application <- Infrastructure <- Presentation, by project)", Observed = cleanSeen && outward.Count == 0, Count = edges.Count,
            Evidence = outward.Select(e => $"against the direction: {e.From.Path} -> {e.To.Path}").Concat(edges.Take(5).Select(e => $"{e.From.Path} -> {e.To.Path}")).Take(6).ToList(), Basis = cleanSeen ? "project references" : "",
        });
        // Conventions: where each role lives, and the naming the code uses.
        foreach (var suffix in new[] { "CommandHandler", "QueryHandler", "Handler", "Command", "Query", "Validator", "Service", "Repository", "Controller", "Function", "Client", "Tests" })
        {
            var hits = concrete.Where(x => x.Sym.Name.EndsWith(suffix, StringComparison.Ordinal) && x.Sym.Name.Length > suffix.Length).ToList();
            if (hits.Count < 2) continue;
            var homes = hits.GroupBy(x => Path.GetDirectoryName(x.Doc.Path)?.Replace('\\', '/') ?? "").OrderByDescending(g => g.Count()).Take(2).Select(g => $"{(g.Key == "" ? "." : g.Key)} ({g.Count()})");
            ix.Conventions.Add($"*{suffix}: {hits.Count} types, mostly in {string.Join(", ", homes)}");
        }
        var interfaces = types.Where(x => x.Sym.Kind == "interface").ToList();
        if (interfaces.Count > 0) ix.Conventions.Add($"interfaces named I<Name>: {interfaces.Count(x => Regex.IsMatch(x.Sym.Name, "^I[A-Z]"))} of {interfaces.Count}");
        var asyncs = methods.Where(x => Regex.IsMatch(x.Sym.Signature ?? "", @"^(async\s+)?(System\.Threading\.Tasks\.)?(Value)?Task\b")).ToList();
        if (asyncs.Count > 0) ix.Conventions.Add($"methods returning Task named *Async: {asyncs.Count(x => x.Sym.Name.EndsWith("Async", StringComparison.Ordinal))} of {asyncs.Count}");
        var testTypes = concrete.Where(x => x.Sym.Name.EndsWith("Tests", StringComparison.Ordinal)).ToList();
        if (testTypes.Count > 0)
        {
            var names = new HashSet<string>(concrete.Select(x => x.Sym.Name));
            ix.Conventions.Add($"test classes named <Type>Tests for an existing type: {testTypes.Count(x => names.Contains(x.Sym.Name.Substring(0, x.Sym.Name.Length - 5)))} of {testTypes.Count}");
        }
        var c = ix.Coverage = new CoverageInfo { Projects = ix.Projects.Count, Semantic = ix.Projects.Count(p => p.Analysis == "semantic"), Partial = ix.Projects.Count(p => p.Analysis == "partial"), Syntax = ix.Projects.Count(p => p.Analysis == "syntax"), Documents = ix.Documents.Count };
        c.Summary = string.Join("; ", new[]
        {
            $"semantic analysis for {c.Semantic} of {c.Projects} project(s)",
            c.Partial > 0 ? $"{c.Partial} loaded incompletely, without their framework references (each project's loadErrors say why: a failed MSBuild evaluation, or a missing restore): external types unresolved there" : null,
            c.Syntax > 0 ? $"{c.Syntax} parsed only, not loaded with MSBuild (each project's loadErrors say why): calls, DI types, and test coverage are not resolved there" : null,
        }.OfType<string>());
    }

    internal static string Bare(string type)   // "Ns.IRequestHandler<Ns.A, B>" -> "IRequestHandler"
    {
        var t = type; var lt = t.IndexOf('<'); if (lt >= 0) t = t.Substring(0, lt);
        var dot = t.LastIndexOf('.'); return (dot >= 0 ? t.Substring(dot + 1) : t).Trim();
    }
    internal static string? Identity(ISymbol symbol)
    {
        var original = symbol.OriginalDefinition;
        var id = original.GetDocumentationCommentId();
        return id == null ? null : id + "@" + original.ContainingAssembly?.Identity.Name;
    }
    internal static string Full(string root, string rel) => Path.Combine(root, rel.Replace('/', Path.DirectorySeparatorChar));
    internal static string Rel(string root, string full) =>
        full.StartsWith(root + "\\", StringComparison.OrdinalIgnoreCase) || full.StartsWith(root + "/", StringComparison.OrdinalIgnoreCase)
            ? full.Substring(root.Length + 1).Replace('\\', '/') : full.Replace('\\', '/');
    internal static string Sha(byte[] bytes) => Compatibility.Hash(bytes);
    static int Line(SyntaxToken t) => t.GetLocation().GetLineSpan().StartLinePosition.Line + 1;
    static int Line(SyntaxNode n) => n.GetLocation().GetLineSpan().StartLinePosition.Line + 1;
    static int EndLine(SyntaxNode n) => n.GetLocation().GetLineSpan().EndLinePosition.Line + 1;
    static SyntaxToken NameToken(BaseMethodDeclarationSyntax m) => m switch { MethodDeclarationSyntax x => x.Identifier, ConstructorDeclarationSyntax x => x.Identifier, _ => m.GetFirstToken() };
    static string Short(string? attribute) => attribute == null ? "" : attribute.EndsWith("Attribute", StringComparison.Ordinal) ? attribute.Substring(0, attribute.Length - 9) : attribute;
    static IEnumerable<string> Attributes(SyntaxList<AttributeListSyntax> lists) => lists.SelectMany(l => l.Attributes).Select(a => Short(Bare(a.Name.ToString())));
    static List<string>? NullIfEmpty(IEnumerable<string> items) { var l = items.Where(s => s != "").Distinct().ToList(); return l.Count == 0 ? null : l; }
    static string Kind(BaseTypeDeclarationSyntax t) => t switch
    {
        InterfaceDeclarationSyntax => "interface", EnumDeclarationSyntax => "enum", StructDeclarationSyntax => "struct",
        RecordDeclarationSyntax r => r.ClassOrStructKeyword.IsKind(SyntaxKind.StructKeyword) ? "record struct" : "record", _ => "class",
    };
    static string? Namespace(SyntaxNode n) { var parts = n.Ancestors().OfType<BaseNamespaceDeclarationSyntax>().Reverse().Select(x => x.Name.ToString()).ToList(); return parts.Count == 0 ? null : string.Join(".", parts); }
    static string QualifiedName(BaseTypeDeclarationSyntax t)   // as a documentation comment id names it: Ns.Outer.Inner`1
    {
        var parts = t.AncestorsAndSelf().OfType<BaseTypeDeclarationSyntax>().Reverse().Select(x => x.Identifier.Text + (x is TypeDeclarationSyntax { TypeParameterList: { } tp } ? "`" + tp.Parameters.Count : ""));
        var ns = Namespace(t);
        return (ns == null ? "" : ns + ".") + string.Join(".", parts);
    }
}
