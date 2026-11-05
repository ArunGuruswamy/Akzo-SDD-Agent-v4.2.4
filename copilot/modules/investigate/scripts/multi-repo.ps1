function Get-WorkspaceArchitecture($r, [switch]$RoutingOnly) {
    $files = @(Invoke-Quiet git -C $r.path -c core.quotepath=off ls-files --cached --others --exclude-standard)
    $workspaceFiles = $files
    if ($r.workspace -and $r.workspace -ne $r.path) {
        $prefix = $r.workspace.Substring($r.path.Length + 1).Replace('\', '/') + '/'
        $workspaceFiles = @($files | Where-Object { $_.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) })
    }
    if ($RoutingOnly) {
        $projectPaths = @($workspaceFiles | Where-Object { $_ -match '\.(cs|fs|vb)proj$' -and (Test-Path -LiteralPath (Join-Path $r.path $_) -PathType Leaf) })
        if ($projectPaths.Count) {
            return [pscustomobject]@{ projects = $projectPaths; typescriptWorkspaces = @() }
        }
    }
    $typescript = @(@(foreach ($file in $workspaceFiles | Where-Object { $_ -match '(^|/)(angular|package)\.json$' -and $_ -notmatch '(^|/)(node_modules|dist|\.angular)/' }) {
        $full = Join-Path $r.path $file
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }
        $json = [IO.File]::ReadAllText($full) | ConvertFrom-Json
        if ($file -match 'angular\.json$' -or $json.dependencies.typescript -or $json.devDependencies.typescript) { Split-Path $full }
    }) | Select-Object -Unique)
    if ($RoutingOnly) {
        return [pscustomobject]@{ projects = @(); typescriptWorkspaces = $typescript }
    }
    $projects = if ($workspaceFiles.Count) { Get-ProjectGraph $r.path $workspaceFiles } else { @{} }
    $frameworks = @(@(foreach ($p in $projects.Values) {
        [xml]$xml = [IO.File]::ReadAllText((Join-Path $r.path $p.path))
        foreach ($node in $xml.SelectNodes("//*[local-name()='TargetFramework' or local-name()='TargetFrameworks' or local-name()='TargetFrameworkVersion']")) { $node.InnerText -split ';' }
    }) | Select-Object -Unique)
    [pscustomobject][ordered]@{ root = $r.path; workspace = $r.workspace
        solutions = @($files | Where-Object { $_ -match '\.slnx?$' })
        projects = @($projects.Values | Sort-Object path); frameworks = $frameworks
        typescriptWorkspaces = $typescript; patterns = Get-ArchitectureConventions $r.path $files
        limitation = 'Structural evidence is not a semantic result; run arch. Mixed-language repositories need separate workspace registrations for TypeScript analysis.' }
}

function Get-TypeScriptAnalysis($r, [string]$root) {
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw 'Node.js is unavailable; TypeScript analysis did not run.' }
    $cache = Join-Path (Get-ArchCache $r.id) 'typescript'
    $raw = & node (Join-Path $ModulesDir 'analyzers\typescript\analyze.cjs') scan --root $root --out $cache
    $exit = $LASTEXITCODE
    $scan = ($raw -join "`n") | ConvertFrom-Json
    if ($exit -ne 0) { throw "TypeScript analysis failed: $($scan.error)" }
    [pscustomobject]@{ scan = $scan; index = ([IO.File]::ReadAllText("$cache\index.json") | ConvertFrom-Json) }
}

function Get-TypeScriptAffected($r, $architecture, [string]$against) {
    if ($architecture.typescriptWorkspaces.Count -ne 1) { throw 'Select/register one TypeScript workspace before test selection.' }
    $workspace = $architecture.typescriptWorkspaces[0]
    $prefix = if ($workspace -ne $r.path) { $workspace.Substring($r.path.Length + 1).Replace('\', '/') + '/' } else { '' }
    $all = @(Invoke-Quiet git -C $r.path -c core.quotepath=off ls-files --cached --others --exclude-standard)
    $changed = @(@(Invoke-Quiet git -C $r.path -c core.quotepath=off diff --name-only $against) + @(Invoke-Quiet git -C $r.path ls-files -o --exclude-standard) | Where-Object { $_ } | Sort-Object -Unique)
    $outside = @($changed | Where-Object { $prefix -and -not $_.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) })
    $changed = @($changed | Where-Object { -not $prefix -or $_.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) } | ForEach-Object { $_.Substring($prefix.Length) })
    $packageFile = Join-Path $workspace 'package.json'
    $pkg = if (Test-Path -LiteralPath $packageFile) { [IO.File]::ReadAllText($packageFile) | ConvertFrom-Json } else { $null }
    $tests = @($all | Where-Object { (-not $prefix -or $_.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) -and $_ -match '\.(spec|test)\.[cm]?[jt]sx?$' } | ForEach-Object { $_.Substring($prefix.Length) })
    $focused = @($tests | Where-Object {
        $test = $_; @($changed | Where-Object { $_ -eq $test -or ($test -replace '\.(spec|test)(\.[cm]?[jt]sx?)$', '$2') -eq $_ }).Count
    })
    $wide = @($changed | Where-Object { $_ -match '(^|/)(package(-lock)?|angular|tsconfig[^/]*)\.json$|(^|/)(jest|vite|vitest)[^/]*config' })
    $build = if ($r.cfg.commands.build) { $r.cfg.commands.build } elseif ($pkg.scripts.build) { 'npm run build' } else { '' }
    $testCommand = if ($r.cfg.commands.test) { $r.cfg.commands.test } elseif ($pkg.scripts.test) { 'npm test' } else { '' }
    $selection = if ($focused.Count -and $pkg.scripts.test -match '(^|\s)jest(\s|$)' -and -not $r.cfg.commands.test) {
        "$testCommand -- --runInBand --runTestsByPath " + (@($focused | ForEach-Object { '"' + $_ + '"' }) -join ' ')
    } elseif ($focused.Count -and $pkg.scripts.test -match '^vitest\b' -and -not $r.cfg.commands.test) {
        "$testCommand -- run " + (@($focused | ForEach-Object { '"' + $_ + '"' }) -join ' ')
    } else { '' }
    [pscustomobject]@{ status = $(if (-not $changed.Count) { 'NO_CHANGES' } elseif ($wide.Count) { 'BUILD_WIDE' } else { 'SELECTED' })
        repo = $r.id; language = 'typescript'; workingDirectory = $workspace; changedFiles = $changed; outsideWorkspaceChanges = $outside
        focusedTests = $focused; buildWide = $wide; untestedChanges = @($changed | Where-Object { $_ -match '\.[jt]sx?$' -and $_ -notmatch '\.(spec|test)\.' -and $_ -notin @($focused -replace '\.(spec|test)(\.[jt]sx?)$', '$2') })
        stages = [ordered]@{ A_build = @($build | Where-Object { $_ }); B_focused = @($selection | Where-Object { $_ }); C_regression = @()
            D_full = [ordered]@{ command = $testCommand; workingDirectory = $workspace; when = 'build-wide inputs, demonstrated integration risk or repository policy only' } }
        next = 'Commands are source-derived candidates, not verified results. Use the project runner for affected imports/integration; no known focused selector means NOT VERIFIED, not an automatic full-suite fallback. Separate Sonar/server and template/build verification are required.' }
}

function Invoke-TypeScriptReview($r, $architecture, [string]$against) {
    if ($architecture.typescriptWorkspaces.Count -ne 1) { throw 'Select/register one TypeScript workspace before review.' }
    $workspace = $architecture.typescriptWorkspaces[0]
    $prefix = if ($workspace -ne $r.path) { $workspace.Substring($r.path.Length + 1).Replace('\', '/') + '/' } else { '' }
    $changed = Get-ChangedLines $r.path $against
    $semantic = Get-TypeScriptAnalysis $r $workspace
    $findings = @(foreach ($doc in $semantic.index.documents) {
        foreach ($diag in $doc.diagnostics) {
            [pscustomobject]@{ file = "$prefix$($doc.path)"; line = $diag.line; rule = "TS$($diag.code)"; message = $diag.message
                changed = $changed.ContainsKey("$prefix$($doc.path)"); source = 'TypeScript compiler, not Sonar' }
        }
    })
    $diff = Invoke-Quiet git -C $r.path diff --check $against
    $diffExit = $LASTEXITCODE
    [pscustomobject]@{ status = $(if ($findings.Count -or $diffExit) { 'FINDINGS' } else { 'COMPILER_CLEAN' })
        repo = $r.id; language = 'typescript'; scan = $semantic.scan; findings = $findings; diffCheck = $diff
        verification = 'Compiler diagnostics only; Angular templates, build, tests, lint and Sonar have independent statuses.'
        next = 'Separate existing findings from regressions; verify selected files and affected consumers before handover.' } | ConvertTo-Json -Depth 8 -Compress
}

function Get-WorksetPath {
    if ($Id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') { throw 'Use an explicit task Id; internal maintenance does not require a PBI.' }
    Join-Path $AkzoHome "worksets\$Id.json"
}

function Get-WorksetState {
    $file = Get-WorksetPath
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Workset '$Id' was not confirmed." }
    $state = [IO.File]::ReadAllText($file) | ConvertFrom-Json
    if ($state.schema -ne 1) { throw 'Unsupported workset schema. Reconfirm scope.' }
    $state
}

function Invoke-WorksetCommand {
    if ($Resume) {
        [pscustomobject]@{ status = 'EXPLICIT_RESUME'; workset = (Get-WorksetState)
            next = 'Reconfirm changed roots, branches, HEAD, files or intent. No implicit New Chat approval reuse.' } | ConvertTo-Json -Depth 10 -Compress
        return
    }
    $entries = New-Object Collections.Generic.List[object]
    $targets = @(Get-Registry | ForEach-Object { $_.id })
    $active = Get-GitTop (Get-Location).Path
    if ($active -and -not (Test-Path -LiteralPath (Join-Path $active 'copilot\agents\akzo-master-sdd.agent.md')) -and -not (Get-WorkspaceRepo)) { $targets += (Get-Location).Path }
    foreach ($target in $targets | Select-Object -Unique) {
        try {
            $r = Resolve-Repo $target; $null = Assert-Preflight $r
            $entries.Add([pscustomobject]@{ id = $r.id; status = 'AVAILABLE'; root = $r.path; workspace = $r.workspace
                registered = $r.registered; architecture = Get-WorkspaceArchitecture $r
                evidence = $(if ($Query) { Get-RepoContext $target $Query 'compact' } else { $null })
                relevance = 'CANDIDATE: inspect real workflows/contracts before excluding' })
        } catch {
            $entries.Add([pscustomobject]@{ id = $target; status = 'UNAVAILABLE'; error = $_.Exception.Message; relevance = 'UNKNOWN: cannot silently exclude' })
        }
    }
    [pscustomobject]@{ status = $(if ($entries.Count) { 'SELECTION_REQUIRED' } else { 'NO_APPLICATION_WORKSPACE' })
        repositories = $entries.ToArray(); selected = @(); approval = 'NONE'
        next = 'Classify every candidate. Use native multi-select where supported, numbered choices otherwise. Additional registrations use setup. Confirm repositories, branches and files before writes. Active unregistered applications can be analyzed without altering user configuration.' } | ConvertTo-Json -Depth 10 -Compress
}

function Get-ScopeFile([string]$root, [string]$relative) {
    if (-not $relative -or [IO.Path]::IsPathRooted($relative) -or $relative -match '[:*?]' -or ($relative -split '[\\/]') -contains '.git') { throw "Invalid scoped file '$relative'." }
    $full = [IO.Path]::GetFullPath((Join-Path $root $relative))
    if (-not $full.StartsWith("$root\", [StringComparison]::OrdinalIgnoreCase)) { throw "File escapes selected repository: $relative" }
    $parent = $full
    while ($parent -and $parent.Length -ge $root.Length) {
        if ((Test-Path -LiteralPath $parent) -and ((Get-Item -LiteralPath $parent -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Scoped path traverses a link: $parent" }
        $parent = Split-Path $parent
    }
    $full
}

function Invoke-ScopeCommand {
    if (-not $Confirmed) { throw 'Scope requires explicit user confirmation (-Confirmed) of mode, repositories, branches and files.' }
    $statePath = Get-WorksetPath
    if (Get-GitTop (Split-Path $statePath)) { throw 'Agent state must live outside Git repositories.' }
    $targets = @("$Repo" -split ';' | Where-Object { $_ } | Select-Object -Unique)
    if ($OperatingMode -eq 'maintenance') {
        if (-not $Path) { throw 'Maintenance needs -Path to identified SDD source; applications stay read-only.' }
        $root = "$(Get-GitTop $Path)"
        if (-not $root -or -not (Test-Path -LiteralPath (Join-Path $root 'copilot\agents\akzo-master-sdd.agent.md'))) { throw 'SDD source is missing. Stop maintenance; no application writes permitted.' }
        $targets = @('agent-source')
    } elseif (-not $targets.Count) { throw 'Select at least one repository explicitly.' }
    $repositories = @(foreach ($target in $targets) {
        $r = if ($OperatingMode -eq 'maintenance') { [pscustomobject]@{ id = $target; path = (Resolve-Path $root).Path; workspace = (Resolve-Path $root).Path } } else { Resolve-Repo $target }
        if ($OperatingMode -eq 'application') { $null = Assert-Preflight $r }
        $branch = "$(Invoke-Quiet git -C $r.path symbolic-ref --quiet --short HEAD)".Trim()
        $head = "$(Invoke-Quiet git -C $r.path rev-parse HEAD)".Trim()
        if (-not $branch -or -not $head) { throw "Select a named branch and starting commit for $($r.id) before confirmation." }
        $files = @("$File" -split ';' | Where-Object { $_.StartsWith("$($r.id)=", [StringComparison]::OrdinalIgnoreCase) } | ForEach-Object { $_.Substring($_.IndexOf('=') + 1) } | Select-Object -Unique)
        if (-not $files.Count) { throw "List approved files for $($r.id) with -File 'id=relative-path;id=relative-path'." }
        $snapshots = @(foreach ($f in $files) {
            $full = Get-ScopeFile $r.path $f
            [pscustomobject]@{ file = $f; existed = (Test-Path -LiteralPath $full -PathType Leaf)
                initialHash = $(if (Test-Path -LiteralPath $full -PathType Leaf) { (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash } else { '' }) }
        })
        $dirty = @(git -C $r.path status --porcelain=v1 -uall)
        if ($dirty.Count -and -not $AllowDirty) { throw "Repository $($r.id) has user changes. Preserve them; -AllowDirty requires explicit confirmation." }
        [pscustomobject]@{ id = $r.id; root = $r.path; workspace = $r.workspace; branch = $branch; startHead = $head; files = $snapshots; initialChanges = $dirty }
    })
    $unknown = @("$File" -split ';' | Where-Object { $_ -and ($_ -split '=', 2)[0] -notin @($repositories.id) })
    if ($unknown.Count) { throw "Unselected repository/file mapping: $($unknown -join ';')" }
    if (@($repositories.root | Select-Object -Unique).Count -ne $repositories.Count) { throw 'Select each Git repository once, including its nested workspace files in the same scope.' }
    $state = [pscustomobject]@{ schema = 1; id = $Id; mode = $OperatingMode; confirmedAt = (Get-Date).ToString('o'); requirement = $Query
        repositories = $repositories; decisionScope = 'explicit task only'; automation = 'no automatic commit, merge, push or deploy'
        enforcement = 'Helper checks cannot intercept arbitrary editor writes. Invoke writecheck before every write.' }
    New-Item -ItemType Directory -Path (Split-Path $statePath) -Force | Out-Null
    Protect-Directory (Split-Path $statePath) | Out-Null
    Write-TextAtomic $statePath ($state | ConvertTo-Json -Depth 8)
    [pscustomobject]@{ status = 'SCOPE_CONFIRMED'; workset = $state } | ConvertTo-Json -Depth 10 -Compress
}

function Invoke-WritecheckCommand {
    if (-not $Resume) { throw 'Write checks need explicit task resume (-Resume); New Chat does not inherit approval.' }
    $state = Get-WorksetState
    if ($state.mode -ne $OperatingMode) { throw 'Operating mode differs from the confirmed task.' }
    $r = @($state.repositories | Where-Object { $_.id -eq $Repo }) | Select-Object -First 1
    if (-not $r) { throw "Repository '$Repo' is not selected." }
    if ($state.mode -eq 'application') {
        $current = Resolve-Repo $Repo; $null = Assert-Preflight $current
        if ($current.path -ne $r.root -or $current.workspace -ne $r.workspace) { throw 'Repository registration changed; reconfirm scope.' }
    }
    $branch = "$(Invoke-Quiet git -C $r.root symbolic-ref --quiet --short HEAD)".Trim()
    $head = "$(Invoke-Quiet git -C $r.root rev-parse HEAD)".Trim()
    if ($branch -ne $r.branch -or $head -ne $r.startHead) { throw 'Branch or HEAD changed; reconfirm scope before writing.' }
    if ($File -notin @($r.files.file)) { throw "File '$File' is not in the approved scope." }
    $full = Get-ScopeFile $r.root $File
    [pscustomobject]@{ status = 'WRITE_ALLOWED'; mode = $state.mode; id = $Id; repo = $Repo; file = $full; branch = $branch
        initialChanges = $r.initialChanges; note = 'Preserve unrelated edits. This does not authorize commits or external operations.' } | ConvertTo-Json -Depth 6 -Compress
}
