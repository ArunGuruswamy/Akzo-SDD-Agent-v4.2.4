# Third-party notices

Akzo SDD Agent — Developed and maintained by Arun RG

## Bundled third-party material
All agent instructions, workflow modules, templates, scripts, and documentation in this repository are original.

The dual `net8.0` / `net472` architecture analyzer (`copilot\modules\analyzers\architecture`, built from original source in `src\ArchitectureAnalyzer` by `scripts\build-analyzer.ps1`) uses Roslyn 5.3.0 and MSBuildLocator 1.11.2. Published runtime dependencies are unmodified. Versions below reflect the restored dependency inventory; compile/build-only references are distinguished from redistribution. Final published host inventories must be checked before packaging.

| Package (version) | License | Copyright |
|---|---|---|
| Microsoft.CodeAnalysis.Common, .CSharp, .CSharp.Workspaces, .Workspaces.Common, .Workspaces.MSBuild (5.3.0); Microsoft.CodeAnalysis.Analyzers (5.3.0-2.25625.1, build-only); Microsoft.Build.Locator (1.11.2) | MIT | © Microsoft Corporation |
| Microsoft.NET.StringTools (17.11.48 / 18.0.2); Microsoft.IO.Redist (6.1.0); Microsoft.VisualStudio.SolutionPersistence (1.0.52); Microsoft.Bcl.AsyncInterfaces (9.0.0) | MIT | © Microsoft Corporation |
| Microsoft.Extensions.DependencyInjection(.Abstractions), .Logging(.Abstractions), .Options, .Primitives (9.0.0) | MIT | © Microsoft Corporation |
| System.Collections.Immutable, System.Composition (and its parts), System.Diagnostics.DiagnosticSource, System.IO.Pipelines, System.Reflection.Metadata, System.Text.Encodings.Web, System.Text.Json, System.Threading.Tasks.Dataflow (9.0.0); System.Configuration.ConfigurationManager, System.Reflection.MetadataLoadContext (8.0.0 / 9.0.0); System.Diagnostics.EventLog, System.Security.Cryptography.ProtectedData, System.Text.Encoding.CodePages, System.Threading.Channels (8.0.0); System.Security.Cryptography.Pkcs (8.0.2), .Xml (8.0.5) | MIT | © Microsoft Corporation |
| System.Buffers, System.Memory, System.Numerics.Vectors, System.Threading.Tasks.Extensions (4.6.0); System.Runtime.CompilerServices.Unsafe (6.1.0); System.Security.Principal.Windows (5.0.0); System.ValueTuple (4.5.0) | MIT | © Microsoft Corporation |
| Humanizer.Core (2.14.1) | MIT | Copyright (c) .NET Foundation and Contributors |
| Newtonsoft.Json (13.0.3, if retained in published build-host material) | MIT | Copyright © James Newton-King 2008 |
| Microsoft.VisualStudio.Setup.Configuration.Interop (3.2.2146, if retained in published build-host material) | Microsoft license terms (https://go.microsoft.com/fwlink/?linkid=831109), not MIT | © Microsoft Corporation |

**Review needed:** Microsoft.VisualStudio.Setup.Configuration.Interop is under Microsoft's own license terms. If present in final published hosts, confirm redistribution approval before the package leaves the team; retaining this notice does not establish approval.

Microsoft.Build and Microsoft.Build.Framework 17.11.48 (`net8.0`) / 18.0.2 (`net472`) are MIT-licensed compile references with runtime assets excluded. At execution, the selected installed SDK/Visual Studio MSBuild owns its matching runtime dependency closure. Those installed binaries are staged only into a local runtime cache for that machine, not patched into shipped hosts or redistributed with the package. SHA-256 content fingerprints of the selected toolset closure and analyzer/host inputs invalidate the runtime cache after changes. Local caching does not grant redistribution rights; the installed toolset remains governed by its own license.

MIT License (applies to every package above marked MIT, with the copyright notice listed for it):

> Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

## Tools used at run time (not bundled or redistributed)
The scripts call these tools only if they are already installed on the user's machine. They are governed by their own licenses.

| Tool | Used by | Required |
|------|---------|----------|
| Windows PowerShell / PowerShell | `scripts/*.ps1`, `copilot/modules/investigate/scripts/akzo.ps1` | Yes |
| .NET runtime 8 or later (`dotnet`) and .NET SDK for the `net8.0` host; .NET Framework and compatible Visual Studio/Build Tools MSBuild 18+ for the `net472` host | helper `arch` (dual local analyzer hosts) | No: a missing compatible host/toolset is reported; source fallback and partial/syntax coverage never count as semantic verification |
| Git | installer repository check, helper `state`/`task` commands | Yes |
| Python with the `graphify` package | helper `graph` command | No (optional) |
| .NET Framework Windows Forms and UI Automation (part of Windows) | launchers (`*.cmd`, `Install-MasterAgent.ps1`, `Start-Development.ps1`), helper `pick` file dialog, `scripts/test-gui.ps1` | Yes for the windows; `-NoGui` and `-Source` work without them |
| `pdftotext` (Poppler) | helper `pick` for `.pdf` requirement files | No (optional) |
| Visual Studio 2022 or 2026 automation interface (EnvDTE, through the `Microsoft.VisualStudio.Interop.dll` of the installed Visual Studio) | helper `sonar -Check issues` (reads the Error List, opens and saves files), `scripts/test-ide.ps1` | No (optional; without it the IDE source reports UNAVAILABLE) |
| GitHub Copilot in VS Code or Visual Studio 2026 | runs the agent | Yes |
| SonarQube Server or SonarQube Cloud (Web API), SonarQube MCP server, SonarQube for IDE, Sonar analyzers and scanners | helper `sonar` command (read-only Web API queries), agent section 6a | No (optional; used only when the developer has configured them) |

SonarQube and SonarQube Cloud are products of SonarSource. The integration calls their public Web API and tools; no SonarSource code, rules text, or plugin content is included.

Update this file if any third-party code or content is added, keeping all required license and attribution notices.

## Design references (not bundled, not used at run time)
Tree-sitter, Continue, Aider (repository maps), and Microsoft Semantic Kernel / Microsoft Agent Framework were studied as design references for incremental indexing, context retrieval, and tool orchestration. No code, text, grammar, or dependency from them is included; the symbol extraction, ranking, memory, and security controls in this package are original implementations in Windows PowerShell. Adopting any of them later would require a licence, supply-chain, and security review and an update to this file.