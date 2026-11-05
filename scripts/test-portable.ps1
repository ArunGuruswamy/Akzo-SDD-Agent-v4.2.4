param()
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$helper = Join-Path $root 'copilot\modules\investigate\scripts\akzo.ps1'
$temp = Join-Path ([IO.Path]::GetTempPath()) "sdd-portable-$([guid]::NewGuid().ToString('N'))"
$savedHome = $env:AKZO_AGENT_HOME
$passes = 0
function Assert($value, $message) { if (-not $value) { throw $message }; $script:passes++; Write-Output "PASS $message" }
function Run([string[]]$arguments, [switch]$Failure) {
    $ErrorActionPreference = 'Continue'
    $output = & powershell -NoProfile -File $helper @arguments 2>&1 | Out-String
    $exit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($Failure) { Assert ($exit -ne 0) "blocked: $($arguments[0]) $($arguments -join ' ')"; return }
    if ($exit) { throw $output }
    $output | ConvertFrom-Json
}
function Put($file, $text) { New-Item -ItemType Directory -Path (Split-Path $file) -Force | Out-Null; [IO.File]::WriteAllText($file, $text) }
try {
    $env:AKZO_AGENT_HOME = Join-Path $temp 'personal-state'
    New-Item -ItemType Directory -Path $env:AKZO_AGENT_HOME -Force | Out-Null
    $empty = Run @('workset')
    Assert ($empty.repositories.Count -eq 0 -and $empty.approval -eq 'NONE') 'no registrations: no application assumed in maintenance source'
    $repos = @(foreach ($name in 'warehouse', 'archive', 'portal') {
        $folder = Join-Path $temp "different-layout\$name"
        Put "$folder\feature.cjs" 'module.exports = { value: 1 };'
        Put "$folder\feature.test.cjs" "require('node:assert/strict').equal(require('./feature.cjs').value, 1);"
        Put "$folder\package.json" '{"scripts":{"test":"node feature.test.cjs"}}'
        if ($name -eq 'portal') { Put "$folder\client\angular.json" '{"version":1,"projects":{"app":{"root":"","projectType":"application"}}}'; Put "$folder\client\package.json" '{"devDependencies":{"typescript":"*"}}' }
        & git -C $folder init --initial-branch "feature/$name" --quiet
        & git -C $folder add --all
        & git -C $folder -c user.name=Fixture -c user.email=fixture@example.invalid commit -m fixture --quiet
        if ($LASTEXITCODE) { throw 'Fixture Git initialization failed.' }
        [pscustomobject]@{ id = $name; path = $(if ($name -eq 'portal') { "$folder\client" } else { $folder }); gitRoot = $folder }
    })
    Put "$env:AKZO_AGENT_HOME\repos.json" ([pscustomobject]@{ version = 1; repos = @($repos | Select-Object id, path) } | ConvertTo-Json -Depth 4)
    $registryHash = (Get-FileHash "$env:AKZO_AGENT_HOME\repos.json").Hash
    $all = Run @('workset')
    Assert ($all.repositories.Count -eq 3 -and @($all.repositories | Where-Object status -ne AVAILABLE).Count -eq 0) 'all renamed repositories are discovered'
    $ui = @($all.repositories | Where-Object id -eq portal)[0]
    Assert ($ui.root -eq $repos[2].gitRoot -and $ui.workspace -eq $repos[2].path -and $ui.architecture.typescriptWorkspaces.Count -eq 1) 'nested Angular workspace retains independent Git boundary'
    Push-Location $repos[0].gitRoot
    try {
        $env:AKZO_AGENT_HOME = Join-Path $temp 'empty-state'
        $active = Run @('workset')
        Assert ($active.repositories.Count -eq 1 -and -not $active.repositories[0].registered) 'active application discovery without any registry'
    } finally { Pop-Location; $env:AKZO_AGENT_HOME = Join-Path $temp 'personal-state' }
    $savedRegistry = [IO.File]::ReadAllText("$env:AKZO_AGENT_HOME\repos.json")
    $nested = @(
        [pscustomobject]@{ id='first-workspace'; path="$($repos[0].gitRoot)\client" },
        [pscustomobject]@{ id='longer-sibling'; path="$($repos[0].gitRoot)\client-other" }
    )
    foreach ($entry in $nested) { New-Item -ItemType Directory -Path $entry.path -Force | Out-Null }
    Put "$env:AKZO_AGENT_HOME\repos.json" ([pscustomobject]@{ version=1; repos=$nested } | ConvertTo-Json -Depth 4)
    try {
        foreach ($entry in $nested) {
            Push-Location $entry.path
            try {
                $current = Run @('state')
                Assert ($current.id -eq $entry.id -and $current.registered) "active nested workspace resolves $($entry.id), not its sibling"
            } finally { Pop-Location }
        }
        Push-Location $repos[0].gitRoot
        try {
            $current = Run @('state')
            Assert (-not $current.registered) 'Git root does not silently select a registered nested workspace'
        } finally { Pop-Location }
    } finally { Put "$env:AKZO_AGENT_HOME\repos.json" $savedRegistry }
    for ($mask = 1; $mask -le 7; $mask++) {
        $selected = @(for ($i = 0; $i -lt 3; $i++) { if ($mask -band (1 -shl $i)) { $repos[$i] } })
        $id = "combination-$mask"
        $targets = $selected.id -join ';'
        $files = @($selected | ForEach-Object { "$($_.id)=feature.cjs"; "$($_.id)=feature.test.cjs" }) -join ';'
        $confirmed = Run @('scope', '-Id', $id, '-Repo', $targets, '-File', $files, '-Confirmed', '-AllowDirty')
        Assert ($confirmed.workset.repositories.Count -eq $selected.Count) "combination $mask selects exact scope"
        foreach ($r in $repos) {
            if ($r.id -in $selected.id) {
                $check = Run @('writecheck', '-Id', $id, '-Repo', $r.id, '-File', 'feature.cjs', '-Resume')
                Assert ($check.status -eq 'WRITE_ALLOWED') "combination $mask authorizes selected repository $($r.id)"
                Put "$($r.gitRoot)\feature.cjs" 'module.exports = { value: 2 };'
                $null = Run @('writecheck', '-Id', $id, '-Repo', $r.id, '-File', 'feature.test.cjs', '-Resume')
                Put "$($r.gitRoot)\feature.test.cjs" "require('node:assert/strict').equal(require('./feature.cjs').value, 2);"
                & node "$($r.gitRoot)\feature.test.cjs"
                Assert ($LASTEXITCODE -eq 0) "combination $mask focused executable validation $($r.id)"
            } else {
                Run @('writecheck', '-Id', $id, '-Repo', $r.id, '-File', 'feature.cjs', '-Resume') -Failure
                Assert (-not @(& git -C $r.gitRoot status --porcelain).Count) "combination $mask leaves unselected $($r.id) untouched"
            }
        }
        $again = Run @('workset', '-Id', $id)
        Assert ($again.approval -eq 'NONE' -and $again.selected.Count -eq 0) "combination $mask New Chat defaults to no approval"
        foreach ($r in $selected) { Put "$($r.gitRoot)\feature.cjs" 'module.exports = { value: 1 };'; Put "$($r.gitRoot)\feature.test.cjs" "require('node:assert/strict').equal(require('./feature.cjs').value, 1);" }
    }
    Run @('writecheck', '-Id', 'combination-7', '-Repo', 'warehouse', '-File', 'feature.cjs') -Failure
    Run @('writecheck', '-Id', 'combination-7', '-Repo', 'warehouse', '-File', '..\escape.cjs', '-Resume') -Failure
    & git -C $repos[0].gitRoot switch -c changed --quiet
    Run @('writecheck', '-Id', 'combination-7', '-Repo', 'warehouse', '-File', 'feature.cjs', '-Resume') -Failure
    Run @('scope', '-Id', 'maintenance', '-OperatingMode', 'maintenance', '-Path', $repos[0].gitRoot, '-File', 'agent-source=feature.cjs', '-Confirmed') -Failure
    # Concurrent chats/processes writing repository memory: every fact survives, no shared temporary file, readable JSON.
    $writers = @(foreach ($n in 1..6) {
        Start-Process powershell.exe -ArgumentList @('-NoProfile', '-File', "`"$helper`"", 'remember', '-Repo', 'warehouse', '-Type', 'component', '-Text', "`"Concurrent fixture fact $n states that feature.cjs exports a numeric value property`"", '-Evidence', 'feature.cjs:1') -WindowStyle Hidden -PassThru
    })
    foreach ($w in $writers) { if (-not $w.WaitForExit(120000)) { $w.Kill(); throw 'A concurrent remember did not finish.' } }
    $memory = Join-Path $env:AKZO_AGENT_HOME 'maps\warehouse'
    $stored = @(([IO.File]::ReadAllText("$memory\facts.json") | ConvertFrom-Json).facts | Where-Object { $_.text -like 'Concurrent fixture fact *' })
    Assert (@($writers | Where-Object ExitCode -ne 0).Count -eq 0 -and $stored.Count -eq 6 -and -not @(Get-ChildItem -LiteralPath $memory -Filter '*.tmp').Count) 'six concurrent remember processes keep all six facts with no lost update or leftover temporary file'
    Assert ((Get-FileHash "$env:AKZO_AGENT_HOME\repos.json").Hash -eq $registryHash) 'runtime preserves personal registrations'
    Write-Output "Portable regression: $passes passed, 0 failed. Fixture validation is not real application/Sonar integration."
} finally {
    $env:AKZO_AGENT_HOME = $savedHome
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
