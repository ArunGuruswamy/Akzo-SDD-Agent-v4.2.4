using System.Text.Json;
using System.Text.RegularExpressions;

namespace Akzo.ArchitectureAnalyzer;

// Akzo SDD Agent architecture analyzer (Roslyn). Reads source; never writes into the repository; makes no network call.
//   scan   --root <repo> --out <cache dir> [--syntax-only]        incremental index of projects, symbols, calls, DI, tests, patterns
//   query  --root <repo> --out <cache dir> --terms "<PBI words>" [--max 8] [--syntax-only]   scan, then the evidence for the work
//   queries --root <repo> --out <cache dir> --terms "<query>;<query>"   one scan for up to eight independent queries
//   locate --out <cache dir> --at "<path>:<line>;..."              the symbol that encloses each location (Sonar findings)
//   graphql --root <repo> --out <cache dir> [--terms "<words>"]     schema/operation validation per scope, cached by content
public static class Program
{
    public static int Main(string[] args)
    {
        try
        {
            var exit = BuildHostStaging.Initialize(args);
            return exit ?? RunAsync(args).GetAwaiter().GetResult();
        }
        catch (Exception ex)
        {
            Console.Out.Write(JsonSerializer.Serialize(new { status = "ERROR", error = ex.ToString() }));
            return 1;
        }
    }

    [System.Runtime.CompilerServices.MethodImpl(System.Runtime.CompilerServices.MethodImplOptions.NoInlining)]
    public static async Task<int> RunAsync(string[] args)
    {
        try
        {
            var o = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            for (var i = 1; i < args.Length; i++)
                if (args[i].StartsWith("--", StringComparison.Ordinal)) o[args[i].Substring(2)] = i + 1 < args.Length && !args[i + 1].StartsWith("--", StringComparison.Ordinal) ? args[++i] : "true";
            string Need(string k) => o.TryGetValue(k, out var v) && v != "" ? v : throw new ArgumentException($"--{k} is required");
            switch (args.FirstOrDefault())
            {
                case "scan":
                {
                    var (ix, sum) = await Scanner.ScanAsync(Need("root"), Need("out"), o.ContainsKey("syntax-only"));
                    sum["coverage"] = ix.Coverage;
                    sum["solutions"] = ix.Solutions;
                    sum["projects"] = ix.Projects.Select(p => new { p.Path, p.Style, p.TargetFrameworks, p.ResolvedFramework, p.Analysis, p.ProjectReferences, p.Packages, p.Test, p.LoadErrors, p.CompilationErrors, p.CompilationDiagnostics });
                    Print(sum);
                    return 0;
                }
                case "query":
                {
                    var (ix, sum) = await Scanner.ScanAsync(Need("root"), Need("out"), o.ContainsKey("syntax-only"));
                    Print(Query.Run(ix, Need("terms"), int.TryParse(o.GetValueOrDefault("max"), out var max) ? max : 4, sum));
                    return 0;
                }
                case "queries":
                {
                    var terms = Need("terms").Split(';').Select(t => t.Trim()).ToArray();
                    if (terms.Length > 8 || terms.Any(t => t.Length == 0))
                        throw new ArgumentException("--terms requires one to eight nonempty queries separated by semicolons");
                    var (ix, sum) = await Scanner.ScanAsync(Need("root"), Need("out"), o.ContainsKey("syntax-only"));
                    var limit = int.TryParse(o.GetValueOrDefault("max"), out var max) ? max : 4;
                    Print(new { status = "OK", scan = sum, coverage = ix.Coverage, scanCount = 1,
                        results = terms.Select(term => new { query = term, evidence = Query.Run(ix, term, limit, new Dictionary<string, object?>()) }).ToArray() });
                    return 0;
                }
                case "locate":
                    Print(Query.Locate(Scanner.Read(Path.Combine(Need("out"), "index.json"), null), Need("at")));
                    return 0;
                case "graphql":
                    Print(GraphQL.Run(Need("root"), Need("out"), o.GetValueOrDefault("terms")));
                    return 0;
                default:
                    Console.Error.WriteLine("usage: scan|query|queries|locate|graphql --root <repo> --out <cache dir> [--terms \"...\"] [--at \"path:line;...\"] [--syntax-only]");
                    return 2;
            }
        }
        catch (Exception ex)
        {
            Print(new { status = "ERROR", error = ex.ToString() });
            return 1;
        }
    }

    static void Print(object value) => Console.Out.Write(JsonSerializer.Serialize(value, Scanner.Json));   // the default encoder escapes non-ASCII: safe on any console code page
}

public static class Query
{
    static readonly HashSet<string> Stop = new(StringComparer.OrdinalIgnoreCase) { "the", "and", "for", "with", "from", "that", "this", "into", "when", "then", "should", "must", "will", "are", "was", "has", "have", "not", "all", "any", "new", "add", "use", "can", "user", "users", "able", "via", "per" };

    // Evidence for a piece of work: the existing types that match its words, ranked; for each its members, DI registrations,
    // callers, tests, and the siblings of the same kind to follow; the reusable abstractions they depend on; the expected
    // impact (projects, dependents, call sites); the conventions; confidence; and the words or projects left unresolved.
    public static object Run(ArchIndex ix, string terms, int max, Dictionary<string, object?> scan)
    {
        var words = Tokens(terms).Distinct().ToList();
        var symbols = ix.Documents.SelectMany(d => d.Symbols.Select(s => (Doc: d, Sym: s))).ToList();
        var byId = new Dictionary<string, (DocumentInfo Doc, SymbolInfo Sym)>();
        foreach (var x in symbols) byId.TryAdd(x.Sym.Id, x);
        var testProjects = new HashSet<string>(ix.Projects.Where(p => p.Test).Select(p => p.Path), Scanner.Paths);
        var types = symbols.Where(x => x.Sym.Kind is not ("method" or "constructor")).ToList();
        var membersOf = symbols.Where(x => x.Sym.Container != null && x.Sym.Kind is "method" or "constructor").ToLookup(x => x.Sym.Container!);
        var exact = types.Any(x => x.Sym.Name.Equals(terms, StringComparison.OrdinalIgnoreCase));
        var ranked = types.Where(x => x.Doc.Project != "" && !testProjects.Contains(x.Doc.Project) &&
            (!exact || x.Sym.Name.Equals(terms, StringComparison.OrdinalIgnoreCase))).Select(x =>
        {
            var name = Tokens(x.Sym.Name).ToHashSet();
            var path = Tokens(x.Doc.Path).ToHashSet();
            var members = membersOf[x.Sym.Id].SelectMany(m => Tokens(m.Sym.Name)).ToHashSet();
            var matched = words.Where(w => name.Contains(w)).ToList();
            var score = matched.Count * 3 + (matched.Count == words.Count && words.Count > 0 ? 3 : 0) + words.Count(w => !name.Contains(w) && (path.Contains(w) || members.Contains(w)));
            return (x.Doc, x.Sym, Score: score, Matched: matched);
        }).Where(x => x.Score > 0).OrderByDescending(x => x.Score).ThenBy(x => x.Doc.Path, Scanner.Paths).Take(Math.Min(8, Math.Max(1, max))).ToList();
        string At(DocumentInfo d, SymbolInfo s) => $"{d.Path}:{s.Line}";
        string Name(string id) => byId.TryGetValue(id, out var x) ? $"{x.Sym.Name} ({At(x.Doc, x.Sym)})" : id.TrimStart('~');
        var calls = ix.Documents.SelectMany(d => d.Calls.Select(c => (Doc: d, Call: c))).ToList();
        var regs = ix.Documents.SelectMany(d => d.Registrations.Select(r => (Doc: d, Reg: r))).ToList();
        var tests = ix.Documents.SelectMany(d => d.Tests.Select(t => (Doc: d, Test: t))).ToList();
        var candidates = ranked.Select(c =>
        {
            var memberIds = membersOf[c.Sym.Id].Select(m => m.Sym.Id).ToHashSet();
            var kin = (c.Sym.InterfaceIds ?? new()).Append(c.Sym.BaseId).OfType<string>().ToHashSet();
            return new
            {
                id = c.Sym.Id, kind = c.Sym.Kind, name = c.Sym.Name, at = $"{c.Doc.Path}:{c.Sym.Line}-{c.Sym.EndLine}", project = c.Doc.Project, analysis = c.Doc.Analysis, matched = c.Matched,
                @base = c.Sym.Base, interfaces = c.Sym.Interfaces?.Take(4), attributes = c.Sym.Attributes?.Take(6), dependencies = c.Sym.Dependencies?.Take(6),
                contextTruncated = (c.Sym.Interfaces?.Count > 4) || (c.Sym.Attributes?.Count > 6) || (c.Sym.Dependencies?.Count > 6),
                members = membersOf[c.Sym.Id].OrderBy(m => m.Sym.Line).Take(8).Select(m => $"{m.Sym.Signature ?? m.Sym.Name} ({At(m.Doc, m.Sym)})"),
                registrations = regs.Where(r => r.Reg.Service == c.Sym.Id || r.Reg.Implementation == c.Sym.Id || r.Reg.Service == "~" + c.Sym.Name || r.Reg.Implementation == "~" + c.Sym.Name)
                    .Take(5).Select(r => $"{r.Doc.Path}:{r.Reg.Line} {r.Reg.Lifetime} {r.Reg.Service.Split(':').Last().TrimStart('~')}{(r.Reg.Implementation == null ? "" : " -> " + r.Reg.Implementation.Split(':').Last().TrimStart('~'))}"),
                callers = calls.Where(x => memberIds.Contains(x.Call.To) && !memberIds.Contains(x.Call.From)).Select(x => $"{Name(x.Call.From)} at {x.Doc.Path}:{x.Call.Line}").Distinct().Take(5),
                tests = tests.Where(t => t.Test.Covers.Contains(c.Sym.Id) || t.Test.Covers.Contains("~" + c.Sym.Name)).Select(t => $"{Name(t.Test.Test)}").Distinct().Take(5),
                implementations = c.Sym.Kind == "interface" ? types.Where(t => t.Sym.InterfaceIds?.Contains(c.Sym.Id) ?? false).Take(5).Select(t => $"{t.Sym.Name} ({At(t.Doc, t.Sym)})") : null,
                siblings = kin.Count == 0 ? null : types.Where(t => t.Sym.Id != c.Sym.Id && !testProjects.Contains(t.Doc.Project) && ((t.Sym.InterfaceIds ?? new()).Append(t.Sym.BaseId).OfType<string>().Any(kin.Contains)))
                    .OrderBy(t => Path.GetDirectoryName(t.Doc.Path) == Path.GetDirectoryName(c.Doc.Path) ? 0 : 1).Take(3).Select(t => $"{t.Sym.Name} ({At(t.Doc, t.Sym)})"),
            };
        }).ToList();
        var dependencyIds = ranked.SelectMany(c => c.Sym.DependencyIds ?? new()).ToHashSet();
        var reusable = types.Where(t => t.Sym.Kind == "interface" && dependencyIds.Contains(t.Sym.Id)).Select(t => $"{t.Sym.Name} ({At(t.Doc, t.Sym)}): {types.Count(i => i.Sym.InterfaceIds?.Contains(t.Sym.Id) ?? false)} implementation(s)").Distinct().Take(8).ToList();
        var projects = ranked.Select(c => c.Doc.Project).Where(p => p != "").Distinct(Scanner.Paths).ToList();
        var allMembers = ranked.SelectMany(c => membersOf[c.Sym.Id].Select(m => m.Sym.Id)).ToHashSet();
        var inbound = calls.Where(x => allMembers.Contains(x.Call.To) && !allMembers.Contains(x.Call.From)).ToList();
        var top = ranked.FirstOrDefault();
        var confidence = top.Sym == null ? "none" : top.Score >= 6 && top.Doc.Analysis == "semantic" ? "high" : top.Score >= 3 ? "medium" : "low";
        var unmatched = words.Where(w => !ranked.Any(c => c.Matched.Contains(w))).ToList();
        var reduced = ix.Projects.Where(p => projects.Contains(p.Path, Scanner.Paths) && p.Analysis != "semantic").Select(p => $"{p.Path}: {p.Analysis} analysis ({string.Join("; ", p.LoadErrors.Take(1))}): callers and tests there may be missing").ToList();
        return new
        {
            status = ranked.Count > 0 ? "FOUND" : "NO_MATCH", terms = words, scan, coverage = ix.Coverage, candidates, reusable,
            impact = new
            {
                projects, dependents = ix.Projects.Where(p => p.ProjectReferences.Any(r => projects.Contains(r, Scanner.Paths))).Select(p => p.Path).ToList(),
                callSites = inbound.Count, callerFiles = inbound.Select(x => x.Doc.Path).Distinct(Scanner.Paths).Take(10).ToList(),
            },
            conventions = ix.Conventions, patterns = ix.Patterns.Where(p => p.Observed).Select(p => new { p.Name, p.Count, evidence = p.Evidence.Take(2), p.Basis }),
            confidence, unresolved = unmatched.Select(w => $"no type is named with '{w}'").Concat(reduced)
                .Concat(ix.Projects.Where(p => projects.Contains(p.Path, Scanner.Paths) && p.CompilationErrors > 0)
                    .Select(p => $"{p.Path}: {p.CompilationErrors} compiler errors; semantic coverage does not certify all symbols resolved"))
                .Concat(calls.Where(c => allMembers.Contains(c.Call.From) && !byId.ContainsKey(c.Call.To))
                    .Select(c => $"external/unindexed target {c.Call.To} at {c.Doc.Path}:{c.Call.Line}").Distinct().Take(8))
                .Concat(ix.Documents.Where(d => projects.Contains(d.Project, Scanner.Paths)).SelectMany(d => d.Unresolved.Select(u => $"{d.Path}: {u}"))).Take(20).ToList(),
            basis = "observed in the source: types, calls, registrations, and tests as the analyzer found them; nothing here is a recommendation",
        };
    }

    public static object Locate(ArchIndex? ix, string at)   // the innermost symbol around each location, and whether the file changed since the scan
    {
        if (ix == null) return new { status = "NO_INDEX" };
        var byPath = ix.Documents.ToDictionary(d => d.Path, Scanner.Paths);
        var rows = new List<object>();
        foreach (var item in Compatibility.SplitTrim(at, ';'))
        {
            var i = item.LastIndexOf(':');
            if (i <= 0 || !int.TryParse(item.Substring(i + 1), out var line)) continue;
            var path = item.Substring(0, i).Replace('\\', '/');
            if (!byPath.TryGetValue(path, out var d)) { rows.Add(new { at = item, symbol = (string?)null }); continue; }
            var file = Scanner.Full(ix.Root, d.Path);
            var stale = !File.Exists(file) || Scanner.Sha(File.ReadAllBytes(file)) != d.Hash;
            var s = d.Symbols.Where(x => x.Line <= line && x.EndLine >= line).OrderBy(x => x.EndLine - x.Line).FirstOrDefault();
            rows.Add(new { at = item, symbol = s?.Id, name = s?.Name, kind = s?.Kind, container = s?.Container, signature = s?.Signature, analysis = d.Analysis, stale });
        }
        return new { status = "OK", scannedAt = ix.ScannedAt, locations = rows };
    }

    static IEnumerable<string> Tokens(string text)   // words of names and phrases: OrderService, order_service, "order services" -> order, service
    {
        foreach (Match m in Regex.Matches(text, "[A-Z]?[a-z]+|[A-Z]+(?![a-z])|[0-9]+"))
        {
            var w = m.Value.ToLowerInvariant();
            if (w.Length < 3 || Stop.Contains(w)) continue;
            yield return w.Length > 4 && w.EndsWith("ies") ? w.Substring(0, w.Length - 3) + "y" : w.Length > 3 && w.EndsWith("s") && !w.EndsWith("ss") ? w.Substring(0, w.Length - 1) : w;
        }
    }
}
