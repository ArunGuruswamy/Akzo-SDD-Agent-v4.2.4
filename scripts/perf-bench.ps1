<#
.SYNOPSIS
  Development-loop benchmark: the previous helper against this one on the same generated layered .NET repository.
.DESCRIPTION
  Generates a repository shaped like a Functions + CQRS + FluentValidation + GraphQL solution (one solution, five
  projects, five test projects, one folder per feature), then runs both helpers interleaved round by round (machine load
  changes from minute to minute) and reports, per scenario, the median wall-clock time, peak working set of the helper
  process, output size, files returned, and the index cache event:
    cold start (index removed), warm start, exact-symbol lookup, handler investigation, business-rule lookup,
    repeat lookup in the same feature, lookup after a one-file edit, profile detection, guarded build command, and
    staged test selection (affected; the previous helper has no equivalent).
  What this cannot measure: model interactions, tokens, tool calls the agent makes, files the agent reads, and test run
  durations (the generated projects are not restored or built). Those are reported as NOT VERIFIED.
  Everything runs under a temporary folder that is removed at the end; the real profile is never touched.
.EXAMPLE
  .\scripts\perf-bench.ps1 -BaselineZip ..\Akzo-Agent-3.6.0.zip -Rounds 5
.NOTES
  Akzo SDD Agent — Developed and maintained by Arun RG
#>
param(
    [string]$BaselineZip = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Akzo-Agent-3.6.0.zip'),
    [string]$BaselineDir,
    [int]$Features = 60,
    [int]$Rounds = 5,
    [string]$Out,
    [switch]$KeepTemp
)
$ErrorActionPreference = 'Stop'
$Source = Split-Path -Parent $PSScriptRoot
$tmp = Join-Path $env:TEMP "akzo-perf-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
New-Item -ItemType Directory -Force $tmp | Out-Null

function New-BenchRepo([string]$repo, [int]$count) {
    $w = { param($rel, $text) $f = Join-Path $repo $rel; New-Item -ItemType Directory -Force (Split-Path $f) | Out-Null; [IO.File]::WriteAllText($f, $text) }
    & $w 'Shop.sln' ''
    $refs = @{ Function = 'Application', 'Contracts'; Application = 'Domain', 'Data', 'Contracts'; Data = 'Domain'; Domain = @(); Contracts = @() }
    foreach ($p in $refs.Keys) {
        $pr = (@($refs[$p]) | ForEach-Object { "<ProjectReference Include=""..\$_\$_.csproj"" />" }) -join ''
        $pkg = @{ Function = '<PackageReference Include="Microsoft.Azure.Functions.Worker" Version="1.0.0" />'; Data = '<PackageReference Include="StrawberryShake.Server" Version="13.0.0" />'; Application = '<PackageReference Include="FluentValidation" Version="11.0.0" />' }[$p]
        & $w "src/$p/$p.csproj" "<Project Sdk=""Microsoft.NET.Sdk""><ItemGroup>$pkg$pr</ItemGroup></Project>"
        & $w "tests/$p.Tests/$p.Tests.csproj" "<Project Sdk=""Microsoft.NET.Sdk""><ItemGroup><PackageReference Include=""xunit"" Version=""2.9.0"" /><ProjectReference Include=""..\..\src\$p\$p.csproj"" /></ItemGroup></Project>"
    }
    $n = 0
    foreach ($noun in 'Order', 'Invoice', 'Customer', 'Product', 'Shipment', 'Payment', 'Refund', 'Supplier', 'Warehouse', 'Stock', 'Contract', 'Quote') {
        foreach ($verb in 'Create', 'Update', 'Cancel', 'Approve', 'Export') {
            if ($n -ge $count) { break }; $n++; $f = "$verb$noun$n"
            & $w "src/Function/$noun/${f}Function.cs" "namespace Fn.$noun;`npublic sealed class ${f}Function`n{`n    [Function(""$f"")]`n    public Task Run() => _dispatcher.Send(new ${f}Command());`n}`n"
            & $w "src/Application/$noun/Commands/${f}Command.cs" "namespace App.$noun;`npublic sealed record ${f}Command(string Name, bool Approved);`n"
            & $w "src/Application/$noun/Commands/${f}CommandHandler.cs" "namespace App.$noun;`npublic sealed class ${f}CommandHandler`n{`n    public Task Handle(${f}Command c)`n    {`n        if (c.Approved) { return Task.CompletedTask; }`n        return Task.CompletedTask;`n    }`n}`n"
            & $w "src/Application/$noun/Validators/${f}Validator.cs" "namespace App.$noun;`npublic sealed class ${f}Validator : AbstractValidator<${f}Command>`n{`n    public ${f}Validator() { RuleFor(x => x.Name).NotEmpty().WithMessage(""Name is required.""); }`n}`n"
            & $w "src/Data/$noun/${f}Repository.cs" "namespace Data.$noun;`npublic sealed class ${f}Repository { public Task Save() => Task.CompletedTask; }`n"
            & $w "src/Data/$noun/$f.graphql" "mutation $f { id }"
            & $w "src/Domain/$noun/${f}Entity.cs" "namespace Domain.$noun;`npublic sealed class ${f}Entity { public string Name { get; set; } }`n"
            & $w "tests/Application.Tests/$noun/${f}CommandHandlerTests.cs" "public class ${f}CommandHandlerTests { [Fact] public void Handles() { } }`n"
            & $w "tests/Application.Tests/$noun/${f}ValidatorTests.cs" "public class ${f}ValidatorTests { [Fact] public void Validates() { } }`n"
            & $w "tests/Data.Tests/$noun/${f}RepositoryTests.cs" "public class ${f}RepositoryTests { [Fact] public void Saves() { } }`n"
        }
    }
    & $w 'src/Function/Program.cs' "var host = new HostBuilder().ConfigureServices(s => { s.AddScoped<IDispatcher, Dispatcher>(); }).Build();`n"
    $ErrorActionPreference = 'Continue'
    & git -C $repo init -q; & git -C $repo config user.email b@b; & git -C $repo config user.name b; & git -C $repo config core.autocrlf false
    & git -C $repo add -A; & git -C $repo commit -qm init 2>$null
}
function Get-Median([double[]]$v) { $s = @($v | Sort-Object); if (-not $s.Count) { return $null }; if ($s.Count % 2) { $s[[int][math]::Floor($s.Count / 2)] } else { ($s[$s.Count / 2 - 1] + $s[$s.Count / 2]) / 2 } }

try {
    if (-not $BaselineDir) {
        if (-not (Test-Path $BaselineZip)) { throw "Baseline package not found: $BaselineZip (give -BaselineZip or -BaselineDir)." }
        $BaselineDir = Join-Path $tmp 'baseline'; Expand-Archive $BaselineZip -DestinationPath $BaselineDir
    }
    $baseVersion = (Get-Content (Join-Path $BaselineDir 'VERSION') -TotalCount 1).Trim()
    $newVersion = (Get-Content (Join-Path $Source 'VERSION') -TotalCount 1).Trim()
    if (-not $Out) { $Out = Join-Path $Source "benchmark\perf-$newVersion.md" }
    $helpers = [ordered]@{ $baseVersion = (Join-Path $BaselineDir 'copilot\modules\investigate\scripts\akzo.ps1'); $newVersion = (Join-Path $Source 'copilot\modules\investigate\scripts\akzo.ps1') }
    $repo = Join-Path $tmp 'repo'; New-BenchRepo $repo $Features
    $edit = Join-Path $repo 'src\Application\Order\Validators\CreateOrder1Validator.cs'; $original = [IO.File]::ReadAllText($edit)
    # Runs the helper inside a child Windows PowerShell and reports that process's peak working set.
    $wrap = Join-Path $tmp 'measure.ps1'
    Set-Content $wrap '$p = @{}; for ($i = 2; $i -lt $args.Count; $i += 2) { $p[$args[$i].TrimStart([char]45)] = $args[$i + 1] }; $o = & $args[0] $args[1] @p 2>$null | Out-String; [Console]::Out.Write($o); [Console]::Out.Write("`nPEAKMB:" + [math]::Round([Diagnostics.Process]::GetCurrentProcess().PeakWorkingSet64 / 1MB))'
    $homes = @{}
    foreach ($v in $helpers.Keys) {
        $h = Join-Path $tmp "home-$v"; $homes[$v] = $h
        New-Item -ItemType Directory -Force "$h\tasks\bench\PBI-1" | Out-Null
        [pscustomobject]@{ version = 1; tasksDir = ''; repos = @([pscustomobject]@{ id = 'bench'; path = $repo; purpose = 'perf' }) } | ConvertTo-Json -Depth 4 | Set-Content "$h\repos.json"
        [IO.File]::WriteAllText("$h\tasks\bench\PBI-1\refined-pbi.md", "# PBI-1 Order approval`nAC1: an order needs a name; approved orders are processed.`n")
        $env:AKZO_AGENT_HOME = $h
        $null = & powershell.exe -NoProfile -File $helpers[$v] authorize -Repo bench -Reference 'benchmark run (no real approval)' -Classification internal 2>&1
    }
    function Invoke-Measured([string]$v, [string[]]$a) {
        $env:AKZO_AGENT_HOME = $homes[$v]
        $ErrorActionPreference = 'Continue'   # Windows PowerShell 5.1 turns redirected native stderr into an error under 'Stop'
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $o = (& powershell.exe -NoProfile -File $wrap $helpers[$v] @a 2>$null | Out-String)
        $sw.Stop()
        $peak = if ($o -match 'PEAKMB:(\d+)') { [int]$Matches[1] } else { 0 }
        $text = ($o -replace 'PEAKMB:\d+\s*$', '').Trim()
        $j = try { $text | ConvertFrom-Json } catch { $null }
        [pscustomobject]@{ ms = $sw.ElapsedMilliseconds; mb = $peak; chars = $text.Length; json = $j }
    }
    $scenarios = [ordered]@{
        'cold start (task, index removed)' = @('task', '-Id', 'PBI-1', '-Repo', 'bench')
        'warm start (task again)'          = @('task', '-Id', 'PBI-1', '-Repo', 'bench')
        'exact-symbol lookup'              = @('context', '-Repo', 'bench', '-Query', 'CreateOrder1Validator')
        'handler investigation'            = @('context', '-Repo', 'bench', '-Query', 'create order command handler')
        'business-rule lookup'             = @('context', '-Repo', 'bench', '-Query', 'order name required approved rule')
        'repeat lookup, same feature'      = @('context', '-Repo', 'bench', '-Query', 'create order command handler')
        'lookup after a one-file edit'     = @('context', '-Repo', 'bench', '-Query', 'create order validator')
        'profile detection, first call'    = @('profile', '-Repo', 'bench')
        'profile detection, repeat'        = @('profile', '-Repo', 'bench')
        'guarded build command'            = @('guard', '-Repo', 'bench', '-Line', 'dotnet build Shop.sln')
        'staged test selection (affected)' = @('affected', '-Repo', 'bench')
        'Fix Issue start, cold (index removed)' = 'fix-start'   # what each version's agent text runs to start a fix
        'Fix Issue start, warm'                 = 'fix-start'
    }
    $fixStart = @{ issue = , @('issue', '-Repo', 'bench', '-Query', 'CreateOrder1Validator', '-Text', 'S3776 complexity')
        separate = @(@('branchinfo', '-Repo', 'bench'), @('profile', '-Repo', 'bench', '-Task', 'fix', '-Query', 'S3776 complexity'), @('context', '-Repo', 'bench', '-Query', 'CreateOrder1Validator')) }
    $hasIssue = @{}; foreach ($v in $helpers.Keys) { $hasIssue[$v] = [bool](Select-String -Path $helpers[$v] -Pattern "ValidateSet\('home'.*'issue'" -Quiet) }
    $fixCalls = @{}   # helper calls per Fix Issue start, per version
    $res = @{}; foreach ($v in $helpers.Keys) { foreach ($s in $scenarios.Keys) { $res["$v|$s"] = New-Object Collections.Generic.List[object] } }
    foreach ($v in $helpers.Keys) { $null = Invoke-Measured $v @('home') }   # first calls discarded (disk cache, JIT)
    for ($r = 0; $r -lt $Rounds; $r++) {
        $order = @($helpers.Keys); if ($r % 2) { [array]::Reverse($order) }
        foreach ($v in $order) {
            Remove-Item (Join-Path $homes[$v] 'maps') -Recurse -Force -ErrorAction SilentlyContinue
            foreach ($s in $scenarios.Keys) {
                if ($s -eq 'lookup after a one-file edit') { [IO.File]::WriteAllText($edit, $original + "// edit $r`n") }
                if ($s -eq 'staged test selection (affected)' -and -not (Select-String -Path $helpers[$v] -SimpleMatch "'affected'" -Quiet)) { continue }
                if ($scenarios[$s] -eq 'fix-start') {
                    if ($s -like '*cold*') { Remove-Item (Join-Path $homes[$v] 'maps') -Recurse -Force -ErrorAction SilentlyContinue }
                    $list = $fixStart[$(if ($hasIssue[$v]) { 'issue' } else { 'separate' })]   # indexed, not piped: a one-call list must not unroll into its words
                    $m = @(foreach ($c in $list) { Invoke-Measured $v $c }); $fixCalls[$v] = $m.Count
                    $res["$v|$s"].Add([pscustomobject]@{ ms = ($m | Measure-Object ms -Sum).Sum; mb = ($m | Measure-Object mb -Maximum).Maximum; chars = ($m | Measure-Object chars -Sum).Sum; json = $null })
                    continue
                }
                $res["$v|$s"].Add((Invoke-Measured $v $scenarios[$s]))
            }
            [IO.File]::WriteAllText($edit, $original)
        }
    }
    Remove-Item Env:AKZO_AGENT_HOME -ErrorAction SilentlyContinue
    $files = @(& git -C $repo ls-files).Count
    $lines = New-Object Collections.Generic.List[string]
    $lines.Add("# Development-loop benchmark: $baseVersion vs $newVersion"); $lines.Add('')
    $lines.Add("Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm') by ``scripts\perf-bench.ps1``: $files tracked files ($Features features, 5 projects + 5 test projects), $Rounds interleaved rounds, Windows PowerShell $($PSVersionTable.PSVersion), $((& git --version) -join ''). Each value is the median over the rounds; every call is a fresh helper process, as in the IDE.")
    $lines.Add(''); $lines.Add("| Scenario | $baseVersion ms | $newVersion ms | change | peak MB ($baseVersion / $newVersion) | output chars | files returned | index event ($newVersion) |"); $lines.Add('|---|---:|---:|---:|---|---|---|---|')
    foreach ($s in $scenarios.Keys) {
        $b = $res["$baseVersion|$s"]; $n = $res["$newVersion|$s"]
        $bm = Get-Median @($b | ForEach-Object { $_.ms }); $nm = Get-Median @($n | ForEach-Object { $_.ms })
        $chg = if ($bm -and $nm) { '{0:+0;-0}%' -f [math]::Round(100 * ($nm - $bm) / $bm) } else { 'n/a' }
        $fc = { param($l) $x = @($l | Where-Object { $_.json -and $_.json.PSObject.Properties['files'] } | Select-Object -First 1); if ($x.Count) { "$(@($x[0].json.files).Count)+$(@($x[0].json.more).Count) more" } else { '-' } }
        $ev = @($n | Where-Object { $_.json } | ForEach-Object { if ($_.json.memory.event) { $_.json.memory.event } elseif ($_.json.architecture.memory.event) { $_.json.architecture.memory.event } elseif ($_.json.cache) { "profile cache $($_.json.cache)" } } | Where-Object { $_ } | Select-Object -Unique) -join ', '
        $lines.Add("| $s | $(if ($bm) { $bm } else { 'n/a' }) | $nm | $chg | $(Get-Median @($b | ForEach-Object { $_.mb })) / $(Get-Median @($n | ForEach-Object { $_.mb })) | $(Get-Median @($b | ForEach-Object { $_.chars })) / $(Get-Median @($n | ForEach-Object { $_.chars })) | $(& $fc $b) / $(& $fc $n) | $ev |")
    }
    $aff = @($res["$newVersion|staged test selection (affected)"] | Where-Object { $_.json } | Select-Object -First 1)
    $hit = @($res["$newVersion|repeat lookup, same feature"] | Where-Object { $_.json } | ForEach-Object { $_.json.memory.hitRatePct } | Select-Object -Last 1)
    $lines.Add('')
    if ($aff.Count) { $aj = $aff[0].json; $lines.Add("Staged test selection for the one-file edit: status ``$($aj.status)``, build $(@($aj.stages.A_build).Count) project(s), $(@($aj.stages.B_focused).Count) focused filter(s), $(@($aj.stages.C_regression).Count) of $($aj.testProjects) test projects for regression, full suite once at the final gate (``$($aj.stages.D_full.command)``).") }
    $lines.Add("Index cache hit rate after the rounds ($newVersion, last 50 synchronizations): $($hit -join '')%.")
    $lines.Add("Fix Issue start: $baseVersion makes $($fixCalls[$baseVersion]) helper calls (branchinfo, profile -Task fix, context), $newVersion makes $($fixCalls[$newVersion]) (issue); in the IDE each helper call is also one agent tool call. Times are the sum of the calls.")
    $lines.Add(''); $lines.Add('**NOT VERIFIED (needs real Copilot runs):** model turns, tokens, tool calls made by the agent, files the agent opened, and test run durations. The helper calls above are what the agent runs; fewer and smaller calls are an input to agent speed, not a measurement of it.')
    [IO.File]::WriteAllLines($Out, [string[]]$lines, (New-Object Text.UTF8Encoding($false)))
    $lines
} finally {
    Remove-Item Env:AKZO_AGENT_HOME -ErrorAction SilentlyContinue
    if (-not $KeepTemp) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue } else { Write-Output "Temp kept: $tmp" }
}
