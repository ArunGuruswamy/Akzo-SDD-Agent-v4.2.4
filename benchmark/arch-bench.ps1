<#
.SYNOPSIS
  Timing of the architecture analyzer on a generated .NET solution: cold scan (no index), warm scan (nothing changed),
  incremental scan (one file changed), and a query. Prints a markdown table; times are medians of -Rounds runs, except the
  cold scan, which is timed once per round on a fresh index.
.EXAMPLE
  .\benchmark\arch-bench.ps1 -Projects 20 -FilesPerProject 40 -Rounds 3
.NOTES
  Akzo SDD Agent — Developed and maintained by Arun RG
#>
param([int]$Projects = 20, [int]$FilesPerProject = 40, [int]$Rounds = 3, [string]$Analyzer = (Join-Path (Split-Path -Parent $PSScriptRoot) 'copilot\modules\analyzers\architecture\Akzo.ArchitectureAnalyzer.dll'))
$ErrorActionPreference = 'Stop'
$root = Join-Path ([IO.Path]::GetTempPath()) "akzo-arch-bench-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$utf8 = New-Object Text.UTF8Encoding($false)
$tfm = "net$(([version]((& dotnet --version) -replace '-.*$')).Major).0"
try {
    # A layered chain: each project references the one before it; every class implements an interface and calls the previous layer.
    $slnx = New-Object Text.StringBuilder; [void]$slnx.Append('<Solution>')
    for ($p = 1; $p -le $Projects; $p++) {
        $name = 'Bench.Lib{0:D2}' -f $p; $dir = Join-Path $root "src\$name"; New-Item -ItemType Directory -Force $dir | Out-Null
        $ref = if ($p -gt 1) { '<ItemGroup><ProjectReference Include="..\Bench.Lib{0:D2}\Bench.Lib{0:D2}.csproj" /></ItemGroup>' -f ($p - 1) } else { '' }
        [IO.File]::WriteAllText("$dir\$name.csproj", '<Project Sdk="Microsoft.NET.Sdk">' + "<PropertyGroup><TargetFramework>$tfm</TargetFramework><Nullable>enable</Nullable></PropertyGroup>$ref</Project>", $utf8)
        [void]$slnx.Append("<Project Path=`"src/$name/$name.csproj`" />")
        for ($f = 1; $f -le $FilesPerProject; $f++) {
            $prev = if ($p -gt 1) { 'Bench.Lib{0:D2}.IService{1}' -f ($p - 1), $f } else { '' }
            $body = if ($prev) { "    private readonly $prev _previous;`n    public Service$f($prev previous) => _previous = previous;`n    public int Run$f(int x) => _previous.Run$f(x) + 1;`n" } else { "    public int Run$f(int x) => x + 1;`n" }
            [IO.File]::WriteAllText("$dir\Service$f.cs", "namespace $name;`n`npublic interface IService$f`n{`n    int Run$f(int x);`n}`n`npublic sealed class Service$f : IService$f`n{`n$body}`n", $utf8)
        }
    }
    [void]$slnx.Append('</Solution>'); [IO.File]::WriteAllText("$root\Bench.slnx", $slnx.ToString(), $utf8)
    $env:MSBUILDDISABLENODEREUSE = '1'
    $null = & dotnet restore "$root\Bench.slnx" 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'dotnet restore failed.' }
    $time = { param([string[]]$a) $sw = [Diagnostics.Stopwatch]::StartNew(); $o = & dotnet $Analyzer @a; $sw.Stop(); [pscustomobject]@{ ms = [int]$sw.Elapsed.TotalMilliseconds; out = ($o -join '') | ConvertFrom-Json } }
    $median = { param($xs) $s = @($xs | Sort-Object); $s[[int][math]::Floor(($s.Count - 1) / 2)] }
    $cold = @(); $warm = @(); $incr = @(); $query = @(); $last = $null
    for ($i = 0; $i -lt $Rounds; $i++) {
        $cache = Join-Path $root "cache$i"
        $c = & $time @('scan', '--root', $root, '--out', $cache); $cold += $c.ms; $last = $c.out
        $warm += (& $time @('scan', '--root', $root, '--out', $cache)).ms
        Add-Content (Join-Path $root ('src\Bench.Lib{0:D2}\Service1.cs' -f $Projects)) "// round $i"   # the top project: it and every project it references reload
        $incr += (& $time @('scan', '--root', $root, '--out', $cache)).ms
        $query += (& $time @('query', '--root', $root, '--out', $cache, '--terms', 'service run')).ms
    }
    $files = $Projects * $FilesPerProject
    Write-Output "Architecture analyzer on a generated $tfm solution: $Projects projects, $files C# files ($(2 * $files) types), coverage: $($last.coverage.summary)."
    Write-Output "Machine: $((Get-CimInstance Win32_Processor | Select-Object -First 1).Name.Trim()), $([math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)) GB RAM; $(& dotnet --version) SDK. Medians of $Rounds rounds; each time includes starting the process."
    Write-Output ''
    Write-Output '| Run | Time |'
    Write-Output '|---|---|'
    Write-Output "| Cold scan (no index: MSBuild loads every project) | $(& $median $cold) ms |"
    Write-Output "| Warm scan (nothing changed: hashes only) | $(& $median $warm) ms |"
    Write-Output "| Incremental scan (1 file changed in the top project: it and all $($Projects - 1) projects below it reload; 1 file re-extracted) | $(& $median $incr) ms |"
    Write-Output "| Query (after an incremental scan) | $(& $median $query) ms |"
} finally { Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue }
