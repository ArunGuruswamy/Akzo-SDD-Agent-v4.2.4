using System.Diagnostics;
using System.Reflection;
using System.Reflection.Metadata;
using System.Reflection.PortableExecutable;
using System.Text;
using System.Xml.Linq;
using Microsoft.Build.Locator;

namespace Akzo.ArchitectureAnalyzer;

// The installed toolset owns its runtime dependencies. Never modify the shipped Roslyn hosts.
internal static class BuildHostStaging
{
    internal static string Fingerprint { get; private set; } = "";

    internal static int? Initialize(string[] args)
    {
        if (args.FirstOrDefault() is "locate" or "graphql") return null;   // no MSBuild: index lookup and GraphQL parsing
        var syntaxOnly = args.Contains("--syntax-only");
#if NETFRAMEWORK
        var pinned = Option(args, "--msbuild-path");
        var instances = MSBuildLocator.QueryVisualStudioInstances(new VisualStudioInstanceQueryOptions
        {
            DiscoveryTypes = DiscoveryType.VisualStudioSetup
        }).Where(i => i.Version.Major >= 18).OrderByDescending(i => i.Version).ToArray();
        // Roslyn's remote framework host independently chooses the highest installed VS.
        // Its selection is not externally pinnable: require an unambiguous compatible instance.
        if (!syntaxOnly && instances.Length > 1)
            throw new InvalidOperationException("Multiple compatible Visual Studio MSBuild instances are installed. Roslyn's remote framework BuildHost cannot be pinned externally; refusing to guess a match: " +
                string.Join("; ", instances.Select(i => i.MSBuildPath + " (" + i.Version + ")")));
        var selected = pinned == null ? instances.FirstOrDefault() :
            instances.SingleOrDefault(i => string.Equals(Path.GetFullPath(i.MSBuildPath), Path.GetFullPath(pinned), StringComparison.OrdinalIgnoreCase));
        if (pinned != null && selected == null) throw new InvalidOperationException("The pinned MSBuild instance is no longer installed: " + pinned);
        if (selected == null)
        {
            Fingerprint = "no-compatible-framework-msbuild";
            if (!syntaxOnly) throw new InvalidOperationException("The framework analyzer requires installed Visual Studio MSBuild 18 or later; use the dotnet host instead.");
            return null;
        }
        var bundle = Option(args, "--bundle-path") ?? AppDomain.CurrentDomain.BaseDirectory;
        var runtime = RuntimeClosure(selected.MSBuildPath);
        var bundled = BundleFiles(bundle).ToArray();
        if (args.FirstOrDefault() == "cache-test") return TestCache(args, selected.MSBuildPath, bundle);
        Fingerprint = ContentFingerprint(runtime.Concat(bundled), selected.MSBuildPath + "|" + selected.Name + "|" + selected.Version);
        if (Option(args, "--bundle-path") == null && !syntaxOnly)
        {
            var output = Option(args, "--out") ?? throw new ArgumentException("--out is required");
            // Remote framework hosts do not consistently support MAX_PATH, even when the parent does.
            var cache = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "AkzoSDD", "hosts");
            if (Path.Combine(cache, Fingerprint, "BuildHost-netcore",
                "Microsoft.CodeAnalysis.Workspaces.MSBuild.BuildHost.runtimeconfig.json").Length >= 260)
                throw new PathTooLongException("The local analyzer host cache exceeds the framework host path limit. Use a shorter Windows user profile; no application files were changed.");
            Directory.CreateDirectory(cache);
            var destination = Path.Combine(cache, Fingerprint);
            if (!Directory.Exists(destination))
            {
                var pending = Path.Combine(cache, "." + Guid.NewGuid().ToString("N"));
                Directory.CreateDirectory(pending);
                try
                {
                    foreach (var file in bundled)
                    {
                        var relative = file.Substring(Path.GetFullPath(bundle).TrimEnd('\\', '/').Length + 1);
                        var target = Path.Combine(pending, relative);
                        Directory.CreateDirectory(Path.GetDirectoryName(target)!);
                        File.Copy(file, target);
                    }
                    Overlay(pending, runtime);
                    Overlay(Path.Combine(pending, "BuildHost-net472"), runtime);
                    try { Directory.Move(pending, destination); }
                    catch (IOException) when (Directory.Exists(destination)) { } // another caller published the same immutable cache
                }
                finally { if (Directory.Exists(pending)) Directory.Delete(pending, true); }
            }
            var exe = Path.Combine(destination, "Akzo.ArchitectureAnalyzer.exe");
            var start = new ProcessStartInfo(exe, string.Join(" ", args.Concat(new[]
            {
                "--msbuild-path", selected.MSBuildPath, "--bundle-path", Path.GetFullPath(bundle)
            }).Select(Quote))) { UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true };
            using var child = Process.Start(start) ?? throw new InvalidOperationException("Unable to launch staged analyzer");
            var stdout = child.StandardOutput.ReadToEndAsync();
            var stderr = child.StandardError.ReadToEndAsync();
            child.WaitForExit();
            Console.Out.Write(stdout.GetAwaiter().GetResult());
            Console.Error.Write(stderr.GetAwaiter().GetResult());
            return child.ExitCode;
        }
        MSBuildLocator.RegisterInstance(selected);
#else
        if (!syntaxOnly)
        {
            var selected = MSBuildLocator.QueryVisualStudioInstances().OrderByDescending(i => i.Version).FirstOrDefault();
            if (selected != null)
            {
                Fingerprint = ContentFingerprint(RuntimeClosure(selected.MSBuildPath).Concat(BundleFiles(AppDomain.CurrentDomain.BaseDirectory)), selected.MSBuildPath + "|" + selected.Name + "|" + selected.Version);
                MSBuildLocator.RegisterInstance(selected);
            }
            else Fingerprint = "no-dotnet-msbuild";
        }
#endif
        return null;
    }

    internal static string ContentFingerprint(IEnumerable<string> paths, string identity = "")
    {
        var lines = paths.Select(Path.GetFullPath).Distinct(StringComparer.OrdinalIgnoreCase).OrderBy(p => p, StringComparer.OrdinalIgnoreCase)
            .Select(p => p + "=" + Compatibility.Hash(File.ReadAllBytes(p)));
        return Compatibility.Hash(Encoding.UTF8.GetBytes(identity + "\n" + string.Join("\n", lines)));
    }

    static string? Option(string[] args, string name)
    {
        var index = Array.IndexOf(args, name);
        return index >= 0 && index + 1 < args.Length ? args[index + 1] : null;
    }

    static IEnumerable<string> BundleFiles(string directory)
    {
        // Only published app files and Roslyn's explicitly named host directories, never the caller's workspace.
        if ((File.GetAttributes(directory) & FileAttributes.ReparsePoint) != 0)
            throw new InvalidDataException("Published app directory must not be a reparse point: " + directory);
        foreach (var file in Directory.GetFiles(directory))
            if (new[] { ".dll", ".exe", ".config", ".json", ".pdb" }.Contains(Path.GetExtension(file), StringComparer.OrdinalIgnoreCase))
            {
                if ((File.GetAttributes(file) & FileAttributes.ReparsePoint) != 0)
                    throw new InvalidDataException("Published app file must not be a reparse point: " + file);
                yield return file;
            }
        foreach (var host in new[] { "BuildHost-net472", "BuildHost-netcore" })
        {
            var path = Path.Combine(directory, host);
            if (!Directory.Exists(path)) continue;
            foreach (var file in HostFiles(path)) yield return file;
        }
    }

    static IEnumerable<string> HostFiles(string directory)
    {
        if ((File.GetAttributes(directory) & FileAttributes.ReparsePoint) != 0)
            throw new InvalidDataException("Published host directory must not be a reparse point: " + directory);
        foreach (var file in Directory.GetFiles(directory))
        {
            if ((File.GetAttributes(file) & FileAttributes.ReparsePoint) != 0)
                throw new InvalidDataException("Published host file must not be a reparse point: " + file);
            yield return file;
        }
        foreach (var child in Directory.GetDirectories(directory))
            foreach (var file in HostFiles(child)) yield return file;
    }

    static int TestCache(string[] args, string toolset, string bundle)
    {
        var output = Path.GetFullPath(Option(args, "--out") ?? throw new ArgumentException("--out is required"));
        var fixture = Path.Combine(output, "fingerprint-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(fixture);
        try
        {
            foreach (var file in RuntimeClosure(toolset)) File.Copy(file, Path.Combine(fixture, Path.GetFileName(file)));
            var hostFixture = Path.Combine(fixture, "bundle");
            Directory.CreateDirectory(hostFixture);
            var config = Directory.GetFiles(Path.Combine(bundle, "BuildHost-net472"), "*.exe.config").Single();
            var copiedConfig = Path.Combine(hostFixture, Path.GetFileName(config));
            File.Copy(config, copiedConfig);
            string Key() => ContentFingerprint(RuntimeClosure(fixture).Concat(BundleFiles(bundle)).Concat(BundleFiles(hostFixture)), toolset);
            var cold = Key();
            var warm = Key();
            var dependency = Path.Combine(fixture, "System.Collections.Immutable.dll");
            var version = AssemblyName.GetAssemblyName(dependency).FullName;
            var primary = Compatibility.Hash(File.ReadAllBytes(Path.Combine(fixture, "Microsoft.Build.Framework.dll")));
            // Appending a byte preserves PE metadata/AssemblyVersion but changes dependency content.
            using (var stream = new FileStream(dependency, FileMode.Append, FileAccess.Write)) stream.WriteByte(0x42);
            var changed = Key();
            var sameVersion = version == AssemblyName.GetAssemblyName(dependency).FullName;
            var primaryUnchanged = primary == Compatibility.Hash(File.ReadAllBytes(Path.Combine(fixture, "Microsoft.Build.Framework.dll")));
            File.AppendAllText(copiedConfig, "\n");
            var hostChanged = Key();
            if (cold != warm || cold == changed || changed == hostChanged || !sameVersion || !primaryUnchanged)
                throw new InvalidOperationException("Runtime dependency fingerprint regression failed.");
            Console.Write(System.Text.Json.JsonSerializer.Serialize(new
            {
                status = "PASSED", warmUnchanged = cold == warm, dependencyBytesInvalidate = cold != changed,
                sameAssemblyVersion = sameVersion, primaryUnchanged, hostConfigurationInvalidate = changed != hostChanged, dependency = Path.GetFileName(dependency)
            }));
            return 0;
        }
        finally { Directory.Delete(fixture, true); } // only the unique directory created above
    }

    static List<string> RuntimeClosure(string directory)
    {
        var pending = new Queue<string>(Directory.GetFiles(directory, "Microsoft.Build*.dll").Where(p => !Path.GetFileName(p).Equals("Microsoft.Build.Locator.dll", StringComparison.OrdinalIgnoreCase)));
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var result = new List<string>();
        while (pending.Count != 0)
        {
            var path = pending.Dequeue();
            if (!seen.Add(path)) continue;
            result.Add(path);
            using var stream = File.OpenRead(path);
            using var pe = new PEReader(stream);
            if (!pe.HasMetadata) throw new InvalidDataException("MSBuild dependency has no managed metadata: " + path);
            var metadata = pe.GetMetadataReader();
            foreach (var reference in metadata.AssemblyReferences)
            {
                var name = metadata.GetString(metadata.GetAssemblyReference(reference).Name);
                var dependency = Path.Combine(directory, name + ".dll");
                if (File.Exists(dependency)) pending.Enqueue(dependency);
            }
        }
        return result;
    }

    static void Overlay(string directory, IEnumerable<string> runtime)
    {
        if (!Directory.Exists(directory)) return;
        foreach (var source in runtime)
        {
            var target = Path.Combine(directory, Path.GetFileName(source));
            if (!File.Exists(target)) continue;
            var installed = AssemblyName.GetAssemblyName(source);
            var bundled = AssemblyName.GetAssemblyName(target);
            if (installed.Version > bundled.Version) File.Copy(source, target, true);
        }
        XNamespace ns = "urn:schemas-microsoft-com:asm.v1";
        foreach (var config in Directory.GetFiles(directory, "*.exe.config"))
        {
            var xml = XDocument.Load(config);
            var root = xml.Root ?? throw new InvalidDataException("Empty host configuration: " + config);
            var runtimeElement = root.Element("runtime");
            if (runtimeElement == null) { runtimeElement = new XElement("runtime"); root.Add(runtimeElement); }
            var binding = runtimeElement.Element(ns + "assemblyBinding");
            if (binding == null) { binding = new XElement(ns + "assemblyBinding"); runtimeElement.Add(binding); }
            foreach (var dll in Directory.GetFiles(directory, "*.dll"))
            {
                var name = AssemblyName.GetAssemblyName(dll);
                var token = name.GetPublicKeyToken();
                if (token == null || token.Length == 0) continue;
                foreach (var old in binding.Elements(ns + "dependentAssembly").Where(e => (string?)e.Element(ns + "assemblyIdentity")?.Attribute("name") == name.Name).ToArray()) old.Remove();
                binding.Add(new XElement(ns + "dependentAssembly",
                    new XElement(ns + "assemblyIdentity", new XAttribute("name", name.Name!), new XAttribute("publicKeyToken", BitConverter.ToString(token).Replace("-", "").ToLowerInvariant()), new XAttribute("culture", "neutral")),
                    new XElement(ns + "bindingRedirect", new XAttribute("oldVersion", "0.0.0.0-" + name.Version), new XAttribute("newVersion", name.Version!))));
            }
            xml.Save(config);
        }
    }

    static string Quote(string value) => "\"" + System.Text.RegularExpressions.Regex.Replace(value, @"(\\*)""", "$1$1\\\"").TrimEnd('\\') +
        new string('\\', value.Reverse().TakeWhile(c => c == '\\').Count() * 2) + "\"";
}
