param([string]$BaselineHelper, [string]$ResultsFile, [ValidateRange(1, 20)][int]$Rounds = 5)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$helper = Join-Path $root 'copilot\modules\investigate\scripts\akzo.ps1'
$temp = Join-Path ([IO.Path]::GetTempPath()) "sdd-retrieval-$([guid]::NewGuid().ToString('N'))"
$savedHome = $env:AKZO_AGENT_HOME
$passes = 0
$measurements = New-Object Collections.Generic.List[object]
$invocations = 0
function Assert($value, $message) {
    if (-not $value) { throw $message }
    $script:passes++
    Write-Output "PASS $message"
}
function Put($path, $text) {
    New-Item -ItemType Directory -Path (Split-Path $path) -Force | Out-Null
    [IO.File]::WriteAllText($path, $text)
}
function Run([string[]]$arguments, [string]$entry = $helper, [switch]$Failure) {
    $script:invocations++
    $ErrorActionPreference = 'Continue'
    $raw = & powershell -NoProfile -File $entry @arguments 2>&1 | Out-String
    $code = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($Failure) { Assert ($code -ne 0) "invalid request refused: $($arguments -join ' ')"; return }
    if ($code) { throw $raw }
    $raw | ConvertFrom-Json
}
function Evidence($value) {
    $value.PSObject.Properties.Remove('repo')
    $value.scan = [pscustomobject]@{}
    $value | ConvertTo-Json -Depth 30 -Compress
}
try {
    $env:AKZO_AGENT_HOME = Join-Path $temp 'state'
    $repo = Join-Path $temp 'workspace'
    $major = ([version]((& dotnet --version) -replace '-.*$', '')).Major
    $project = '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFramework>net' + $major + '.0</TargetFramework><NuGetAudit>false</NuGetAudit></PropertyGroup>{0}</Project>'
    Put "$repo\Library\Library.csproj" ($project -f '')
    Put "$repo\Consumer\Consumer.csproj" ($project -f '<ItemGroup><ProjectReference Include="..\Library\Library.csproj" /></ItemGroup>')
    Put "$repo\Library\Service.cs" 'namespace Fixture; public class Service { public int Run(int value) => value; }'
    Put "$repo\Consumer\Consumer.cs" 'namespace Fixture; public class Consumer { public int Use() => new Service().Run(1); }'
    Put "$repo\NuGet.Config" '<configuration><packageSources><clear /></packageSources></configuration>'
    Put "$repo\.gitignore" "**/bin/`n**/obj/"
    & git -C $repo init --quiet --initial-branch=fixture
    if ($LASTEXITCODE) { throw 'Fixture Git initialization failed.' }
    & dotnet build "$repo\Consumer\Consumer.csproj" --nologo --configfile "$repo\NuGet.Config" | Out-Host
    if ($LASTEXITCODE) { throw 'Offline fixture build failed.' }
    & git -C $repo add --all
    & git -C $repo -c user.name=Fixture -c user.email=fixture@example.invalid commit --quiet -m fixture
    if ($LASTEXITCODE) { throw 'Fixture baseline commit failed.' }
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'copilot\modules\investigate\scripts\multi-repo.ps1'), [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw 'Routing source does not parse.' }
    $function = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-WorkspaceArchitecture' }, $true)
    . ([scriptblock]::Create($function.Extent.Text))
    function Invoke-Quiet([string]$exe) { & $exe @args }
    function Get-ProjectGraph { throw 'Routing must not build the structural graph.' }
    function Get-ArchitectureConventions { throw 'Routing must not rediscover conventions.' }
    $route = Get-WorkspaceArchitecture ([pscustomobject]@{ path = $repo; workspace = $repo }) -RoutingOnly
    Assert ($route.projects.Count -eq 2 -and $route.typescriptWorkspaces.Count -eq 0) 'C# routing skips project graph, framework and convention parsing'
    Put "$repo\ui\package.json" '{"devDependencies":{"typescript":"*"}}'
    Put "$repo\ui\angular.json" '{"version":1,"projects":{}}'
    Put "$repo\outside\package.json" 'not JSON'
    $route = Get-WorkspaceArchitecture ([pscustomobject]@{ path = $repo; workspace = "$repo\ui" }) -RoutingOnly
    Assert ($route.projects.Count -eq 0 -and $route.typescriptWorkspaces.Count -eq 1 -and $route.typescriptWorkspaces[0] -eq "$repo\ui") 'nested TypeScript routing excludes backend and unrelated malformed manifests'
    New-Item -ItemType Directory -Path "$repo\empty" -Force | Out-Null
    $route = Get-WorkspaceArchitecture ([pscustomobject]@{ path = $repo; workspace = "$repo\empty" }) -RoutingOnly
    Assert ($route.projects.Count -eq 0 -and $route.typescriptWorkspaces.Count -eq 0) 'empty nested workspace does not inherit sibling projects'
    Remove-Item -LiteralPath "$repo\outside\package.json"
    $batch = Run @('arch', '-Repo', $repo, '-Queries', 'Service;Consumer')
    Assert ($batch.status -eq 'OK' -and $batch.scanCount -eq 1 -and $batch.coverage.semantic -eq 2 -and $batch.results.Count -eq 2) 'normal helper batches queries with one semantic refresh and complete coverage'
    foreach ($row in $batch.results) {
        $single = Run @('arch', '-Repo', $repo, '-Query', $row.query)
        Assert ((Evidence $single) -ceq (Evidence $row.evidence)) "batch evidence equals existing single query: $($row.query)"
    }
    $warm = Run @('arch', '-Repo', $repo, '-Queries', 'Service;Service')
    Assert ($warm.scan.status -eq 'UP_TO_DATE' -and $warm.results.Count -eq 2 -and $warm.results[0].query -eq 'Service' -and $warm.results[1].query -eq 'Service') 'warm batch reuses semantic index and preserves request order and duplicates'
    Put "$repo\Library\Service.cs" 'namespace Fixture; public class Service { public int Run(long value) => (int)value; }'
    $changed = Run @('arch', '-Repo', $repo, '-Queries', 'Service;Consumer')
    $fresh = Run @('arch', '-Repo', $repo, '-Queries', 'Service;Consumer', '-Update')
    Assert ($changed.scan.changedDocuments -eq 1 -and $changed.scan.revalidatedDocuments -eq 2 -and $changed.scan.full -eq $false) 'batched signature edit revalidates the unchanged consumer dependency'
    for ($i = 0; $i -lt 2; $i++) {
        Assert ((Evidence $changed.results[$i].evidence) -ceq (Evidence $fresh.results[$i].evidence)) "incremental batch equals fresh semantic retrieval: $i"
    }
    $before = (& git -C $repo status --porcelain=v1) -join "`n"
    $affected = Run @('affected', '-Repo', $repo, '-Base', 'fixture')
    Assert ($affected.directProjects -contains 'Library/Library.csproj' -and $affected.affectedProjects -contains 'Consumer/Consumer.csproj') 'focused test selection still follows backend project dependencies after routing optimization'
    $review = Run @('review', '-Repo', $repo, '-Base', 'fixture')
    Assert ($review.csharpFilesReviewed -eq 1 -and @($review.analysis | Where-Object { $_.status -eq 'NOT VERIFIED' }).Count -eq 1 -and ($review.notChecked -join ';') -match 'SonarCloud') 'review preserves explicit unverified build and Sonar status'
    Assert (((& git -C $repo status --porcelain=v1) -join "`n") -ceq $before) 'optimized selection and review do not modify the analyzed repository'
    Run @('arch', '-Repo', $repo, '-Query', 'Service', '-Queries', 'Consumer') -Failure
    Run @('arch', '-Repo', $repo, '-Queries', 'Service;') -Failure
    Run @('arch', '-Repo', $repo, '-Queries', ((1..9) -join ';')) -Failure
    Run @('arch', '-Repo', "$repo\ui", '-Queries', 'Component;Service') -Failure
    if ($BaselineHelper) {
        if (-not (Test-Path -LiteralPath $BaselineHelper -PathType Leaf)) { throw 'Baseline helper not found.' }
        $candidateState = $env:AKZO_AGENT_HOME
        $env:AKZO_AGENT_HOME = Join-Path $temp 'baseline-state'
        $null = Run @('arch', '-Repo', $repo, '-Query', 'Service') $BaselineHelper
        for ($round = 1; $round -le $Rounds; $round++) {
            foreach ($variant in 'baseline-single', 'candidate-single', 'candidate-batch') {
                $entry = if ($variant -eq 'baseline-single') { $BaselineHelper } else { $helper }
                $env:AKZO_AGENT_HOME = if ($variant -eq 'baseline-single') { Join-Path $temp 'baseline-state' } else { $candidateState }
                $clock = [Diagnostics.Stopwatch]::StartNew()
                if ($variant -eq 'candidate-batch') {
                    $value = Run @('arch', '-Repo', $repo, '-Queries', 'Service;Consumer') $entry
                    if ($value.scan.status -ne 'UP_TO_DATE') { throw 'Timed batch cache was not warm.' }
                } else {
                    foreach ($term in 'Service', 'Consumer') {
                        $value = Run @('arch', '-Repo', $repo, '-Query', $term) $entry
                        if ($value.scan.status -ne 'UP_TO_DATE') { throw 'Timed single-query cache was not warm.' }
                    }
                }
                $clock.Stop()
                $measurements.Add([pscustomobject]@{ variant = $variant; round = $round; wallMs = $clock.ElapsedMilliseconds; helperInvocations = $(if ($variant -eq 'candidate-batch') { 1 } else { 2 }) })
            }
        }
    }
    $summaries = @($measurements | Group-Object variant | ForEach-Object {
        $times = @($_.Group.wallMs | Sort-Object)
        [pscustomobject]@{ variant = $_.Name; runs = $times.Count; medianMs = $times[[int][math]::Floor($times.Count / 2)]; p95Ms = $times[[int][math]::Ceiling($times.Count * 0.95) - 1] }
    })
    if ($ResultsFile) {
        [IO.File]::WriteAllText($ResultsFile, ([pscustomobject]@{
            checksPassed = $passes; helperInvocations = $invocations; measurements = $measurements.ToArray(); summaries = $summaries
            p95Method = 'nearest rank; five-run p95 is maximum'; modelCalls = $null; tokens = $null
        } | ConvertTo-Json -Depth 8))
    }
    $summaries | Format-Table -AutoSize
    Write-Output "Architecture retrieval regression: $passes passed, 0 failed."
} finally {
    $env:AKZO_AGENT_HOME = $savedHome
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
