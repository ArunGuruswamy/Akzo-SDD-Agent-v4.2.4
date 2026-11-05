param(
    [Parameter(Mandatory = $true)][string]$BaselineAnalyzer,
    [string]$CandidateAnalyzer,
    [int]$Rounds = 1
)
$ErrorActionPreference = 'Stop'
if (-not $CandidateAnalyzer) { $CandidateAnalyzer = Join-Path (Split-Path $PSScriptRoot) 'copilot\modules\analyzers\architecture\Akzo.ArchitectureAnalyzer.dll' }
if ($Rounds -lt 1 -or $Rounds -gt 5) { throw 'Rounds must be between one and five.' }
foreach ($analyzer in $BaselineAnalyzer, $CandidateAnalyzer) { if (-not (Test-Path -LiteralPath $analyzer -PathType Leaf)) { throw "Analyzer not found: $analyzer" } }
$temp = Join-Path ([IO.Path]::GetTempPath()) "sdd-matched-$([guid]::NewGuid().ToString('N'))"
function Put($file, $text) { $full = Join-Path $temp $file; New-Item -ItemType Directory -Path (Split-Path $full) -Force | Out-Null; [IO.File]::WriteAllText($full, $text) }
try {
    $major = ([version]((& dotnet --version) -replace '-.*$', '')).Major
    Put 'workspace\NuGet.Config' '<configuration><packageSources><clear /></packageSources></configuration>'
    for ($p = 0; $p -lt 5; $p++) {
        $references = if ($p) { '<ItemGroup><ProjectReference Include="..\P{0}\P{0}.csproj" /></ItemGroup>' -f ($p - 1) } else { '' }
        Put "workspace\P$p\P$p.csproj" ('<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFramework>net' + $major + '.0</TargetFramework></PropertyGroup>' + $references + '</Project>')
        for ($d = 0; $d -lt 10; $d++) { Put "workspace\P$p\File$d.cs" "namespace P$p { public class Worker$d { public int Run() => 1; } public interface IWorker$d { int Run(); } }" }
    }
    & dotnet restore "$temp\workspace\P4\P4.csproj" --configfile "$temp\workspace\NuGet.Config" --nologo | Out-Host
    if ($LASTEXITCODE) { throw 'Offline fixture restore failed.' }
    $rows = @(for ($round = 1; $round -le $Rounds; $round++) {
        $order = if ($round % 2) { @('baseline', 'candidate') } else { @('candidate', 'baseline') }
        foreach ($label in $order) {
            $analyzer = if ($label -eq 'baseline') { $BaselineAnalyzer } else { $CandidateAnalyzer }
            Put 'workspace\P0\File0.cs' 'namespace P0 { public class Worker0 { public int Run() => 1; } public interface IWorker0 { int Run(); } }'
            $cache = Join-Path $temp "$label-$round"
            foreach ($phase in 'cold', 'warm', 'incremental', 'query') {
                if ($phase -eq 'incremental') { Put 'workspace\P0\File0.cs' 'namespace P0 { public class Worker0 { public int Run() => 2; } public interface IWorker0 { int Run(); } }' }
                $timer = [Diagnostics.Stopwatch]::StartNew()
                $arguments = @($(if ($phase -eq 'query') { 'query' } else { 'scan' }), '--root', "$temp\workspace", '--out', $cache)
                if ($phase -eq 'query') { $arguments += @('--terms', 'Worker0') }
                $raw = & dotnet $analyzer @arguments | Out-String
                $exit = $LASTEXITCODE
                $timer.Stop()
                if ($exit) { throw "$label $phase failed: $raw" }
                $result = $raw | ConvertFrom-Json
                [pscustomobject]@{ runtime = $label; round = $round; phase = $phase; elapsedMs = $timer.ElapsedMilliseconds
                    scannerMs = $(if ($phase -eq 'query') { $result.scan.elapsedMs } else { $result.elapsedMs })
                    bytes = [Text.Encoding]::UTF8.GetByteCount($raw); status = $result.status
                    changed = $result.changedDocuments; revalidated = $result.revalidatedDocuments }
            }
        }
    })
    [pscustomobject]@{ fixture = '5 renamed SDK projects, 50 files, 100 types; transitive project references; body-only edit'
        sdk = (& dotnet --version); rounds = $Rounds; measurements = $rows
        limitations = 'Direct net8 hosts, not IDE/model latency; concurrent processes may affect timings. No inference of model/tool/token consumption. Conservative consumer revalidation may cost more on body-only edits.' } | ConvertTo-Json -Depth 5
} finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force } }
