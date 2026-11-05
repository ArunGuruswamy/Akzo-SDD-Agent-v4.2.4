<#
.SYNOPSIS
  Reproducible helper benchmark: the previous package (e.g. 3.3.0) against this one on the same generated repository.
.DESCRIPTION
  Generates a synthetic layered repository (C# backend + TypeScript UI, one folder per feature), then runs both helpers
  in separate temporary profiles and measures wall-clock time (median of -Runs), output size, cache behaviour, whether an
  uncommitted edit is noticed, and whether retrieval names the right file. Finally installs the previous package, creates
  a task, upgrades to this package, and checks the task still works.
  What this cannot measure: model interactions, tokens, files read by the agent, and manual interactions in Copilot.
  Those need real IDE runs (benchmark\results-template.csv) and are reported as NOT VERIFIED.
  Never touches the real profile: everything runs under a temporary folder that is removed at the end.
.EXAMPLE
  .\scripts\benchmark.ps1 -BaselineZip ..\Akzo-Agent-3.3.0.zip
  .\scripts\benchmark.ps1 -BaselineDir C:\temp\Akzo-Agent-3.3.0 -Features 80 -Runs 7
.NOTES
  Akzo SDD Agent — Developed and maintained by Arun RG
#>
param(
    [string]$BaselineZip = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Akzo-Agent-3.3.0.zip'),
    [string]$BaselineDir,
    [int]$Features = 60,
    [int]$Runs = 5,
    [string]$Out,   # default: benchmark\results-<version>.md
    [switch]$KeepTemp
)
$ErrorActionPreference = 'Stop'
$Source = Split-Path -Parent $PSScriptRoot
$tmp = Join-Path $env:TEMP "akzo-bench-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
New-Item -ItemType Directory -Force $tmp | Out-Null

function Invoke-Helper([string]$helper, [string]$homeDir, [string[]]$arguments) {
    $env:AKZO_AGENT_HOME = $homeDir
    $ErrorActionPreference = 'Continue'
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $o = & powershell.exe -NoProfile -File $helper @arguments 2>$null
    $sw.Stop()
    $text = ($o | Out-String).Trim()
    [pscustomobject]@{ ms = $sw.ElapsedMilliseconds; chars = $text.Length; text = $text; code = $LASTEXITCODE }
}
function Get-Median([double[]]$v) { $s = @($v | Sort-Object); if (-not $s.Count) { return $null }; if ($s.Count % 2) { $s[[int][math]::Floor($s.Count / 2)] } else { ($s[$s.Count / 2 - 1] + $s[$s.Count / 2]) / 2 } }

try {
    # ---- previous package
    if (-not $BaselineDir) {
        if (-not (Test-Path $BaselineZip)) { throw "Baseline package not found: $BaselineZip (give -BaselineZip or -BaselineDir)." }
        $BaselineDir = Join-Path $tmp 'baseline'
        Expand-Archive $BaselineZip -DestinationPath $BaselineDir
    }
    $baseVersion = (Get-Content (Join-Path $BaselineDir 'VERSION') -TotalCount 1).Trim()
    $newVersion = (Get-Content (Join-Path $Source 'VERSION') -TotalCount 1).Trim()
    if (-not $Out) { $Out = Join-Path $Source "benchmark\results-$newVersion.md" }
    $helpers = [ordered]@{ $baseVersion = (Join-Path $BaselineDir 'copilot\modules\investigate\scripts\akzo.ps1'); $newVersion = (Join-Path $Source 'copilot\modules\investigate\scripts\akzo.ps1') }

    # ---- synthetic repository: <Features> features x (command, handler, validator, service, repository, model, controller, test, UI component, UI service, UI spec)
    $repo = Join-Path $tmp 'repo'
    $nouns = 'Order', 'Invoice', 'Customer', 'Product', 'Shipment', 'Payment', 'Refund', 'Supplier', 'Warehouse', 'Stock', 'Contract', 'Quote'
    $verbs = 'Create', 'Update', 'Cancel', 'Approve', 'Export'
    $n = 0
    foreach ($noun in $nouns) {
        foreach ($verb in $verbs) {
            if ($n -ge $Features) { break }
            $n++; $f = "$verb$noun"; $d = "$repo\src\App\$noun\$f"; $ui = "$repo\ui\src\app\$($noun.ToLower())\$($verb.ToLower())-$($noun.ToLower())"
            New-Item -ItemType Directory -Force $d, "$repo\tests\App.Tests\$noun", $ui | Out-Null
            $w = { param($p, $t) [IO.File]::WriteAllText($p, $t) }
            & $w "$d\${f}Command.cs" "namespace App.$noun;`npublic sealed record ${f}Command(Guid Id, decimal Amount, string Reference) : IRequest<Result>;`n"
            & $w "$d\${f}Handler.cs" "namespace App.$noun;`npublic sealed class ${f}Handler : IRequestHandler<${f}Command, Result>`n{`n    private readonly I${noun}Repository _repository;`n    public ${f}Handler(I${noun}Repository repository) { _repository = repository; }`n    public async Task<Result> Handle(${f}Command request, CancellationToken cancellationToken)`n    {`n        var entity = await _repository.GetAsync(request.Id, cancellationToken);`n        return Result.Ok();`n    }`n}`n"
            & $w "$d\${f}Validator.cs" "namespace App.$noun;`npublic sealed class ${f}Validator : AbstractValidator<${f}Command>`n{`n    public ${f}Validator()`n    {`n        RuleFor(x => x.Amount).GreaterThan(0);`n        RuleFor(x => x.Reference).NotEmpty().MaximumLength(40);`n    }`n}`n"
            & $w "$d\${f}Service.cs" "namespace App.$noun;`npublic class ${f}Service`n{`n    public decimal CalculateTotal(decimal amount, decimal rate) => amount * rate;`n    public bool IsAllowed(string reference) => reference.Length > 0;`n}`n"
            & $w "$d\${noun}${verb}Repository.cs" "namespace App.$noun;`npublic class ${noun}${verb}Repository`n{`n    public Task<$noun> GetAsync(Guid id, CancellationToken ct) => Task.FromResult(new $noun());`n}`n"
            & $w "$d\${f}Dto.cs" "namespace App.$noun;`npublic sealed record ${f}Dto(Guid Id, decimal Amount);`n"
            & $w "$d\${f}Controller.cs" "namespace App.$noun;`n[Route(""api/$($noun.ToLower())"")]`npublic sealed class ${f}Controller : ControllerBase`n{`n    [HttpPost(""$($verb.ToLower())"")]`n    public async Task<IActionResult> $verb(${f}Command command) => Ok(await _mediator.Send(command));`n}`n"
            & $w "$repo\tests\App.Tests\$noun\${f}ValidatorTests.cs" "public class ${f}ValidatorTests`n{`n    [Fact]`n    public void Rejects_zero_amount() { }`n    [Fact]`n    public void Accepts_valid_command() { }`n}`n"
            & $w "$ui\$($verb.ToLower())-$($noun.ToLower()).component.ts" "@Component({ selector: 'app-$($verb.ToLower())-$($noun.ToLower())' })`nexport class ${f}Component implements OnInit {`n  ngOnInit(): void {`n  }`n  submit(): void {`n  }`n}`n"
            & $w "$ui\$($verb.ToLower())-$($noun.ToLower()).service.ts" "@Injectable({ providedIn: 'root' })`nexport class ${f}Service {`n  send(command: ${f}Command): Observable<Result> {`n    return this.http.post<Result>('/api/$($noun.ToLower())/$($verb.ToLower())', command);`n  }`n}`n"
            & $w "$ui\$($verb.ToLower())-$($noun.ToLower()).service.spec.ts" "describe('${f}Service', () => { it('posts', () => {}); });`n"
        }
    }
    [IO.File]::WriteAllText("$repo\App.sln", '')
    [IO.File]::WriteAllText("$repo\src\App\App.csproj", '<Project Sdk="Microsoft.NET.Sdk.Web"><ItemGroup><PackageReference Include="MediatR" Version="12.0.0" /><PackageReference Include="FluentValidation" Version="11.0.0" /></ItemGroup></Project>')
    [IO.File]::WriteAllText("$repo\ui\package.json", '{ "dependencies": { "@angular/core": "^17.0.0" } }')
    & git -C $repo init -q; & git -C $repo config user.email b@b; & git -C $repo config user.name b; & git -C $repo config core.autocrlf false
    & git -C $repo add -A; & git -C $repo commit -qm init
    $fileCount = @(& git -C $repo ls-files).Count
    $target = 'src/App/Invoice/ApproveInvoice/ApproveInvoiceValidator.cs'
    $query = 'approve invoice amount validation'

    $rows = [ordered]@{}
    foreach ($v in $helpers.Keys) {
        $helper = $helpers[$v]
        $homeDir = Join-Path $tmp "home-$v"
        New-Item -ItemType Directory -Force "$homeDir\tasks\bench\PBI-1", "$homeDir\tasks\bench\PBI-2" | Out-Null
        [pscustomobject]@{ version = 1; tasksDir = ''; repos = @([pscustomobject]@{ id = 'bench'; path = $repo; purpose = 'benchmark' }) } | ConvertTo-Json -Depth 4 | Set-Content "$homeDir\repos.json"
        foreach ($p in 'PBI-1', 'PBI-2') { [IO.File]::WriteAllText("$homeDir\tasks\bench\$p\refined-pbi.md", "# $p Approve invoice`nAC1: an invoice with amount 0 is rejected when it is approved.`n") }
        # 3.4.0 and later fail closed until the repository is authorized (G8 preflight); the previous version has no such step.
        if ($v -eq $newVersion) { $null = Invoke-Helper $helper $homeDir @('authorize', '-Repo', 'bench', '-Reference', 'benchmark fixture', '-Classification', 'internal') }
        $cold = Invoke-Helper $helper $homeDir @('task', '-Id', 'PBI-1', '-Repo', 'bench')
        $warm = @(1..$Runs | ForEach-Object { Invoke-Helper $helper $homeDir @('task', '-Id', 'PBI-1', '-Repo', 'bench') })
        $second = Invoke-Helper $helper $homeDir @('task', '-Id', 'PBI-2', '-Repo', 'bench')
        # An uncommitted new file: is it in the component index the agent searches?
        [IO.File]::WriteAllText("$repo\src\App\Invoice\ApproveInvoice\ApproveInvoiceLimitValidator.cs", "public sealed class ApproveInvoiceLimitValidator { }`n")
        $edit = Invoke-Helper $helper $homeDir @('task', '-Id', 'PBI-1', '-Repo', 'bench')
        $index = Join-Path $homeDir 'maps\bench\component-index.tsv'
        $seesEdit = [bool](Select-String -LiteralPath $index -SimpleMatch 'ApproveInvoiceLimitValidator.cs' -Quiet)
        Remove-Item "$repo\src\App\Invoice\ApproveInvoice\ApproveInvoiceLimitValidator.cs"
        $after = Invoke-Helper $helper $homeDir @('task', '-Id', 'PBI-1', '-Repo', 'bench')   # back to the committed state
        # Selection step for one requirement. Previous version: the index lines a term search returns (what the agent reads
        # next). This version: the context output. Both measured; correctness = the expected validator is first / present.
        $terms = 'approve', 'invoice', 'validator'
        $idxHits = @(Get-Content -LiteralPath $index | Where-Object { $l = $_.ToLowerInvariant(); @($terms | Where-Object { $l.Contains($_) }).Count -ge 2 })
        $ctx = $null; $ctxTop = ''; $ctxOk = $null
        if ($v -eq $newVersion) {
            $ctxRuns = @(1..$Runs | ForEach-Object { Invoke-Helper $helper $homeDir @('context', '-Repo', 'bench', '-Query', $query) })
            $ctx = $ctxRuns[-1]; $cj = $ctx.text | ConvertFrom-Json; $ctxTop = $cj.files[0].path; $ctxOk = $ctxTop -eq $target
            $ctx | Add-Member ms (Get-Median @($ctxRuns | ForEach-Object { $_.ms })) -Force
        }
        $hitRate = $null
        $log = Join-Path $homeDir 'maps\bench\memory-log.tsv'
        if (Test-Path $log) { $ev = @(Get-Content $log | ForEach-Object { ($_ -split "`t")[1] } | Where-Object { $_ -in 'hit', 'refresh', 'rebuild' }); if ($ev.Count) { $hitRate = [math]::Round(100 * @($ev | Where-Object { $_ -eq 'hit' }).Count / $ev.Count, 1) } }
        $rows[$v] = [pscustomobject][ordered]@{
            coldMs = $cold.ms; warmMs = (Get-Median @($warm | ForEach-Object { $_.ms })); secondPbiMs = $second.ms; editMs = $edit.ms; afterMs = $after.ms
            taskChars = $warm[-1].chars; seesUncommitted = $seesEdit
            idxHitLines = $idxHits.Count; idxHitChars = ($idxHits -join "`n").Length; idxHasTarget = [bool]($idxHits -match [regex]::Escape($target))
            ctxMs = $(if ($ctx) { $ctx.ms } else { $null }); ctxChars = $(if ($ctx) { $ctx.chars } else { $null }); ctxTop = $ctxTop; ctxOk = $ctxOk
            hitRate = $hitRate; ok = ($cold.code -eq 0 -and $second.code -eq 0)
        }
    }

    # ---- upgrade compatibility: install the previous package, create a task, upgrade, use the task again
    $uh = Join-Path $tmp 'upgrade-home'; New-Item -ItemType Directory -Force $uh | Out-Null
    $ErrorActionPreference = 'Continue'
    $i1 = & powershell.exe -NoProfile -File (Join-Path $BaselineDir 'scripts\install.ps1') -HomeRoot $uh -AddRepo $repo 2>&1 | Out-String
    $old = Join-Path $uh '.akzo-agent\modules\investigate\scripts\akzo.ps1'
    New-Item -ItemType Directory -Force "$uh\.akzo-agent\tasks\repo\PBI-9" | Out-Null
    [IO.File]::WriteAllText("$uh\.akzo-agent\tasks\repo\PBI-9\refined-pbi.md", "# PBI-9 Export quotes`nAC1: quotes export as CSV.`n")
    $before = (Invoke-Helper $old "$uh\.akzo-agent" @('task', '-Id', 'PBI-9', '-Repo', 'repo')).text | ConvertFrom-Json
    $i2 = & powershell.exe -NoProfile -File (Join-Path $Source 'scripts\install.ps1') -HomeRoot $uh 2>&1 | Out-String
    $verify = & powershell.exe -NoProfile -File (Join-Path $Source 'scripts\install.ps1') -HomeRoot $uh -Verify 2>&1 | Out-String
    # Same installed path, now the new helper. By design the repository must be authorized once before it is processed again.
    $blockedUp = (Invoke-Helper $old "$uh\.akzo-agent" @('task', '-Id', 'PBI-9', '-Repo', 'repo')).text | ConvertFrom-Json
    $null = Invoke-Helper $old "$uh\.akzo-agent" @('authorize', '-Repo', 'repo', '-Reference', 'benchmark fixture', '-Classification', 'internal')
    $afterUp = (Invoke-Helper $old "$uh\.akzo-agent" @('task', '-Id', 'PBI-9', '-Repo', 'repo')).text | ConvertFrom-Json
    $ErrorActionPreference = 'Stop'
    $upgradeOk = $before.status -eq 'READY' -and $blockedUp.status -eq 'NEEDS_AUTHORIZATION' -and $afterUp.status -eq 'READY' -and $afterUp.spec -eq $before.spec -and $verify -match 'VERIFY OK' -and $afterUp.agentVersion -eq $newVersion -and $afterUp.architecture.memory.event -eq 'rebuild'

    # ---- report
    $b = $rows[$baseVersion]; $c = $rows[$newVersion]
    $env = "Windows PowerShell $($PSVersionTable.PSVersion), $((& git --version) -replace 'git version ', 'Git '), $((Get-CimInstance Win32_Processor | Select-Object -First 1).Name.Trim()), $([math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)) GB RAM"
    $pct = { param($a, $z) if ($a -and $null -ne $z) { "$([math]::Round(100 * ($z - $a) / $a))%" } else { 'n/a' } }
    $md = @"
# Helper benchmark: $baseVersion vs $newVersion

Akzo SDD Agent — Developed and maintained by Arun RG

- Date: $((Get-Date).ToString('yyyy-MM-dd HH:mm')) · Command: ``scripts\benchmark.ps1 -Features $Features -Runs $Runs``
- Environment: $env
- Repository: generated, $fileCount tracked files ($Features features: command, handler, validator, service, repository, DTO, controller, test, UI component, UI service, UI spec), one commit
- Times are wall clock per helper call including Windows PowerShell start-up (median of $Runs where noted). Characters are the size of the helper's output, which is what enters the model's context.

| Metric | $baseVersion | $newVersion | Change | Kind |
|---|---|---|---|---|
| First discovery (cold ``task``, builds the index) | $($b.coldMs) ms | $($c.coldMs) ms | $(& $pct $b.coldMs $c.coldMs) | measured |
| Same task again (warm, median) | $($b.warmMs) ms | $($c.warmMs) ms | $(& $pct $b.warmMs $c.warmMs) | measured |
| Second PBI start-up (index exists) | $($b.secondPbiMs) ms | $($c.secondPbiMs) ms | $(& $pct $b.secondPbiMs $c.secondPbiMs) | measured |
| Start-up after an uncommitted new file | $($b.editMs) ms | $($c.editMs) ms | $(& $pct $b.editMs $c.editMs) | measured |
| Uncommitted new file appears in the index | $($b.seesUncommitted) | $($c.seesUncommitted) | | measured |
| ``task`` output size (warm) | $($b.taskChars) chars | $($c.taskChars) chars | $(& $pct $b.taskChars $c.taskChars) | measured |
| Selection for one requirement: index term search ("$($terms -join '", "')", 2 of 3) | $($b.idxHitLines) lines, $($b.idxHitChars) chars, target listed: $($b.idxHasTarget) | $($c.idxHitLines) lines, $($c.idxHitChars) chars | | measured |
| Selection for one requirement: ``context -Query "$query"`` | not available | $($c.ctxChars) chars, $($c.ctxMs) ms (median), first file: ``$($c.ctxTop)`` (expected: $($c.ctxOk)) | | measured |
| Memory hit rate over this run's synchronizations | not recorded | $($c.hitRate)% | | measured |
| Upgrade $baseVersion -> $newVersion keeps an existing task working (the repository needs a one-time ``authorize`` first: blocked until then, then the same spec path and task) | | $(if ($upgradeOk) { 'PASS' } else { 'FAIL' }) | | measured |
| Model interactions, tokens, files read, manual interactions in Copilot | | | | NOT VERIFIED (needs IDE runs; see benchmark/results-template.csv) |

Notes
- The index term search row shows what the agent had to read next in $baseVersion (matching index lines, then whole files). $newVersion returns ranked files with symbol line numbers and linked tests in one call; files are still read at the cited lines (retrieval level L3), so this row is not a claim of end-to-end token savings.
- $newVersion fingerprints every file by content on each call. Its warm time is the cost of that check; the benefit is that edits, untracked files, deletions, and renames are seen without a commit (row 5), and only changed files are reparsed.
"@
    New-Item -ItemType Directory -Force (Split-Path $Out) | Out-Null
    [IO.File]::WriteAllText($Out, $md, (New-Object Text.UTF8Encoding($false)))
    Write-Output $md
    if (-not $upgradeOk) { Write-Output "Upgrade check details:`n$i1`n$i2`n$verify"; exit 1 }
} finally {
    Remove-Item Env:AKZO_AGENT_HOME -ErrorAction SilentlyContinue
    if (-not $KeepTemp) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue } else { Write-Output "Temp kept: $tmp" }
}
