<#
.SYNOPSIS
  Interleaved timing of 'task' for up to three helper versions on one repository.
.DESCRIPTION
  Machine load changes from minute to minute, so timings of different versions taken one after another are not
  comparable. This script runs every version once per round (the order rotates) against the same repository and
  reports the median of each, and each version's change against the baseline measured in the same rounds.
  Cold = the repository's memory removed first; warm = the call right after. It measures the helper only: model
  interactions, tokens, and files read by the agent need real IDE runs (benchmark\results-template.csv).
  Use any repository, for example the one scripts\benchmark.ps1 generates (-KeepTemp keeps it).
  Everything runs in a temporary work folder; the repository is only read.
.EXAMPLE
  .\scripts\ab-bench.ps1 -Repo C:\src\my-repo -Work $env:TEMP\ab -Baseline C:\old\3.3.0\copilot\modules\investigate\scripts\akzo.ps1 -Previous C:\old\3.4.0\...\akzo.ps1
.NOTES
  Akzo SDD Agent — Developed and maintained by Arun RG
#>
param(
    [Parameter(Mandatory)][string]$Repo,
    [Parameter(Mandatory)][string]$Work,
    [Parameter(Mandatory)][string]$Baseline,   # akzo.ps1 of the version to compare against
    [string]$Previous,                         # optional second older akzo.ps1
    [string]$Current,                         # default: this package's helper
    [int]$Rounds = 6
)
$ErrorActionPreference = 'Continue'
# not a parameter default: $PSScriptRoot is empty there in Windows PowerShell 5.1 when a parameter is mandatory
if (-not $Current) { $Current = Join-Path (Split-Path -Parent $PSScriptRoot) 'copilot\modules\investigate\scripts\akzo.ps1' }
$helpers = [ordered]@{ baseline = $Baseline }
if ($Previous) { $helpers['previous'] = $Previous }
$helpers['current'] = $Current
foreach ($v in $helpers.Keys) { if (-not (Test-Path $helpers[$v])) { throw "helper for '$v' not found: $($helpers[$v])" } }
if (-not (Test-Path (Join-Path $Repo '.git'))) { throw "$Repo is not a Git repository." }
if (Test-Path $Work) { Remove-Item $Work -Recurse -Force }
$homes = @{}
foreach ($v in $helpers.Keys) {
    $h = Join-Path $Work "home-$v"; $homes[$v] = $h
    New-Item -ItemType Directory -Force "$h\tasks\bench\PBI-1" | Out-Null
    [pscustomobject]@{ version = 1; tasksDir = ''; repos = @([pscustomobject]@{ id = 'bench'; path = $Repo; purpose = 'ab' }) } | ConvertTo-Json -Depth 4 | Set-Content "$h\repos.json"
    [IO.File]::WriteAllText("$h\tasks\bench\PBI-1\refined-pbi.md", "# PBI-1 Timing`nAC1: timing only.`n")
    # 3.4.0 and later need the repository authorized once; earlier versions have no such command
    if (Select-String -Path $helpers[$v] -SimpleMatch "'authorize'" -Quiet) {
        $env:AKZO_AGENT_HOME = $h
        $null = & powershell.exe -NoProfile -File $helpers[$v] authorize -Repo bench -Reference 'timing run (no real approval)' -Classification internal 2>&1
    }
}
function Call($v) {
    $env:AKZO_AGENT_HOME = $homes[$v]
    $sw = [Diagnostics.Stopwatch]::StartNew(); $null = & powershell.exe -NoProfile -File $helpers[$v] task -Id PBI-1 -Repo bench 2>&1; $sw.ElapsedMilliseconds
}
$cold = @{}; $warm = @{}; foreach ($v in $helpers.Keys) { $cold[$v] = @(); $warm[$v] = @() }
foreach ($v in $helpers.Keys) { $null = Call $v }   # first-ever calls are discarded (disk cache, JIT)
for ($r = 0; $r -lt $Rounds; $r++) {
    $order = @($helpers.Keys); for ($k = 0; $k -lt ($r % $order.Count); $k++) { $order = @($order[1..($order.Count - 1)] + $order[0]) }
    foreach ($v in $order) {
        Remove-Item (Join-Path $homes[$v] 'maps') -Recurse -Force -ErrorAction SilentlyContinue
        $cold[$v] += Call $v
        $warm[$v] += Call $v
    }
}
Remove-Item Env:AKZO_AGENT_HOME -ErrorAction SilentlyContinue
function Med($a) { $s = @($a | Sort-Object); if ($s.Count % 2) { $s[[int][math]::Floor($s.Count / 2)] } else { [int](($s[$s.Count / 2 - 1] + $s[$s.Count / 2]) / 2) } }
$repoFiles = @(& git -C $Repo ls-files).Count
"Interleaved timing, $Rounds rounds, $repoFiles tracked files, Windows PowerShell $($PSVersionTable.PSVersion), $((& git --version) -join '')"
foreach ($v in $helpers.Keys) {
    "{0,-9} cold median {1,5} ms (min {2}, max {3})   warm median {4,5} ms (min {5}, max {6})" -f $v, (Med $cold[$v]), ($cold[$v] | Measure-Object -Minimum).Minimum, ($cold[$v] | Measure-Object -Maximum).Maximum, (Med $warm[$v]), ($warm[$v] | Measure-Object -Minimum).Minimum, ($warm[$v] | Measure-Object -Maximum).Maximum
}
$b = Med $cold['baseline']; $w = Med $warm['baseline']
foreach ($v in @($helpers.Keys | Where-Object { $_ -ne 'baseline' })) {
    "{0,-9} vs baseline (same rounds): cold {1:+0;-0}%  warm {2:+0;-0}%" -f $v, [math]::Round(100 * ((Med $cold[$v]) - $b) / $b), [math]::Round(100 * ((Med $warm[$v]) - $w) / $w)
}
