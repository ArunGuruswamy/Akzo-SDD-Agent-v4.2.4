using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Akzo.ArchitectureAnalyzer;

// Mechanical GraphQL validation without a dependency: parses .graphql/.graphqls/.gql documents, merges each scope's SDL,
// validates operations and fragments against it (fields, arguments, input objects, enums, nullability, variables, fragment
// type conditions, leaf/composite selections, deprecations), and compares operation names with StrawberryShake-generated
// interfaces. A scope is the nearest folder with a GraphQL config (.graphqlrc*, graphql.config.*), else the repository
// root. Results are cached per scope by content fingerprint: an unchanged scope is not parsed again.
public static class GraphQL
{
    static readonly Regex DocumentFile = new(@"\.(graphql|graphqls|gql)$", RegexOptions.IgnoreCase);
    static readonly Regex ConfigFile = new(@"^(\.graphqlrc(\.(json|ya?ml))?|graphql\.config\.(json|ya?ml))$", RegexOptions.IgnoreCase);
    static readonly HashSet<string> Builtin = new() { "Int", "Float", "String", "Boolean", "ID" };
    const int MaxFindings = 50;

    public static object Run(string root, string outDir, string? terms)
    {
        var clock = System.Diagnostics.Stopwatch.StartNew();
        root = Path.GetFullPath(root).TrimEnd('\\', '/');
        var cacheRoot = Path.GetFullPath(outDir).TrimEnd('\\', '/');
        if (Scanner.Paths.Equals(root, cacheRoot) || cacheRoot.StartsWith(root + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("GraphQL cache must be outside the analyzed repository.");
        var docs = new List<string>(); var configs = new List<string>(); var csharp = new List<string>();
        Walk(root, root, docs, configs, csharp);
        if (docs.Count == 0) return new { status = "NO_GRAPHQL", scopes = Array.Empty<object>(), errorCount = 0, warningCount = 0, elapsedMs = clock.ElapsedMilliseconds };
        var scopeDirs = configs.Select(c => Path.GetDirectoryName(c)?.Replace('\\', '/') ?? "").Distinct().OrderByDescending(d => d.Length).ToList();
        string ScopeOf(string rel) => scopeDirs.FirstOrDefault(d => d == "" || rel.StartsWith(d + "/", StringComparison.OrdinalIgnoreCase)) ?? "";
        var cacheFile = Path.Combine(outDir, "graphql.json");
        var version = typeof(GraphQL).Assembly.ManifestModule.ModuleVersionId.ToString();
        var cache = ReadCache(cacheFile, version);
        var fresh = new Dictionary<string, CachedScope>();
        var results = new List<ScopeResult>();
        foreach (var group in docs.GroupBy(ScopeOf).OrderBy(g => g.Key, StringComparer.OrdinalIgnoreCase))
        {
            var scope = group.Key;
            var files = group.OrderBy(f => f, StringComparer.OrdinalIgnoreCase).ToList();
            var generated = csharp.Where(f => ScopeOf(f) == scope).ToList();
            var key = Scanner.Sha(Encoding.UTF8.GetBytes(string.Join("\n", files.Concat(generated).Select(f => f + "=" + Scanner.Sha(File.ReadAllBytes(Scanner.Full(root, f)))))));
            ScopeResult result;
            if (cache.TryGetValue(scope, out var hit) && hit.Key == key && hit.Result != null) { result = hit.Result; result.Cached = true; }
            else { result = Validate(root, scope, files, generated); result.Cached = false; }
            fresh[scope] = new CachedScope { Key = key, Result = result };
            results.Add(result);
        }
        WriteCache(cacheFile, version, fresh);
        var words = terms == null ? new List<string>() : Compatibility.SplitTrim(terms, ';').SelectMany(t => Compatibility.SplitTrim(t, ' ')).Where(w => w.Length > 1).ToList();
        var errorCount = results.Sum(r => r.ErrorCount); var warningCount = results.Sum(r => r.WarningCount);
        return new
        {
            status = errorCount > 0 ? "INVALID" : results.All(r => r.Status == "NO_SCHEMA") ? "NO_SCHEMA" : "VALID",
            scopes = results.Select(r => new
            {
                r.Scope, r.Status, r.SchemaFiles, r.DocumentFiles, r.Types, r.Roots, operations = r.Operations.Take(40), r.Fragments,
                errors = r.Errors.Take(MaxFindings), warnings = r.Warnings.Take(MaxFindings), r.ErrorCount, r.WarningCount, r.Client, r.Cached,
                context = words.Count == 0 ? null : Context(r, words),
            }),
            errorCount, warningCount, elapsedMs = clock.ElapsedMilliseconds,
            basis = "parsed GraphQL documents in the repository; nothing is inferred from names alone except the generated-client comparison",
            limitations = new[]
            {
                "field-merging conflicts (same response name, different fields), directive locations and custom scalar formats are not validated",
                "code-first schemas (types defined in C#) are not read: a scope without SDL is NO_SCHEMA, not verified",
                "generated clients are compared by operation interface name (I<Operation><Kind>); files under bin/obj are not read",
            },
        };
    }

    // Only the schema types and operations a requirement names, bounded: never the whole schema.
    static object Context(ScopeResult r, List<string> words)
    {
        bool Hit(string s) => words.Any(w => s.IndexOf(w, StringComparison.OrdinalIgnoreCase) >= 0);
        static string FieldName(string f) => f.Split('(', ':')[0].Trim();
        return new
        {
            types = r.TypeIndex.Where(t => Hit(t.Name) || t.Fields.Any(f => words.Any(w => FieldName(f).Equals(w, StringComparison.OrdinalIgnoreCase))))
                .Take(8).Select(t => new { t.Name, t.Kind, t.At, fields = t.Fields.Take(25), fieldsTruncated = t.Fields.Count > 25 }),
            operations = r.OperationIndex.Where(o => Hit(o.Name) || o.Types.Any(Hit)).Take(8),
        };
    }

    static void Walk(string root, string dir, List<string> docs, List<string> configs, List<string> csharp)
    {
        string[] subs, files;
        try { subs = Directory.GetDirectories(dir); files = Directory.GetFiles(dir); } catch { return; }
        foreach (var f in files)
        {
            var name = Path.GetFileName(f);
            if (DocumentFile.IsMatch(name)) docs.Add(Scanner.Rel(root, f));
            else if (ConfigFile.IsMatch(name)) configs.Add(Scanner.Rel(root, f));
            else if (name.EndsWith(".cs", StringComparison.OrdinalIgnoreCase) && IsGeneratedClient(f)) csharp.Add(Scanner.Rel(root, f));
        }
        foreach (var d in subs)
            if (!Scanner.SkipDirs.Contains(Path.GetFileName(d)) && !new DirectoryInfo(d).Attributes.HasFlag(FileAttributes.ReparsePoint)) Walk(root, d, docs, configs, csharp);
    }

    static bool IsGeneratedClient(string file)
    {
        try
        {
            using var reader = new StreamReader(file);
            var buffer = new char[4096];
            var head = new string(buffer, 0, reader.Read(buffer, 0, buffer.Length));
            return head.IndexOf("auto-generated", StringComparison.OrdinalIgnoreCase) >= 0 && head.IndexOf("StrawberryShake", StringComparison.Ordinal) >= 0;
        }
        catch { return false; }
    }

    // ---- validation -------------------------------------------------------------------------------------------------

    static ScopeResult Validate(string root, string scope, List<string> files, List<string> generated)
    {
        var r = new ScopeResult { Scope = scope == "" ? "." : scope, DocumentFiles = files.Count };
        var types = new List<TypeDef>(); var execs = new List<Executable>(); var roots = new List<(string Op, string Type)>();
        foreach (var f in files)
        {
            try
            {
                var p = new Parser(Lex(File.ReadAllText(Scanner.Full(root, f))), f);
                p.Document();
                types.AddRange(p.Types); execs.AddRange(p.Executables); roots.AddRange(p.SchemaRoots);
                if (p.Types.Count > 0) r.SchemaFiles.Add(f);
            }
            catch (GraphQLSyntaxException ex) { r.Error($"{f}:{ex.Line}", "syntax", ex.Message); }
        }
        var schema = BuildSchema(types, roots, r);
        r.Types = schema.Types.Count - Builtin.Count;
        r.Roots = new Dictionary<string, string?> { ["query"] = schema.Query, ["mutation"] = schema.Mutation, ["subscription"] = schema.Subscription };
        var operations = execs.Where(e => e.Kind != "fragment").ToList();
        var fragments = execs.Where(e => e.Kind == "fragment").ToList();
        r.Operations = operations.Select(o => o.Name == "" ? $"(anonymous {o.Kind}) {o.File}:{o.Line}" : $"{o.Kind} {o.Name}").ToList();
        r.Fragments = fragments.Count;
        if (r.Types == 0)
        {
            r.Status = "NO_SCHEMA";
            if (operations.Count + fragments.Count > 0) r.Warning($"{r.Scope}", "no-schema", "operations exist but no SDL schema was found in this scope: not verified (a code-first or remote schema is not read)");
            r.Client = Client(root, generated, operations);
            return r;
        }
        foreach (var t in schema.Types.Values.Where(t => !Builtin.Contains(t.Name)))
            r.TypeIndex.Add(new TypeSummary { Name = t.Name, Kind = t.Kind, At = $"{t.File}:{t.Line}",
                Fields = t.Kind == "INPUT_OBJECT" ? t.InputFields.Values.Select(v => $"{v.Name}: {v.Type}").ToList()
                    : t.Kind == "ENUM" ? t.Values.ToList()
                    : t.Fields.Values.Select(f => $"{f.Name}{(f.Args.Count == 0 ? "" : "(" + string.Join(", ", f.Args.Values.Select(a => $"{a.Name}: {a.Type}")) + ")")}: {f.Type}{(f.Deprecated != null ? " @deprecated" : "")}").ToList() });
        var v = new OperationValidator(schema, fragments, r);
        foreach (var op in operations) v.Operation(op);
        v.Fragments();
        foreach (var dup in operations.Where(o => o.Name != "").GroupBy(o => o.Name).Where(g => g.Count() > 1))
            r.Error($"{dup.ElementAt(1).File}:{dup.ElementAt(1).Line}", "duplicate-operation", $"operation name '{dup.Key}' is also defined at {dup.First().File}:{dup.First().Line}; generated clients need unique names");
        foreach (var op in operations.Where(o => o.Name != ""))
            r.OperationIndex.Add(new OperationSummary { Name = op.Name, Kind = op.Kind, At = $"{op.File}:{op.Line}", Types = v.TypesUsedBy(op).OrderBy(x => x).Take(12).ToList() });
        r.Client = Client(root, generated, operations);
        r.Status = r.ErrorCount > 0 ? "INVALID" : "VALID";
        return r;
    }

    static object Client(string root, List<string> generated, List<Executable> operations)
    {
        if (generated.Count == 0) return new { generatedFiles = 0, status = "NOT_FOUND", basis = "no StrawberryShake-generated source outside bin/obj (generation at build time is not read)" };
        var names = new HashSet<string>(StringComparer.Ordinal);
        foreach (var f in generated)
            foreach (Match m in Regex.Matches(File.ReadAllText(Scanner.Full(root, f)), @"\binterface\s+(I\w+)")) names.Add(m.Groups[1].Value);
        string Cap(string kind) => char.ToUpperInvariant(kind[0]) + kind.Substring(1);
        bool Has(Executable o) => names.Contains("I" + o.Name + Cap(o.Kind)) || (o.Name.EndsWith(Cap(o.Kind), StringComparison.Ordinal) && names.Contains("I" + o.Name));
        var named = operations.Where(o => o.Name != "").ToList();
        var missing = named.Where(o => !Has(o)).Select(o => $"{o.Kind} {o.Name} ({o.File}:{o.Line})").ToList();
        var known = new HashSet<string>(named.SelectMany(o => new[] { "I" + o.Name + Cap(o.Kind), "I" + o.Name }), StringComparer.Ordinal);
        var stale = names.Where(n => Regex.IsMatch(n, "^I\\w+(Query|Mutation|Subscription)$") && !known.Contains(n)).OrderBy(n => n, StringComparer.Ordinal).Take(20).ToList();
        return new
        {
            generatedFiles = generated.Count, status = missing.Count + stale.Count == 0 ? "COMPATIBLE" : "REGENERATION_NEEDED", missing, stale,
            basis = "operation interface names in generated source; regenerate with the repository's own StrawberryShake tooling, never by editing generated files",
        };
    }

    static Schema BuildSchema(List<TypeDef> defs, List<(string Op, string Type)> roots, ScopeResult r)
    {
        var s = new Schema();
        foreach (var b in Builtin) s.Types[b] = new TypeDef { Name = b, Kind = "SCALAR", File = "(built-in)" };
        foreach (var d in defs.Where(d => !d.Extension))
        {
            if (s.Types.TryGetValue(d.Name, out var prior))
                r.Error($"{d.File}:{d.Line}", "duplicate-type", $"type '{d.Name}' is already defined at {prior.File}:{prior.Line}");
            else s.Types[d.Name] = d;
        }
        foreach (var e in defs.Where(d => d.Extension))
        {
            if (!s.Types.TryGetValue(e.Name, out var t)) { r.Error($"{e.File}:{e.Line}", "unknown-type", $"extension of undefined type '{e.Name}'"); continue; }
            if (t.Kind != e.Kind) { r.Error($"{e.File}:{e.Line}", "extension-kind", $"'{e.Name}' is {t.Kind}, extended as {e.Kind}"); continue; }
            foreach (var f in e.Fields.Values) if (!t.Fields.ContainsKey(f.Name)) t.Fields[f.Name] = f; else r.Error($"{e.File}:{f.Line}", "duplicate-field", $"field '{e.Name}.{f.Name}' is already defined");
            foreach (var f in e.InputFields.Values) if (!t.InputFields.ContainsKey(f.Name)) t.InputFields[f.Name] = f; else r.Error($"{e.File}:{f.Line}", "duplicate-field", $"input field '{e.Name}.{f.Name}' is already defined");
            foreach (var x in e.Values) t.Values.Add(x);
            t.Members.AddRange(e.Members); t.Interfaces.AddRange(e.Interfaces);
        }
        string? Root(string op, string fallback) => roots.Where(x => x.Op == op).Select(x => x.Type).LastOrDefault() ?? (s.Types.ContainsKey(fallback) ? fallback : null);
        s.Query = Root("query", "Query"); s.Mutation = Root("mutation", "Mutation"); s.Subscription = Root("subscription", "Subscription");
        foreach (var (op, type) in roots)
            if (!s.Types.TryGetValue(type, out var rt) || rt.Kind != "OBJECT") r.Error("schema", "root-type", $"{op} root '{type}' is not a defined object type");
        bool Input(TypeRef t) => s.Types.TryGetValue(t.Named, out var x) && x.Kind is "SCALAR" or "ENUM" or "INPUT_OBJECT";
        bool Output(TypeRef t) => s.Types.TryGetValue(t.Named, out var x) && x.Kind != "INPUT_OBJECT";
        foreach (var t in s.Types.Values.Where(t => t.File != "(built-in)"))
        {
            foreach (var f in t.Fields.Values)
            {
                if (!s.Types.ContainsKey(f.Type.Named)) r.Error($"{t.File}:{f.Line}", "unknown-type", $"field '{t.Name}.{f.Name}' has undefined type '{f.Type.Named}'");
                else if (!Output(f.Type)) r.Error($"{t.File}:{f.Line}", "output-type", $"field '{t.Name}.{f.Name}' uses input type '{f.Type.Named}'");
                foreach (var a in f.Args.Values)
                    if (!s.Types.ContainsKey(a.Type.Named)) r.Error($"{t.File}:{a.Line}", "unknown-type", $"argument '{t.Name}.{f.Name}({a.Name})' has undefined type '{a.Type.Named}'");
                    else if (!Input(a.Type)) r.Error($"{t.File}:{a.Line}", "input-type", $"argument '{t.Name}.{f.Name}({a.Name})' uses output type '{a.Type.Named}'");
            }
            foreach (var f in t.InputFields.Values)
                if (!s.Types.ContainsKey(f.Type.Named)) r.Error($"{t.File}:{f.Line}", "unknown-type", $"input field '{t.Name}.{f.Name}' has undefined type '{f.Type.Named}'");
                else if (!Input(f.Type)) r.Error($"{t.File}:{f.Line}", "input-type", $"input field '{t.Name}.{f.Name}' uses output type '{f.Type.Named}'");
            foreach (var i in t.Interfaces)
            {
                if (!s.Types.TryGetValue(i, out var it) || it.Kind != "INTERFACE") { r.Error($"{t.File}:{t.Line}", "interface", $"'{t.Name}' implements '{i}', which is not a defined interface"); continue; }
                foreach (var f in it.Fields.Keys.Where(f => !t.Fields.ContainsKey(f))) r.Error($"{t.File}:{t.Line}", "interface", $"'{t.Name}' does not define '{f}' required by interface '{i}'");
            }
            foreach (var m in t.Members)
                if (!s.Types.TryGetValue(m, out var mt) || mt.Kind != "OBJECT") r.Error($"{t.File}:{t.Line}", "union", $"union '{t.Name}' member '{m}' is not a defined object type");
        }
        return s;
    }

    sealed class OperationValidator
    {
        readonly Schema s; readonly ScopeResult r;
        readonly Dictionary<string, Executable> frags = new();
        readonly HashSet<string> usedFragments = new();
        readonly HashSet<string> reported = new();
        public OperationValidator(Schema schema, List<Executable> fragments, ScopeResult result)
        {
            s = schema; r = result;
            foreach (var f in fragments)
                if (frags.TryGetValue(f.Name, out var prior)) Err(f.File, f.Line, "duplicate-fragment", $"fragment '{f.Name}' is also defined at {prior.File}:{prior.Line}");
                else frags[f.Name] = f;
        }

        sealed class Scope
        {
            public Executable Op = null!;
            public Dictionary<string, (TypeRef Type, bool HasDefault)>? Vars;
            public HashSet<string> Used = new();
            public Stack<string> Spreads = new();
            public HashSet<string> Types = new();
        }

        void Err(string file, int line, string code, string message) { if (reported.Add($"{file}:{line}:{message}")) r.Error($"{file}:{line}", code, message); }
        void Warn(string file, int line, string code, string message) { if (reported.Add($"w:{file}:{line}:{message}")) r.Warning($"{file}:{line}", code, message); }

        public void Operation(Executable op)
        {
            var sc = new Scope { Op = op, Vars = new() };
            foreach (var (name, type, hasDefault, line) in op.Variables)
            {
                if (sc.Vars.ContainsKey(name)) { Err(op.File, line, "duplicate-variable", $"variable '${name}' is declared twice"); continue; }
                sc.Vars[name] = (type, hasDefault);
                if (!s.Types.TryGetValue(type.Named, out var vt)) Err(op.File, line, "unknown-type", $"variable '${name}' has undefined type '{type.Named}'");
                else if (vt.Kind is not ("SCALAR" or "ENUM" or "INPUT_OBJECT")) Err(op.File, line, "input-type", $"variable '${name}' uses output type '{type.Named}'");
            }
            var rootName = op.Kind switch { "mutation" => s.Mutation, "subscription" => s.Subscription, _ => s.Query };
            if (rootName == null || !s.Types.TryGetValue(rootName, out var root)) { Err(op.File, op.Line, "root-type", $"the schema defines no {op.Kind} type"); return; }
            Selections(root, op.Set, op.File, sc);
            foreach (var name in sc.Vars.Keys.Where(n => !sc.Used.Contains(n))) Warn(op.File, op.Line, "unused-variable", $"variable '${name}' of {Label(op)} is never used");
            usedByOperation[op] = sc.Types;
        }

        readonly Dictionary<Executable, HashSet<string>> usedByOperation = new();
        public IEnumerable<string> TypesUsedBy(Executable op) => usedByOperation.TryGetValue(op, out var t) ? t : Enumerable.Empty<string>();

        public void Fragments()   // fragments on their own: type conditions, fields, and whether any operation uses them
        {
            foreach (var f in frags.Values)
            {
                if (!s.Types.TryGetValue(f.TypeCondition ?? "", out var t)) { Err(f.File, f.Line, "unknown-type", $"fragment '{f.Name}' is on undefined type '{f.TypeCondition}'"); continue; }
                if (t.Kind is not ("OBJECT" or "INTERFACE" or "UNION")) { Err(f.File, f.Line, "fragment-type", $"fragment '{f.Name}' is on {t.Kind} '{t.Name}'; fragments need an object, interface or union"); continue; }
                var sc = new Scope { Op = f };
                sc.Spreads.Push(f.Name);
                Selections(t, f.Set, f.File, sc);
                if (!usedFragments.Contains(f.Name)) Warn(f.File, f.Line, "unused-fragment", $"fragment '{f.Name}' is not used by any operation");
            }
        }

        static string Label(Executable e) => e.Name == "" ? $"anonymous {e.Kind}" : $"{e.Kind} {e.Name}";

        void Selections(TypeDef parent, List<Selection> set, string file, Scope sc)
        {
            sc.Types.Add(parent.Name);
            foreach (var sel in set)
            {
                if (sel.Kind == "field") Field(parent, sel, file, sc);
                else if (sel.Kind == "spread")
                {
                    usedFragments.Add(sel.Name);
                    if (!frags.TryGetValue(sel.Name, out var frag)) { Err(file, sel.Line, "unknown-fragment", $"fragment '{sel.Name}' is not defined"); continue; }
                    if (!s.Types.TryGetValue(frag.TypeCondition ?? "", out var ft)) continue;   // reported on the fragment
                    if (!Overlap(parent, ft)) Err(file, sel.Line, "fragment-spread", $"fragment '{sel.Name}' on '{ft.Name}' can never apply to '{parent.Name}'");
                    if (sc.Spreads.Contains(sel.Name)) { Err(file, sel.Line, "fragment-cycle", $"fragment '{sel.Name}' spreads itself"); continue; }
                    sc.Spreads.Push(sel.Name);
                    Selections(ft, frag.Set, frag.File, sc);
                    sc.Spreads.Pop();
                }
                else
                {
                    var name = sel.TypeCondition ?? parent.Name;
                    if (!s.Types.TryGetValue(name, out var it)) { Err(file, sel.Line, "unknown-type", $"inline fragment on undefined type '{name}'"); continue; }
                    if (it.Kind is not ("OBJECT" or "INTERFACE" or "UNION")) { Err(file, sel.Line, "fragment-type", $"inline fragment on {it.Kind} '{name}'"); continue; }
                    if (!Overlap(parent, it)) Err(file, sel.Line, "fragment-spread", $"inline fragment on '{name}' can never apply to '{parent.Name}'");
                    Selections(it, sel.Set ?? new(), file, sc);
                }
            }
        }

        void Field(TypeDef parent, Selection sel, string file, Scope sc)
        {
            if (sel.Name == "__typename") { if (sel.Set != null) Err(file, sel.Line, "leaf-selection", "'__typename' cannot have a selection"); return; }
            if (sel.Name is "__schema" or "__type" && parent.Name == s.Query) return;   // introspection
            if (parent.Kind == "UNION") { Err(file, sel.Line, "union-field", $"field '{sel.Name}' cannot be selected on union '{parent.Name}' directly; use an inline fragment"); return; }
            if (!parent.Fields.TryGetValue(sel.Name, out var field))
            {
                var near = parent.Fields.Keys.Where(k => k.Equals(sel.Name, StringComparison.OrdinalIgnoreCase) || Distance(k, sel.Name) <= 2).Take(3).ToList();
                Err(file, sel.Line, "unknown-field", $"field '{sel.Name}' does not exist on type '{parent.Name}'{(near.Count > 0 ? $" (did you mean {string.Join(", ", near.Select(n => "'" + n + "'"))}?)" : "")}");
                return;
            }
            if (field.Deprecated != null) Warn(file, sel.Line, "deprecated", $"field '{parent.Name}.{sel.Name}' is deprecated: {field.Deprecated}");
            var given = new HashSet<string>();
            foreach (var (name, value) in sel.Args)
            {
                if (!given.Add(name)) { Err(file, value.Line, "duplicate-argument", $"argument '{name}' is given twice to '{parent.Name}.{sel.Name}'"); continue; }
                if (!field.Args.TryGetValue(name, out var arg)) { Err(file, value.Line, "unknown-argument", $"'{parent.Name}.{sel.Name}' has no argument '{name}'"); continue; }
                CheckValue(arg.Type, arg.HasDefault, value, file, $"argument '{name}' of '{parent.Name}.{sel.Name}'", sc);
            }
            foreach (var arg in field.Args.Values.Where(a => a.Type.NonNull && !a.HasDefault && !given.Contains(a.Name)))
                Err(file, sel.Line, "missing-argument", $"'{parent.Name}.{sel.Name}' requires argument '{arg.Name}: {arg.Type}'");
            if (!s.Types.TryGetValue(field.Type.Named, out var target)) return;   // reported on the schema
            if (target.Kind is "SCALAR" or "ENUM")
            {
                if (sel.Set != null) Err(file, sel.Line, "leaf-selection", $"'{parent.Name}.{sel.Name}' is {field.Type} (a leaf) and cannot have a selection");
            }
            else if (sel.Set == null) Err(file, sel.Line, "missing-selection", $"'{parent.Name}.{sel.Name}' is {field.Type} and needs a selection of its fields");
            else Selections(target, sel.Set, file, sc);
        }

        void CheckValue(TypeRef type, bool locationDefault, Value v, string file, string where, Scope sc)
        {
            if (v.Kind == "Variable")
            {
                if (sc.Vars == null) return;   // a fragment on its own: variables are checked where an operation spreads it
                if (!sc.Vars.TryGetValue(v.Text, out var decl)) { Err(file, v.Line, "undefined-variable", $"variable '${v.Text}' is not declared by {Label(sc.Op)}"); return; }
                sc.Used.Add(v.Text);
                if (!Allowed(decl.Type, decl.HasDefault, type, locationDefault))
                    Err(file, v.Line, "variable-type", $"variable '${v.Text}' of type {decl.Type} cannot be used for {where}, which expects {type}");
                return;
            }
            if (v.Kind == "Null") { if (type.NonNull) Err(file, v.Line, "null-value", $"null given for {where}, which is {type}"); return; }
            if (type.Of != null)
            {
                if (v.Kind == "List") foreach (var item in v.Items) CheckValue(type.Of, false, item, file, where, sc);
                else CheckValue(type.Of, false, v, file, where, sc);   // input coercion: a single value becomes a one-item list
                return;
            }
            if (!s.Types.TryGetValue(type.Name, out var t)) return;
            switch (t.Kind)
            {
                case "ENUM":
                    if (v.Kind != "Enum" || !t.Values.Contains(v.Text)) Err(file, v.Line, "enum-value", $"'{v.Text}' is not a value of enum '{t.Name}' ({where})");
                    break;
                case "INPUT_OBJECT":
                    if (v.Kind != "Object") { Err(file, v.Line, "input-object", $"{where} expects input object '{t.Name}'"); break; }
                    var given = new HashSet<string>();
                    foreach (var (name, fv) in v.Fields)
                    {
                        given.Add(name);
                        if (!t.InputFields.TryGetValue(name, out var f)) Err(file, fv.Line, "unknown-input-field", $"input '{t.Name}' has no field '{name}'");
                        else CheckValue(f.Type, f.HasDefault, fv, file, $"field '{name}' of input '{t.Name}'", sc);
                    }
                    foreach (var f in t.InputFields.Values.Where(f => f.Type.NonNull && !f.HasDefault && !given.Contains(f.Name)))
                        Err(file, v.Line, "missing-input-field", $"input '{t.Name}' requires field '{f.Name}: {f.Type}' ({where})");
                    break;
                case "SCALAR":
                    var ok = t.Name switch
                    {
                        "Int" => v.Kind == "Int", "Float" => v.Kind is "Int" or "Float", "String" => v.Kind == "String",
                        "Boolean" => v.Kind == "Boolean", "ID" => v.Kind is "String" or "Int", _ => true,   // custom scalars: format not checked
                    };
                    if (!ok) Err(file, v.Line, "scalar-value", $"{v.Kind} value '{v.Text}' given for {where}, which is {t.Name}");
                    break;
            }
        }

        // GraphQL spec "IsVariableUsageAllowed": a nullable variable may fill a non-null position only when a default covers it.
        static bool Allowed(TypeRef variable, bool variableDefault, TypeRef location, bool locationDefault)
        {
            if (location.NonNull && !variable.NonNull)
                return (variableDefault || locationDefault) && Compatible(variable, location.Nullable());
            return Compatible(variable, location);
        }

        static bool Compatible(TypeRef variable, TypeRef location)
        {
            if (location.NonNull) return variable.NonNull && Compatible(variable.Nullable(), location.Nullable());
            if (variable.NonNull) return Compatible(variable.Nullable(), location);
            if (location.Of != null) return variable.Of != null && Compatible(variable.Of, location.Of);
            return variable.Of == null && variable.Name == location.Name;
        }

        HashSet<string> Possible(TypeDef t) => t.Kind switch
        {
            "OBJECT" => new HashSet<string> { t.Name },
            "INTERFACE" => new HashSet<string>(s.Types.Values.Where(o => o.Kind == "OBJECT" && o.Interfaces.Contains(t.Name)).Select(o => o.Name)),
            "UNION" => new HashSet<string>(t.Members),
            _ => new HashSet<string>(),
        };

        bool Overlap(TypeDef a, TypeDef b) => a.Name == b.Name || Possible(a).Overlaps(Possible(b));

        static int Distance(string a, string b)
        {
            var d = new int[a.Length + 1, b.Length + 1];
            for (var i = 0; i <= a.Length; i++) d[i, 0] = i;
            for (var j = 0; j <= b.Length; j++) d[0, j] = j;
            for (var i = 1; i <= a.Length; i++)
                for (var j = 1; j <= b.Length; j++)
                    d[i, j] = Math.Min(Math.Min(d[i - 1, j] + 1, d[i, j - 1] + 1), d[i - 1, j - 1] + (char.ToLowerInvariant(a[i - 1]) == char.ToLowerInvariant(b[j - 1]) ? 0 : 1));
            return d[a.Length, b.Length];
        }
    }

    // ---- lexer and parser -------------------------------------------------------------------------------------------

    enum K { Punct, Name, Int, Float, String, End }
    sealed class Tok { public K Kind; public string Text = ""; public int Line; }
    sealed class GraphQLSyntaxException : Exception { public int Line { get; } public GraphQLSyntaxException(int line, string message) : base(message) { Line = line; } }

    static List<Tok> Lex(string s)
    {
        var list = new List<Tok>(); int i = 0, line = 1;
        void Add(K kind, string text, int at) => list.Add(new Tok { Kind = kind, Text = text, Line = at });
        while (i < s.Length)
        {
            var c = s[i];
            if (c == '\n') { line++; i++; continue; }
            if (c == '﻿' || c == ',' || char.IsWhiteSpace(c)) { i++; continue; }
            if (c == '#') { while (i < s.Length && s[i] != '\n') i++; continue; }
            if (c == '.')
            {
                if (i + 2 < s.Length && s[i + 1] == '.' && s[i + 2] == '.') { Add(K.Punct, "...", line); i += 3; continue; }
                throw new GraphQLSyntaxException(line, "unexpected '.'");
            }
            if ("!$&()=:@[]{}|".IndexOf(c) >= 0) { Add(K.Punct, c.ToString(), line); i++; continue; }
            if (c == '_' || (c < 128 && char.IsLetter(c)))
            {
                var start = i;
                while (i < s.Length && (s[i] == '_' || (s[i] < 128 && char.IsLetterOrDigit(s[i])))) i++;
                Add(K.Name, s.Substring(start, i - start), line); continue;
            }
            if (c == '-' || char.IsDigit(c))
            {
                var start = i++; var isFloat = false;
                while (i < s.Length && (char.IsDigit(s[i]) || s[i] is '.' or 'e' or 'E' || (s[i] is '+' or '-' && s[i - 1] is 'e' or 'E')))
                {
                    if (s[i] is '.' or 'e' or 'E') isFloat = true;
                    i++;
                }
                Add(isFloat ? K.Float : K.Int, s.Substring(start, i - start), line); continue;
            }
            if (c == '"')
            {
                var startLine = line;
                var sb = new StringBuilder();
                if (i + 2 < s.Length && s[i + 1] == '"' && s[i + 2] == '"')
                {
                    i += 3;
                    while (i < s.Length && !(s[i] == '"' && i + 2 < s.Length && s[i + 1] == '"' && s[i + 2] == '"'))
                    {
                        if (s[i] == '\\' && i + 3 < s.Length && s[i + 1] == '"' && s[i + 2] == '"' && s[i + 3] == '"') { sb.Append("\"\"\""); i += 4; continue; }
                        if (s[i] == '\n') line++;
                        sb.Append(s[i++]);
                    }
                    if (i >= s.Length) throw new GraphQLSyntaxException(startLine, "unterminated block string");
                    i += 3;
                }
                else
                {
                    i++;
                    while (i < s.Length && s[i] != '"')
                    {
                        if (s[i] == '\n') throw new GraphQLSyntaxException(line, "unterminated string");
                        if (s[i] == '\\' && i + 1 < s.Length) sb.Append(s[i++]);
                        sb.Append(s[i++]);
                    }
                    if (i >= s.Length) throw new GraphQLSyntaxException(line, "unterminated string");
                    i++;
                }
                Add(K.String, sb.ToString(), startLine); continue;
            }
            throw new GraphQLSyntaxException(line, $"unexpected character '{c}'");
        }
        Add(K.End, "", line);
        return list;
    }

    static readonly HashSet<string> DefinitionWords = new() { "type", "interface", "union", "enum", "input", "scalar", "schema", "directive", "extend", "query", "mutation", "subscription", "fragment" };

    sealed class Parser
    {
        readonly List<Tok> t; readonly string file; int p;
        public readonly List<TypeDef> Types = new();
        public readonly List<Executable> Executables = new();
        public readonly List<(string Op, string Type)> SchemaRoots = new();
        public Parser(List<Tok> tokens, string file) { t = tokens; this.file = file; }

        Tok Peek => t[p];
        Tok Next() => t[p++];
        bool IsP(string s) => t[p].Kind == K.Punct && t[p].Text == s;
        bool IsName(string s) => t[p].Kind == K.Name && t[p].Text == s;
        GraphQLSyntaxException Fail(string expected) => new(Peek.Line, $"expected {expected} but found '{(Peek.Kind == K.End ? "end of file" : Peek.Text)}'");
        void Expect(string s) { if (!IsP(s)) throw Fail($"'{s}'"); p++; }
        string Name() { if (Peek.Kind != K.Name) throw Fail("a name"); return Next().Text; }
        void Description() { if (Peek.Kind == K.String) p++; }

        public void Document()
        {
            while (Peek.Kind != K.End)
            {
                Description();
                if (IsP("{")) { var line = Peek.Line; Executables.Add(new Executable { Kind = "query", File = file, Line = line, Set = SelectionSet() }); continue; }
                if (Peek.Kind != K.Name) throw Fail("a definition");
                switch (Peek.Text)
                {
                    case "query": case "mutation": case "subscription": Operation(); break;
                    case "fragment": Fragment(); break;
                    case "extend": p++; TypeSystem(true); break;
                    default: TypeSystem(false); break;
                }
            }
        }

        void TypeSystem(bool extension)
        {
            var tok = Next();
            TypeDef New(string kind) => new() { Name = Name(), Kind = kind, File = file, Line = tok.Line, Extension = extension };
            switch (tok.Text)
            {
                case "schema":
                    Directives();
                    if (IsP("{")) { p++; while (!IsP("}")) { var op = Name(); Expect(":"); SchemaRoots.Add((op, Name())); } p++; }
                    break;
                case "scalar": { var d = New("SCALAR"); Directives(); Types.Add(d); break; }
                case "type":
                case "interface":
                {
                    var d = New(tok.Text == "type" ? "OBJECT" : "INTERFACE");
                    if (IsName("implements"))
                    {
                        p++;
                        if (IsP("&")) p++;
                        d.Interfaces.Add(Name());
                        while (IsP("&") || (Peek.Kind == K.Name && !DefinitionWords.Contains(Peek.Text))) { if (IsP("&")) p++; d.Interfaces.Add(Name()); }   // legacy SDL separates with spaces or commas
                    }
                    Directives();
                    if (IsP("{")) { p++; while (!IsP("}")) { var f = FieldDefinition(); d.Fields[f.Name] = f; } p++; }
                    Types.Add(d); break;
                }
                case "union":
                {
                    var d = New("UNION"); Directives();
                    if (IsP("=")) { p++; if (IsP("|")) p++; d.Members.Add(Name()); while (IsP("|")) { p++; d.Members.Add(Name()); } }
                    Types.Add(d); break;
                }
                case "enum":
                {
                    var d = New("ENUM"); Directives();
                    if (IsP("{")) { p++; while (!IsP("}")) { Description(); d.Values.Add(Name()); Directives(); } p++; }
                    Types.Add(d); break;
                }
                case "input":
                {
                    var d = New("INPUT_OBJECT"); Directives();
                    if (IsP("{")) { p++; while (!IsP("}")) { var v = InputValue(); d.InputFields[v.Name] = v; } p++; }
                    Types.Add(d); break;
                }
                case "directive":
                    Expect("@"); Name();
                    if (IsP("(")) ArgumentDefinitions();
                    if (IsName("repeatable")) p++;
                    if (!IsName("on")) throw Fail("'on'");
                    p++; if (IsP("|")) p++; Name(); while (IsP("|")) { p++; Name(); }
                    break;
                default: throw new GraphQLSyntaxException(tok.Line, $"unexpected '{tok.Text}'");
            }
        }

        FieldDef FieldDefinition()
        {
            Description();
            var f = new FieldDef { Line = Peek.Line, Name = Name() };
            if (IsP("(")) f.Args = ArgumentDefinitions();
            Expect(":"); f.Type = Type(); f.Deprecated = Directives();
            return f;
        }

        Dictionary<string, InputValueDef> ArgumentDefinitions()
        {
            Expect("(");
            var map = new Dictionary<string, InputValueDef>();
            while (!IsP(")")) { var v = InputValue(); map[v.Name] = v; }
            p++;
            return map;
        }

        InputValueDef InputValue()
        {
            Description();
            var v = new InputValueDef { Line = Peek.Line, Name = Name() };
            Expect(":"); v.Type = Type();
            if (IsP("=")) { p++; ParseValue(true); v.HasDefault = true; }
            Directives();
            return v;
        }

        TypeRef Type()
        {
            TypeRef r;
            if (IsP("[")) { p++; r = new TypeRef { Of = Type() }; Expect("]"); }
            else r = new TypeRef { Name = Name() };
            if (IsP("!")) { p++; r.NonNull = true; }
            return r;
        }

        string? Directives()   // the @deprecated reason, when present
        {
            string? deprecated = null;
            while (IsP("@"))
            {
                p++;
                var name = Name();
                var args = IsP("(") ? Arguments(true) : new List<(string Name, Value Value)>();
                if (name == "deprecated") deprecated = args.Where(a => a.Name == "reason").Select(a => a.Value.Text).FirstOrDefault() ?? "No longer supported";
            }
            return deprecated;
        }

        void Operation()
        {
            var tok = Next();
            var e = new Executable { Kind = tok.Text, File = file, Line = tok.Line };
            if (Peek.Kind == K.Name) e.Name = Name();
            if (IsP("("))
            {
                p++;
                while (!IsP(")"))
                {
                    var line = Peek.Line;
                    Expect("$"); var name = Name(); Expect(":"); var type = Type(); var hasDefault = false;
                    if (IsP("=")) { p++; ParseValue(true); hasDefault = true; }
                    Directives();
                    e.Variables.Add((name, type, hasDefault, line));
                }
                p++;
            }
            Directives();
            e.Set = SelectionSet();
            Executables.Add(e);
        }

        void Fragment()
        {
            var tok = Next();
            var e = new Executable { Kind = "fragment", File = file, Line = tok.Line, Name = Name() };
            if (!IsName("on")) throw Fail("'on'");
            p++; e.TypeCondition = Name(); Directives();
            e.Set = SelectionSet();
            Executables.Add(e);
        }

        List<Selection> SelectionSet()
        {
            var line = Peek.Line;
            Expect("{");
            var list = new List<Selection>();
            while (!IsP("}")) list.Add(ParseSelection());
            p++;
            if (list.Count == 0) throw new GraphQLSyntaxException(line, "empty selection set");
            return list;
        }

        Selection ParseSelection()
        {
            var line = Peek.Line;
            if (IsP("..."))
            {
                p++;
                if (IsName("on")) { p++; var condition = Name(); Directives(); return new Selection { Kind = "inline", TypeCondition = condition, Set = SelectionSet(), Line = line }; }
                if (Peek.Kind == K.Name) { var name = Name(); Directives(); return new Selection { Kind = "spread", Name = name, Line = line }; }
                Directives();
                return new Selection { Kind = "inline", Set = SelectionSet(), Line = line };
            }
            var s = new Selection { Kind = "field", Line = line };
            var first = Name();
            if (IsP(":")) { p++; s.Alias = first; s.Name = Name(); } else s.Name = first;
            if (IsP("(")) s.Args = Arguments(false);
            Directives();
            if (IsP("{")) s.Set = SelectionSet();
            return s;
        }

        List<(string Name, Value Value)> Arguments(bool constant)
        {
            Expect("(");
            var list = new List<(string Name, Value Value)>();
            while (!IsP(")")) { var name = Name(); Expect(":"); list.Add((name, ParseValue(constant))); }
            p++;
            return list;
        }

        Value ParseValue(bool constant)
        {
            var tok = Peek;
            var v = new Value { Line = tok.Line };
            if (IsP("$"))
            {
                if (constant) throw new GraphQLSyntaxException(tok.Line, "a variable is not allowed in a constant value");
                p++; v.Kind = "Variable"; v.Text = Name(); return v;
            }
            if (IsP("[")) { p++; v.Kind = "List"; while (!IsP("]")) v.Items.Add(ParseValue(constant)); p++; return v; }
            if (IsP("{")) { p++; v.Kind = "Object"; while (!IsP("}")) { var name = Name(); Expect(":"); v.Fields.Add((name, ParseValue(constant))); } p++; return v; }
            p++;
            v.Text = tok.Text;
            v.Kind = tok.Kind switch
            {
                K.Int => "Int", K.Float => "Float", K.String => "String",
                K.Name => tok.Text is "true" or "false" ? "Boolean" : tok.Text == "null" ? "Null" : "Enum",
                _ => throw new GraphQLSyntaxException(tok.Line, $"unexpected '{(tok.Kind == K.End ? "end of file" : tok.Text)}' in a value"),
            };
            return v;
        }
    }

    // ---- model ------------------------------------------------------------------------------------------------------

    sealed class TypeRef
    {
        public string Name = ""; public TypeRef? Of; public bool NonNull;
        public string Named => Of?.Named ?? Name;
        public TypeRef Nullable() => new() { Name = Name, Of = Of };
        public override string ToString() => (Of == null ? Name : "[" + Of + "]") + (NonNull ? "!" : "");
    }
    sealed class InputValueDef { public string Name = ""; public TypeRef Type = new(); public bool HasDefault; public int Line; }
    sealed class FieldDef { public string Name = ""; public TypeRef Type = new(); public Dictionary<string, InputValueDef> Args = new(); public string? Deprecated; public int Line; }
    sealed class TypeDef
    {
        public string Name = "", Kind = "", File = ""; public int Line; public bool Extension;
        public Dictionary<string, FieldDef> Fields = new(); public Dictionary<string, InputValueDef> InputFields = new();
        public List<string> Interfaces = new(), Members = new(); public HashSet<string> Values = new();
    }
    sealed class Value { public string Kind = "", Text = ""; public int Line; public List<Value> Items = new(); public List<(string Name, Value Value)> Fields = new(); }
    sealed class Selection { public string Kind = "", Name = ""; public string? Alias, TypeCondition; public List<(string Name, Value Value)> Args = new(); public List<Selection>? Set; public int Line; }
    sealed class Executable
    {
        public string Kind = "", Name = "", File = ""; public string? TypeCondition; public int Line;
        public List<(string Name, TypeRef Type, bool HasDefault, int Line)> Variables = new(); public List<Selection> Set = new();
    }
    sealed class Schema { public Dictionary<string, TypeDef> Types = new(); public string? Query, Mutation, Subscription; }

    public sealed class Finding { public string At { get; set; } = ""; public string Code { get; set; } = ""; public string Message { get; set; } = ""; }
    public sealed class TypeSummary { public string Name { get; set; } = ""; public string Kind { get; set; } = ""; public string At { get; set; } = ""; public List<string> Fields { get; set; } = new(); }
    public sealed class OperationSummary { public string Name { get; set; } = ""; public string Kind { get; set; } = ""; public string At { get; set; } = ""; public List<string> Types { get; set; } = new(); }
    public sealed class ScopeResult
    {
        public string Scope { get; set; } = "."; public string Status { get; set; } = "VALID";
        public List<string> SchemaFiles { get; set; } = new(); public int DocumentFiles { get; set; } public int Types { get; set; }
        public Dictionary<string, string?> Roots { get; set; } = new(); public List<string> Operations { get; set; } = new(); public int Fragments { get; set; }
        public List<Finding> Errors { get; set; } = new(); public List<Finding> Warnings { get; set; } = new();
        public int ErrorCount { get; set; } public int WarningCount { get; set; }
        public object? Client { get; set; } public bool Cached { get; set; }
        public List<TypeSummary> TypeIndex { get; set; } = new(); public List<OperationSummary> OperationIndex { get; set; } = new();
        internal void Error(string at, string code, string message) { ErrorCount++; if (Errors.Count < MaxFindings) Errors.Add(new Finding { At = at, Code = code, Message = message }); }
        internal void Warning(string at, string code, string message) { WarningCount++; if (Warnings.Count < MaxFindings) Warnings.Add(new Finding { At = at, Code = code, Message = message }); }
    }
    sealed class CachedScope { public string Key { get; set; } = ""; public ScopeResult? Result { get; set; } }
    sealed class CacheFile { public string Analyzer { get; set; } = ""; public Dictionary<string, CachedScope> Scopes { get; set; } = new(); }

    static Dictionary<string, CachedScope> ReadCache(string path, string version)
    {
        try
        {
            if (!File.Exists(path)) return new();
            var c = JsonSerializer.Deserialize<CacheFile>(File.ReadAllText(path), Scanner.Json);
            return c != null && c.Analyzer == version ? c.Scopes : new();
        }
        catch { return new(); }   // unreadable: validate again
    }

    static void WriteCache(string path, string version, Dictionary<string, CachedScope> scopes)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var pending = path + "." + Guid.NewGuid().ToString("N");   // unique per writer: concurrent runs never share a temporary file
        try
        {
            File.WriteAllText(pending, JsonSerializer.Serialize(new CacheFile { Analyzer = version, Scopes = scopes }, Scanner.Json));
            if (File.Exists(path)) File.Replace(pending, path, null);
            else
            {
                try { File.Move(pending, path); }
                catch (IOException) when (File.Exists(path)) { File.Replace(pending, path, null); }
            }
        }
        catch (IOException) { }   // another writer replaced it at the same moment: the cache is an optimization only
        finally { if (File.Exists(pending)) File.Delete(pending); }
    }
}
