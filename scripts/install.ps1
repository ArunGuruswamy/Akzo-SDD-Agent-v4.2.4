<#
.SYNOPSIS
  Installs, upgrades, repairs, verifies, or uninstalls the Akzo Master SDD GitHub Copilot agent at user level.
  Install-MasterAgent.cmd is the one-click front end for this script.

.DESCRIPTION
  Copies (no downloads, no admin rights) from this repository:
    copilot\agents\akzo-master-sdd.agent.md -> <HomeRoot>\.copilot\agents\    (VS Code)
                                            -> <HomeRoot>\.github\agents\     (Visual Studio 2026 default user location)
    copilot\modules\                        -> <HomeRoot>\.akzo-agent\modules\ (helper script and spec/plan templates)
  With -ConfigureVSCode it also adds a marked block to VS Code user settings (backed up first; removed by -Uninstall).
  It creates <HomeRoot>\.akzo-agent\repos.json from config\repos.example.json if missing, plus the tasks folder
  (repos.json 'tasksDir', default <HomeRoot>\.akzo-agent\tasks) and the inbox. repos.json is validated and only
  changed by -AddRepo (backed up first).
  Upgrade: files from earlier versions that are no longer shipped are backed up and removed (manifest), and
  earlier Akzo agent files found in agent folders without a manifest entry (e.g. akzo-sdd) are backed up and removed.
  If a write fails, every file changed by this run is restored from its backup (rollback).
  Isolation: the agent file is the only file placed where Copilot discovers customizations. Workflow modules
  are deliberately NOT installed as skills, because both IDEs offer discovered skills to every agent.
  -Verify also reports Akzo text in places Copilot loads for every agent (shared instruction/prompt folders,
  VS Code Copilot memory); -CleanMemory backs up and removes such VS Code memory files.
  Every written file is recorded with its SHA-256 in <HomeRoot>\.akzo-agent\install-manifest.json.
  Any existing file that would be replaced or removed is first copied to <HomeRoot>\.akzo-agent\backups\<timestamp>\.
  Target repositories are never written; their HEAD and git status are compared before and after.
  Re-running is safe (repair): unchanged files are skipped, missing or modified files are restored.

.EXAMPLE
  .\scripts\install.ps1 -DryRun                    # preview
  .\scripts\install.ps1                            # install, upgrade, or repair
  .\scripts\install.ps1 -AddRepo C:\src\backend    # also register a repository in repos.json
  .\scripts\install.ps1 -Verify                    # check installed files, isolation, and leaks
  .\scripts\install.ps1 -CleanMemory               # repair and remove Akzo text from VS Code Copilot memory (backed up)
  .\scripts\install.ps1 -Uninstall                 # remove installed agent/modules (keeps registry and task artifacts)
.NOTES
  Akzo SDD Agent — Developed and maintained by Arun RG
#>
[CmdletBinding()]
param(
    [switch]$Verify,
    [switch]$Uninstall,
    [switch]$DryRun,
    [ValidateSet('All', 'VSCode', 'VisualStudio')]
    [string]$Target = 'All',
    [string]$HomeRoot = $env:USERPROFILE,
    # Visual Studio lets users change this in Tools > Options > GitHub > Copilot.
    [string]$VisualStudioAgentsDir,
    # Adds a marked block to VS Code user settings: auto-approve for the exact helper command line, and
    # read access to the Akzo folders. Backed up first; refreshed on reruns; removed by -Uninstall.
    [switch]$ConfigureVSCode,
    # Registers these local repositories in repos.json (idempotent; repos.json is backed up first).
    [string[]]$AddRepo,
    # Backs up and removes VS Code Copilot memory files that mention Akzo (they are loaded for every agent).
    [switch]$CleanMemory,
    # Repository management (setup window). With -RegistryOnly, -AddRepo only registers (no install).
    # Source folders are never written or deleted; repos.json is backed up before every change.
    [string]$ValidateRepo,      # prints the validation as JSON; writes nothing
    [string]$RepoName,          # display name for -AddRepo (one path) or -EditRepo
    [string]$EditRepo,          # repository id to change (-RepoName, -RepoPath)
    [string]$RepoPath,
    [string]$RemoveRepo,        # repository id: removes its registration only
    [switch]$ListRepos,         # prints the registered repositories with their validation as JSON
    [switch]$RegistryOnly,
    # Tests: check this VS Code installation folder instead of the detected ones.
    [string]$VSCodeInstallDir
)
$ErrorActionPreference = 'Stop'

$Source = Split-Path -Parent $PSScriptRoot
if (-not $HomeRoot -or -not (Test-Path $HomeRoot -PathType Container)) { throw "HomeRoot '$HomeRoot' does not exist." }
$HomeRoot = (Resolve-Path $HomeRoot).Path
$AkzoHome = Join-Path $HomeRoot '.akzo-agent'
$ManifestPath = Join-Path $AkzoHome 'install-manifest.json'
# A plain rerun (update, verify) keeps the choices recorded by the previous install.
$saved = if (Test-Path $ManifestPath) { Get-Content $ManifestPath -Raw | ConvertFrom-Json } else { $null }
if (-not $PSBoundParameters.ContainsKey('Target') -and $saved.target) { $Target = $saved.target }
if (-not $VisualStudioAgentsDir) {
    $VisualStudioAgentsDir = if ($saved.visualStudioAgentsDir) { $saved.visualStudioAgentsDir } else { Join-Path $HomeRoot '.github\agents' }
}
$ModulesDir = Join-Path $AkzoHome 'modules'
$SourceVersion = if (Test-Path (Join-Path $Source 'VERSION')) { (Get-Content (Join-Path $Source 'VERSION') -TotalCount 1).Trim() } else { 'unknown' }

# Package integrity: a release package (scripts\make-release.ps1) carries release-manifest.json with the SHA-256 of every
# file. A file that differs, is missing, or is not listed stops the install before anything is written. A working
# copy without a manifest installs as before (reported). Hashes show the package is unchanged since it was built; they
# do not show who built or approved it (organizational code signing does that, where required).
$ReleaseManifest = Join-Path $Source 'release-manifest.json'
if (Test-Path $ReleaseManifest) {
    $rm = Get-Content $ReleaseManifest -Raw | ConvertFrom-Json
    $listed = @{}; foreach ($f in @($rm.files)) { $listed[($f.path -replace '/', '\')] = $f.sha256 }
    $bad = @()
    foreach ($k in $listed.Keys) { $p = Join-Path $Source $k; if (-not (Test-Path -LiteralPath $p)) { $bad += "missing $k" } elseif ((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash -ne $listed[$k]) { $bad += "modified $k" } }
    foreach ($f in Get-ChildItem $Source -Recurse -File -Force | Where-Object { $_.FullName -notmatch '\\\.git\\' -and $_.FullName -ne $ReleaseManifest }) {
        $rel = $f.FullName.Substring($Source.Length + 1); if (-not $listed.ContainsKey($rel)) { $bad += "not in the release manifest $rel" }
    }
    if ($bad) { throw "PACKAGE INTEGRITY FAILED ($ReleaseManifest, version $($rm.version)): $($bad -join '; '). Do not install this package; get it again from the trusted source." }
    if ($rm.version -ne $SourceVersion) { throw "PACKAGE INTEGRITY FAILED: release-manifest.json is for version $($rm.version), VERSION says $SourceVersion." }
    $PackageStatus = "release package $($rm.version): $(@($rm.files).Count) file(s) match release-manifest.json"
    Write-Output "package integrity OK: $(@($rm.files).Count) file(s) match release-manifest.json (version $($rm.version))"
} else {
    $PackageStatus = 'working copy'
    Write-Output 'package integrity: NOT VERIFIED - development working copy (no release-manifest.json). Release zips from scripts\make-release.ps1 carry one; install from such a zip to have the files checked.'
}
# Folders Copilot scans for skills/instructions for every agent (VS Code source + docs, Visual Studio docs).
$SharedSkillDirs = '.copilot\skills', '.agents\skills', '.claude\skills' | ForEach-Object { Join-Path $HomeRoot $_ }
$VSCodeUserDirs = 'Code', 'Code - Insiders' | ForEach-Object { Join-Path $HomeRoot "AppData\Roaming\$_\User" }
# The VS Code profile 'prompts' folder holds user-level instructions, prompts, and agents (applied to every chat).
$SharedInstructionDirs = @('.copilot\instructions', '.claude\rules' | ForEach-Object { Join-Path $HomeRoot $_ }) + @($VSCodeUserDirs | ForEach-Object { Join-Path $_ 'prompts' })
# Folders where an agent file is discovered; earlier Akzo agents left here (without a manifest entry) are migrated away.
$LegacyAgentNames = @('akzo-sdd.agent.md')
$VSCodeOnlyField = 'disable-model-invocation: true'   # VS Code: other agents cannot invoke the Akzo agents as subagents
$Registry = Join-Path $AkzoHome 'repos.json'
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$Utf8 = New-Object System.Text.UTF8Encoding($false)
$Sha = [System.Security.Cryptography.SHA256]::Create()

function Get-Hash([byte[]]$bytes) { ([BitConverter]::ToString($Sha.ComputeHash($bytes)) -replace '-', '') }
function Get-FileSha([string]$path) { Get-Hash ([IO.File]::ReadAllBytes($path)) }
function Say([string]$msg) { Write-Output $(if ($DryRun) { "[dry-run] $msg" } else { $msg }) }

$BackupOf = @{}   # original path -> backup copy made in this run (used for rollback)
function Backup([string]$path) {
    $root = Join-Path $AkzoHome "backups\$Stamp"
    $rel = $path -replace ':', ''   # full path keeps backups of files on other drives distinct
    $dest = Join-Path $root $rel
    if ($dest.Length -gt 240) {   # Windows PowerShell 5.1 cannot write past MAX_PATH (260): short name, listed in index.txt
        $dest = Join-Path $root ("long\" + (Get-Hash ([Text.Encoding]::UTF8.GetBytes($path))).Substring(0, 12) + '-' + (Split-Path $path -Leaf))
    }
    Say "backup  $path -> $dest"
    if (-not $DryRun) {
        New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
        Copy-Item -LiteralPath $path $dest -Force
        Add-Content -LiteralPath (Join-Path $root 'index.txt') -Value "$path`t$dest" -Encoding UTF8
        $BackupOf[$path] = $dest
    }
}

# VS Code Copilot memory: user memory (loaded into every agent's context) and per-workspace repository memory.
function Get-AkzoMemoryFile {
    foreach ($u in $VSCodeUserDirs) {
        $dirs = @(Join-Path $u 'globalStorage\github.copilot-chat\memory-tool\memories') +
            @(Get-ChildItem (Join-Path $u 'workspaceStorage') -Directory -ErrorAction SilentlyContinue |
                ForEach-Object { Join-Path $_.FullName 'github.copilot-chat\memory-tool\memories\repo' })
        foreach ($d in $dirs | Where-Object { Test-Path -LiteralPath $_ }) {
            Get-ChildItem -LiteralPath $d -Recurse -File -ErrorAction SilentlyContinue | Select-String -Pattern 'akzo' -List | ForEach-Object { $_.Path }
        }
    }
}

# Earlier Akzo agent files in discovery folders that this installer no longer ships (ownership: they name an Akzo agent).
function Get-LegacyAgentFile {
    $dirs = @((Join-Path $HomeRoot '.copilot\agents'), (Join-Path $HomeRoot '.github\agents'), $VisualStudioAgentsDir) + @($VSCodeUserDirs | ForEach-Object { Join-Path $_ 'prompts' })
    foreach ($d in $dirs | Sort-Object -Unique | Where-Object { Test-Path -LiteralPath $_ }) {
        foreach ($n in $LegacyAgentNames) {
            $f = Join-Path $d $n
            if ((Test-Path -LiteralPath $f) -and (Select-String -LiteralPath $f -Pattern 'Akzo (Master )?SDD Agent' -Quiet)) { $f }
        }
    }
}

# A path as typed or pasted (File Explorer address bar, "Copy as path"): trimmed, surrounding quotes dropped, %VARS%
# expanded, '..' and '/' resolved. '' unless it is a full local (C:\...) or UNC (\\server\share\...) path.
function ConvertTo-RepoPath([string]$p) {
    $p = "$p".Trim()
    if ($p.Length -ge 2 -and $p[0] -eq $p[$p.Length - 1] -and "$($p[0])" -in '"', "'") { $p = $p.Substring(1, $p.Length - 2).Trim() }
    $p = [Environment]::ExpandEnvironmentVariables($p)
    if ($p -notmatch '^([A-Za-z]:[\\/]|\\\\[^\\/]+[\\/][^\\/]+)' -or $p.IndexOfAny([IO.Path]::GetInvalidPathChars()) -ge 0) { return '' }
    try { $full = [IO.Path]::GetFullPath($p) } catch { return '' }
    if ($full.Length -gt 3) { $full = $full.TrimEnd('\') }
    $full
}

# Validation shown before a repository is saved. Invalid blocks saving; Warning needs the user's confirmation.
function Test-RepoPath([string]$given, [string]$exceptId = '') {
    $full = ConvertTo-RepoPath $given
    $v = [ordered]@{ input = "$given"; path = $full; name = ''; status = 'Invalid'; git = $false; gitTop = ''; duplicateOf = ''; message = '' }
    if (-not $full) { $v.message = 'Enter a full folder path, for example C:\src\backend or \\server\share\backend.'; return [pscustomobject]$v }
    $v.name = Split-Path $full -Leaf
    if (-not (Test-Path -LiteralPath $full -PathType Container)) { $v.message = "Folder not found (or not reachable): $full."; return [pscustomobject]$v }
    try { $null = @(Get-ChildItem -LiteralPath $full -Force -ErrorAction Stop | Select-Object -First 1) } catch { $v.message = "Folder not accessible: $($_.Exception.Message)"; return [pscustomobject]$v }
    $dup = @((Read-Config).repos | Where-Object { $_ -and $_.id -ne $exceptId -and $_.path -and (ConvertTo-RepoPath $_.path) -eq $full }) | Select-Object -First 1
    if ($dup) { $v.duplicateOf = "$($dup.id)"; $v.message = "Already registered as '$($dup.id)'."; return [pscustomobject]$v }
    if (Test-Path -LiteralPath (Join-Path $full '.git')) { $v.status = 'Valid'; $v.git = $true; $v.message = 'Git repository.'; return [pscustomobject]$v }
    $top = try { & git -C $full rev-parse --show-toplevel 2>$null } catch { '' }
    $v.status = 'Warning'
    if ($top) { $v.gitTop = "$top" -replace '/', '\'; $v.message = "Inside the Git repository $($v.gitTop); the agent works on that whole repository." }
    else { $v.message = 'Not a Git repository. It can be registered, but the agent needs a Git clone for its branch, change, and review checks and refuses this folder until it is one.' }
    [pscustomobject]$v
}

function Save-Registry($cfg) {
    if (Test-Path -LiteralPath $Registry) { Backup $Registry }
    if (-not $DryRun) { New-Item -ItemType Directory -Force -Path $AkzoHome | Out-Null; [IO.File]::WriteAllText($Registry, ($cfg | ConvertTo-Json -Depth 6), $Utf8) }
}

# The developer's recorded G8 statement is keyed by repository id; it must not carry over to another folder.
function Remove-Attestation([string]$id) {
    $auth = Join-Path $AkzoHome 'authorizations.json'
    $data = try { Get-Content -LiteralPath $auth -Raw -ErrorAction Stop | ConvertFrom-Json } catch { $null }
    if (-not $data.repos -or -not $data.repos.PSObject.Properties[$id]) { return }
    Backup $auth
    $data.repos.PSObject.Properties.Remove($id)
    Say "revoke  developer authorization recorded for '$id' (it applied to the previous folder; no approval prompt is required for ordinary tasks)"
    if (-not $DryRun) { [IO.File]::WriteAllText($auth, ($data | ConvertTo-Json -Depth 6), $Utf8) }
}

function Edit-Repository([string]$id, [string]$newPath, [string]$newName) {
    $cfg = Read-Config
    $e = @($cfg.repos | Where-Object { $_ -and $_.id -eq $id }) | Select-Object -First 1
    if (-not $e) { Write-Output "NOT SAVED: no repository '$id' in $Registry."; $script:RegistryFailed = $true; return }
    $moved = $false
    if ($newPath) {
        $v = Test-RepoPath $newPath $id
        if ($v.status -eq 'Invalid') { Write-Output "NOT SAVED: $($v.message)"; $script:RegistryFailed = $true; return }
        $moved = (ConvertTo-RepoPath $e.path) -ne $v.path
        if ($moved) { $e.path = $v.path }
    }
    $renamed = $newName -and $newName.Trim() -ne "$($e.name)"
    if ($renamed) { $e | Add-Member -NotePropertyName name -NotePropertyValue $newName.Trim() -Force }
    if (-not ($moved -or $renamed)) { Say "keep    repository '$id' (no change)"; return }
    Save-Registry $cfg
    Say "update  repository '$id'$(if ($renamed) { " name '$($e.name)'" })$(if ($moved) { " -> $($e.path)" })"
    if ($moved) { Remove-Attestation $id }
}

function Remove-Repository([string]$id) {
    $cfg = Read-Config
    $e = @($cfg.repos | Where-Object { $_ -and $_.id -eq $id }) | Select-Object -First 1
    if (-not $e) { Write-Output "NOT REMOVED: no repository '$id' in $Registry."; $script:RegistryFailed = $true; return }
    $cfg.repos = @($cfg.repos | Where-Object { $_ -and $_.id -ne $id })
    Save-Registry $cfg
    Say "remove  repository '$id' registration (the folder $($e.path) is not touched)"
    Remove-Attestation $id
    foreach ($d in @((Join-Path (Get-TasksDir $cfg) $id), (Join-Path $AkzoHome "maps\$id")) | Where-Object { Test-Path -LiteralPath $_ }) { Say "keep    $d (task files or architecture map; delete it yourself if no longer needed)" }
}

# Adds a local repository to repos.json as given (never swapped for another folder). specsDir follows a spec folder it already has.
function Add-Repository([string]$repoPath, [string]$name = '') {
    $v = Test-RepoPath $repoPath
    if ($v.duplicateOf) {
        $full = $v.path; $same = @((Read-Config).repos | Where-Object { $_ -and $_.id -eq $v.duplicateOf })[0]
        Say "keep    repository '$($same.id)' -> $full (already registered)"
        if (-not $DryRun -and -not (Test-Path (Join-Path $AkzoHome "maps\$($same.id)\architecture.json"))) { Invoke-Discovery $same.id }   # e.g. after its authorization
        return
    }
    if ($v.status -eq 'Invalid') { Write-Output "skip    AddRepo '$repoPath': $($v.message) Not registered."; $script:RegistryFailed = $true; return }
    if ($v.status -eq 'Warning') { Write-Warning "AddRepo '$($v.path)': $($v.message)" }
    $full = $v.path
    $cfg = Read-Config
    if (-not $cfg) { $cfg = Get-Content (Join-Path $Source 'config\repos.example.json') -Raw | ConvertFrom-Json }   # before the registry exists
    $repos = @($cfg.repos | Where-Object { $_ })
    $name = "$name".Trim()
    $base = ($(if ($name) { $name } else { Split-Path $full -Leaf }) -replace '[^A-Za-z0-9._-]', '-').Trim('-', '.')
    if (-not $base) { $base = 'repo' }
    $id = $base
    for ($n = 2; $repos.id -contains $id; $n++) { $id = "$base-$n" }
    $specsDir = @('openspec/changes', 'src/.github/specs', '.github/specs', 'docs/specs', 'specs') | Where-Object { Test-Path -LiteralPath (Join-Path $full $_) } | Select-Object -First 1
    $stack = @()
    if (Get-ChildItem -LiteralPath $full -Filter *.sln -Recurse -Depth 2 -ErrorAction SilentlyContinue | Select-Object -First 1) { $stack += 'dotnet' }
    if (Get-ChildItem -LiteralPath $full -Filter angular.json -Recurse -Depth 2 -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '\\node_modules\\' } | Select-Object -First 1) { $stack += 'angular' }
    $entry = [pscustomobject]@{ id = $id; name = $(if ($name) { $name } else { Split-Path $full -Leaf }); path = $full; specsDir = "$specsDir"; purpose = ''; stack = $stack; notes = @(); commands = [pscustomobject]@{ build = ''; test = ''; codegen = ''; lint = '' }; verified = [pscustomobject]@{ date = ''; commit = '' } }
    # Unconfigured example entries (no path, never verified) would only show up as choices that cannot work.
    $kept = @($repos | Where-Object { $_.path -or $_.verified.date })
    $cfg.repos = @($kept) + $entry
    Save-Registry $cfg
    Say "add     repository '$id' -> $full$(if ($specsDir) { " (specsDir $specsDir)" })"
    if (-not $DryRun) { Invoke-Discovery $id }
}

# First architecture discovery of a newly registered repository (the helper refreshes it later only when HEAD moves).
function Invoke-Discovery([string]$id) {
    $helper = Join-Path $ModulesDir 'investigate\scripts\akzo.ps1'
    if (-not (Test-Path $helper)) { return }
    $saved = $env:AKZO_AGENT_HOME
    $ErrorActionPreference = 'Continue'   # Windows PowerShell 5.1: native stderr must not abort the installer
    try {
        $env:AKZO_AGENT_HOME = $AkzoHome
        # Discovery is repository processing: it waits for the G8 authorization (policy or the developer's statement).
        $pre = (& powershell.exe -NoProfile -File $helper policy -Repo $id 2>$null) -join "`n" | ConvertFrom-Json
        if ($pre.preflight -ne 'OK') { Write-Output "skip    architecture discovery for '$id': $($pre.preflight) - $($pre.reason) (resolve the explicit policy restriction before processing)"; return }
        $raw = & powershell.exe -NoProfile -File $helper discover -Repo $id 2>$null
        $d = ($raw -join "`n") | ConvertFrom-Json
        Say "discover architecture of '$id': $($d.files) files, stack: $(if ($d.stack) { $d.stack } else { 'not detected' }) -> $($d.architecture)"
    } catch { Write-Output "skip    architecture discovery for '$id' (the agent builds it on first use): $($_.Exception.Message)" }
    finally { $env:AKZO_AGENT_HOME = $saved }
}

function Test-GitRepo([string]$p) {   # tolerate empty or malformed paths from the user-edited registry
    try { [bool]($p -and (Test-Path -LiteralPath (Join-Path $p '.git'))) } catch { $false }
}

function Read-Config { if (Test-Path $Registry) { Get-Content $Registry -Raw -Encoding UTF8 | ConvertFrom-Json } }

# Same rule as the helper (akzo.ps1): repos.json 'tasksDir', default <AkzoHome>\tasks.
function Get-TasksDir($cfg) {
    $d = if ($cfg.tasksDir) { [Environment]::ExpandEnvironmentVariables($cfg.tasksDir) } else { Join-Path $AkzoHome 'tasks' }
    $d.TrimEnd('\', '/')
}

# Problems in the user-edited registry. Reported only; the registry is never rewritten.
function Test-Config {
    try { $cfg = Read-Config } catch { "repos.json is not valid JSON ($Registry): $($_.Exception.Message)"; return }
    $ids = @($cfg.repos | Where-Object { $_ } | ForEach-Object { "$($_.id)" })
    foreach ($g in $ids | Group-Object | Where-Object { $_.Count -gt 1 }) { "duplicate repo id '$($g.Name)' in $Registry" }
    foreach ($i in $ids | Where-Object { $_ -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' }) { "repo id '$i' must be a folder name (letters, digits, '.', '_', '-')" }
    $tasks = Get-TasksDir $cfg
    if (-not [IO.Path]::IsPathRooted($tasks)) { "tasksDir '$tasks' must be an absolute path"; return }
    $p = $tasks
    while ($p -and -not (Test-Path -LiteralPath $p)) { $p = Split-Path $p }
    $top = if ($p) { try { & git -C $p rev-parse --show-toplevel 2>$null } catch { '' } }
    if ($top) { "tasksDir '$tasks' is inside the Git repository '$top'; task files would show in Git Changes" }
}

$VSCodeSettings = Join-Path $HomeRoot 'AppData\Roaming\Code\User\settings.json'
$BlockStart = '// >>> akzo-sdd (added by install.ps1 -ConfigureVSCode; removed by -Uninstall)'
$BlockEnd = '// <<< akzo-sdd'
$BlockRx = '(?s)[ \t]*' + [regex]::Escape($BlockStart) + '.*?' + [regex]::Escape($BlockEnd) + '[ \t]*\r?\n?'

# VS Code settings.json is JSONC; edit it as text so the user's comments and layout survive.
function Get-VSCodeBlock([string]$text) {
    $helper = Join-Path $ModulesDir 'investigate\scripts\akzo.ps1'
    # Only the helper, only its own commands, and no characters that could chain or substitute another command.
    $rx = '^(powershell|pwsh)(\.exe)? -NoProfile -File "?' + ([regex]::Escape($helper) -replace '\\\\', '[\\/]') +
        '"? (home|registry|state|inbox|pick|intake|attach|role|discover|task|graph|sonar|coverage|context|remember|forget|policy|guard|scan|security|branchinfo|tasks|snapshot|profile|review|affected|guidance|issue|impact|arch|workset)\b([^;&|`$<>\r\n"]|"[^"&|`$<>\r\n]*")*$'   # scope/writecheck are deliberately not auto-approved
    $rest = [regex]::Replace($text, $BlockRx, '')
    $lines = @()
    if ($rest -notmatch '"chat\.tools\.terminal\.autoApprove"') {
        $lines += '    "chat.tools.terminal.autoApprove": { ' + (ConvertTo-Json -InputObject "/$rx/i") + ': { "approve": true, "matchCommandLine": true } },'
    } else { Write-Warning "VS Code: chat.tools.terminal.autoApprove already exists in $VSCodeSettings; add the akzo helper rule from installation-guide.html yourself." }
    if ($rest -notmatch '"github\.copilot\.chat\.additionalReadAccessPaths"') {
        $lines += '    "github.copilot.chat.additionalReadAccessPaths": ' + (ConvertTo-Json -Compress -InputObject @($AkzoHome, (Get-TasksDir (Read-Config)))) + ','
    } else { Write-Warning "VS Code: github.copilot.chat.additionalReadAccessPaths already exists; add $AkzoHome to it yourself." }
    # VS Code pauses an agent with "Continue?" after 50 requests by default; a full implementation needs more.
    if ($rest -notmatch '"chat\.agent\.maxRequests"') { $lines += '    "chat.agent.maxRequests": 400,' }
    else { Write-Warning "VS Code: chat.agent.maxRequests already set; raise it (e.g. 400) if an Akzo agent stops with 'Continue?'." }
    if (-not $lines) { return '' }
    "    $BlockStart`n" + ($lines -join "`n") + "`n    $BlockEnd`n"
}

function Set-VSCodeSettingsBlock {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([switch]$Remove)
    $text = if (Test-Path $VSCodeSettings) { [IO.File]::ReadAllText($VSCodeSettings) } else { "{`n}`n" }
    $rest = [regex]::Replace($text, $BlockRx, '')
    $block = if ($Remove) { '' } else { Get-VSCodeBlock $text }
    $brace = $rest.IndexOf('{')
    if (-not $block) { $new = $rest }
    elseif ($brace -lt 0) { Write-Warning "VS Code: $VSCodeSettings has no '{'; not changed."; return }
    else {
        $new = $rest.Substring(0, $brace + 1) + "`n" + $block + $rest.Substring($brace + 1).TrimStart("`r", "`n")
        if ($rest.Substring($brace + 1) -match '^\s*\}') { $new = $new -replace ',(\r?\n    ' + [regex]::Escape($BlockEnd) + ')', '$1' }   # nothing follows: no trailing comma
    }
    if ($new -eq $text) { Say "keep    $VSCodeSettings (VS Code settings)"; return }
    if (Test-Path $VSCodeSettings) { Backup $VSCodeSettings }
    Say "$(if ($Remove) { 'clean ' } else { 'update' })  $VSCodeSettings (VS Code settings block)"
    if (-not $DryRun -and $PSCmdlet.ShouldProcess($VSCodeSettings, 'Write VS Code settings')) {
        New-Item -ItemType Directory -Force -Path (Split-Path $VSCodeSettings) | Out-Null
        [IO.File]::WriteAllText($VSCodeSettings, $new, $Utf8)
    }
}

function Read-Manifest {
    if (Test-Path $ManifestPath) { @((Get-Content $ManifestPath -Raw | ConvertFrom-Json).files) } else { @() }
}

# HEAD + porcelain status of every registered repo present on disk.
function Get-RepoSnapshot {
    $snap = @{}
    foreach ($r in @((Read-Config).repos | Where-Object { $_ })) {
        if (-not (Test-GitRepo $r.path)) { continue }
        $snap[$r.id] = ((& git -C $r.path rev-parse HEAD) + "`n" + ((& git -C $r.path status --porcelain=v1 --untracked-files=all) -join "`n"))
    }
    $snap
}

# Desired files: destination path -> bytes. Markdown gets machine paths rendered in.
function Get-DesiredFileMap {
    $render = @{
        '{{MODULES_DIR}}' = ($ModulesDir -replace '\\', '/')
        '{{AKZO_HOME}}'   = ($AkzoHome -replace '\\', '/')
        '{{VERSION}}'     = $SourceVersion
    }
    $files = [ordered]@{}
    $add = {
        param($src, $dest, [switch]$StripVSCodeOnly)
        if ($src -like '*.md') {
            $text = [IO.File]::ReadAllText($src)
            foreach ($k in $render.Keys) { $text = $text.Replace($k, $render[$k]) }
            # Visual Studio documents only name/description/model/tools; keep its copy to documented fields.
            if ($StripVSCodeOnly) { $text = [regex]::Replace($text, "(?m)^$([regex]::Escape($VSCodeOnlyField))\r?\n", '') }
            $files[$dest] = $Utf8.GetBytes($text)
        } else {
            $files[$dest] = [IO.File]::ReadAllBytes($src)
        }
    }
    foreach ($agent in Get-ChildItem (Join-Path $Source 'copilot\agents') -Filter *.agent.md) {
        if ($Target -in 'All', 'VSCode') { & $add $agent.FullName (Join-Path $HomeRoot ".copilot\agents\$($agent.Name)") }
        if ($Target -in 'All', 'VisualStudio') { & $add $agent.FullName (Join-Path $VisualStudioAgentsDir $agent.Name) -StripVSCodeOnly }
    }
    $moduleRoot = Join-Path $Source 'copilot\modules'
    foreach ($f in Get-ChildItem $moduleRoot -Recurse -File) {
        & $add $f.FullName (Join-Path $ModulesDir $f.FullName.Substring($moduleRoot.Length + 1))
    }
    & $add (Join-Path $Source 'VERSION') (Join-Path $ModulesDir 'VERSION')
    $files
}

function Remove-EmptyDirectory {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([string]$Root)
    if (-not (Test-Path $Root)) { return }
    $dirs = @(Get-ChildItem $Root -Recurse -Directory | Sort-Object { $_.FullName.Length } -Descending) + @(Get-Item $Root)
    foreach ($d in $dirs) {
        if (-not (Get-ChildItem $d.FullName -Force) -and $PSCmdlet.ShouldProcess($d.FullName, 'Remove empty directory')) { Remove-Item $d.FullName }
    }
}

function Remove-EmptyAkzoDirectory {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    Remove-EmptyDirectory -Root $ModulesDir
    # Earlier versions installed akzo-* skills into the shared skills folder; their files are removed via the old manifest.
    Get-ChildItem (Join-Path $HomeRoot '.copilot\skills') -Directory -Filter 'akzo-*' -ErrorAction SilentlyContinue |
        ForEach-Object { Remove-EmptyDirectory -Root $_.FullName }
}

# Front matter as a strict YAML parser reads it (Visual Studio's parser is not documented; VS Code's is lenient).
function Test-AgentFrontMatter([string]$text, [string]$fileName) {
    if ($text -notmatch '(?s)^﻿?---\r?\n(.*?)\r?\n---\r?\n') { return @('no front matter (--- ... ---) at the top') }
    $keys = @{}
    foreach ($line in $Matches[1] -split '\r?\n' | Where-Object { $_.Trim() }) {
        if ($line -notmatch '^([A-Za-z][\w-]*):(?:\s+(.*))?$') { "line is not 'key: value': $line"; continue }
        $k = $Matches[1]; $val = "$($Matches[2])".Trim(); $keys[$k] = $val
        if ($val -match '^"') { if ($val -notmatch '^"(?:[^"\\]|\\.)*"$') { "${k}: unterminated double-quoted value" } }
        elseif ($val -match "^'") { if ($val -notmatch "^'(?:[^']|'')*'$") { "${k}: unterminated single-quoted value" } }
        elseif ($val -match ': |\s#|^[\[\]{}&*!|>%@`]') { "${k}: plain value contains ': ', ' #', or starts with a YAML indicator; quote it" }
    }
    $base = $fileName -replace '\.agent\.md$', ''
    $nm = "$($keys['name'])".Trim('"', "'")   # the file name, or the file name with the version the picker shows (akzo-master-sdd-v4.1.0)
    if (-not $keys['name']) { 'name is missing' } elseif ($nm -ne $base -and $nm -notmatch "^$([regex]::Escape($base))-v\d+\.\d+\.\d+$") { "name '$($keys['name'])' is neither the file name '$base' nor '$base-v<version>'" }
    if (-not $keys['description']) { 'description is missing' }
}

# VS Code installations: version, and whether that build reads user-level agents from ~/.copilot/agents by default.
function Get-VSCodeInstall {
    $dirs = if ($VSCodeInstallDir) { @($VSCodeInstallDir) } else {
        @("$env:LOCALAPPDATA\Programs\Microsoft VS Code", "$env:ProgramFiles\Microsoft VS Code", "$env:LOCALAPPDATA\Programs\Microsoft VS Code Insiders", "$env:ProgramFiles\Microsoft VS Code Insiders")
    }
    foreach ($d in $dirs | Where-Object { $_ -and (Test-Path -LiteralPath $_) }) {
        $app = @(Get-Item -LiteralPath (Join-Path $d 'resources\app') -ErrorAction SilentlyContinue) + @(Get-ChildItem -LiteralPath $d -Directory -ErrorAction SilentlyContinue | ForEach-Object { Get-Item -LiteralPath (Join-Path $_.FullName 'resources\app') -ErrorAction SilentlyContinue }) |
            Where-Object { $_ } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $app) { continue }
        $version = try { (Get-Content -LiteralPath (Join-Path $app.FullName 'package.json') -Raw | ConvertFrom-Json).version } catch { 'unknown' }
        $wb = Join-Path $app.FullName 'out\vs\workbench\workbench.desktop.main.js'
        $reads = if (Test-Path -LiteralPath $wb) { [IO.File]::ReadAllText($wb).Contains('"~/.copilot/agents"') } else { $null }
        [pscustomobject]@{ dir = $d; version = "$version"; readsUserAgents = $reads }
    }
}

# ---------------------------------------------------------------- repository registry (setup window)
if ($PSBoundParameters.ContainsKey('ValidateRepo') -or $ListRepos -or $EditRepo -or $RemoveRepo -or ($RegistryOnly -and $AddRepo)) {
    try { $null = Read-Config } catch { Write-Output "NOT SAVED: repos.json is not valid JSON ($Registry): $($_.Exception.Message)"; exit 2 }
    if ($PSBoundParameters.ContainsKey('ValidateRepo')) { $v = Test-RepoPath $ValidateRepo $EditRepo; $v | ConvertTo-Json; exit $(if ($v.status -eq 'Invalid') { 1 } else { 0 }) }
    if ($ListRepos) {
        $installed = Test-Path $ManifestPath
        $auth = try { (Get-Content -LiteralPath (Join-Path $AkzoHome 'authorizations.json') -Raw -ErrorAction Stop | ConvertFrom-Json).repos } catch { $null }
        $list = foreach ($r in @((Read-Config).repos | Where-Object { $_ })) {
            $v = Test-RepoPath $r.path $r.id
            $agent = if (-not $installed) { 'Agent not installed' } else {
                'Registered' + $(if (Test-Path (Join-Path $AkzoHome "maps\$($r.id)\architecture.json")) { '; map built' } else { '; map not built yet' }) +
                $(if ($auth -and $auth.PSObject.Properties[$r.id]) { '; authorization recorded' } else { '; no approval record required for ordinary tasks' })
            }
            [pscustomobject]@{ id = "$($r.id)"; name = $(if ($r.name) { "$($r.name)" } else { "$($r.id)" }); path = "$($r.path)"; validation = $v.status; message = $v.message; agentStatus = $agent }
        }
        ConvertTo-Json -InputObject @($list) -Depth 3; exit 0
    }
    $RegistryFailed = $false
    if ($EditRepo) { Edit-Repository $EditRepo $RepoPath $RepoName }
    elseif ($RemoveRepo) { Remove-Repository $RemoveRepo }
    else {
        $paths = @($AddRepo | ForEach-Object { $_ -split ';' } | Where-Object { $_.Trim() })
        foreach ($p in $paths) { Add-Repository $p.Trim() $(if ($paths.Count -eq 1) { $RepoName }) }
    }
    exit $(if ($RegistryFailed) { 2 } else { 0 })
}

# ---------------------------------------------------------------- verify
if ($Verify) {
    $problems = 0
    $manifest = Read-Manifest
    if (-not $manifest.Count) { Write-Output "NOT INSTALLED: no manifest at $ManifestPath"; exit 1 }
    $installedVersion = if ($saved.version) { $saved.version } else { 'unknown (installed before versioning)' }
    Write-Output "VERSION   installed $installedVersion, this folder $SourceVersion"
    if ($installedVersion -ne $SourceVersion) { Write-Output "OUTDATED: run install.ps1 from this folder to update to $SourceVersion." }
    foreach ($m in $manifest) {
        if (-not (Test-Path $m.path)) { Write-Output "MISSING   $($m.path)"; $problems++ }
        elseif ((Get-FileSha $m.path) -ne $m.sha256) { Write-Output "MODIFIED  $($m.path)"; $problems++ }
        elseif ($m.path -like '*.md' -and ([IO.File]::ReadAllText($m.path) -match '\{\{[A-Z_]+\}\}')) { Write-Output "UNRENDERED $($m.path)"; $problems++ }
    }
    # Isolation: nothing Akzo-specific where Copilot loads customizations for every agent.
    foreach ($d in $SharedSkillDirs) {
        foreach ($s in Get-ChildItem $d -Directory -Filter 'akzo-*' -ErrorAction SilentlyContinue) {
            Write-Output "NOT ISOLATED: shared skill folder $($s.FullName) is offered to every agent. Remove it or re-run install.ps1."; $problems++
        }
    }
    foreach ($d in $SharedInstructionDirs) {
        foreach ($f in Get-ChildItem $d -Recurse -File -ErrorAction SilentlyContinue | Select-String -Pattern 'akzo' -List) {
            Write-Output "WARNING: $($f.Path) mentions Akzo and is applied to every agent (not created by this installer)."
        }
    }
    foreach ($f in @(Get-AkzoMemoryFile)) {
        Write-Output "LEAK: VS Code Copilot memory file $f mentions Akzo; Copilot loads memory into every agent. Run install.ps1 -CleanMemory (or Install-MasterAgent.cmd > Repair)."; $problems++
    }
    foreach ($f in @(Get-LegacyAgentFile)) {
        Write-Output "DUPLICATE: earlier Akzo agent $f is still discovered. Run install.ps1 to migrate it (backed up, then removed)."; $problems++
    }
    foreach ($m in $manifest | Where-Object { $_.path -like '*.agent.md' -and (Test-Path $_.path) }) {
        $text = [IO.File]::ReadAllText($m.path)
        foreach ($ref in [regex]::Matches($text, '[A-Za-z]:/[^"`\s]+/modules/[^"`\s]+\.(md|ps1)') | ForEach-Object { $_.Value } | Sort-Object -Unique) {
            if (-not (Test-Path $ref)) { Write-Output "MISSING MODULE $ref (referenced by $($m.path))"; $problems++ }
        }
    }
    # Repository profiles: every file profiles.json lists is installed, so the helper's 'profile' command can hand it to the agent.
    $pj = Join-Path $ModulesDir 'profiles\profiles.json'
    if (Test-Path $pj) {
        $pdefs = Get-Content $pj -Raw | ConvertFrom-Json
        $plist = @(@($pdefs.shared.skills) + @($pdefs.shared.onDemand.PSObject.Properties | ForEach-Object { $_.Name }) + @($pdefs.profiles | ForEach-Object { @($_.skills) + @($_.sonarRules) }) | Where-Object { $_ })
        $pmiss = @($plist | Where-Object { -not (Test-Path (Join-Path $ModulesDir "profiles\$_")) })
        foreach ($m in $pmiss) { Write-Output "MISSING PROFILE FILE $m"; $problems++ }
        $custom = @(Get-ChildItem (Join-Path $AkzoHome 'profiles-custom') -Recurse -File -ErrorAction SilentlyContinue)
        Write-Output "PROFILES: $(@($pdefs.profiles | ForEach-Object { "$($_.id) ($(@($_.skills).Count) skills + Sonar rules)" }) -join ', '), shared ($(@($pdefs.shared.skills).Count + @($pdefs.shared.onDemand.PSObject.Properties).Count) skills); $($plist.Count - $pmiss.Count) of $($plist.Count) files installed; $($custom.Count) custom file(s) in $AkzoHome\profiles-custom"
    } else { Write-Output 'MISSING PROFILE FILE profiles.json'; $problems++ }
    Write-Output "ISOLATION: helper and templates in $ModulesDir (not a Copilot discovery folder); agent files are the only discovered Akzo files."
    # Visual Studio reads user-level agents (%USERPROFILE%\.github\agents) only from 2026 version 18.5; 2022 has no custom agents.
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if ($Target -in 'All', 'VisualStudio' -and (Test-Path $vswhere)) {
        $vsVersions = @(& $vswhere -all -prerelease -property installationVersion 2>$null | Where-Object { $_ })
        $ok = @($vsVersions | Where-Object { [version]$_ -ge [version]'18.5' })
        if ($ok.Count) { Write-Output "VISUALSTUDIO $($ok -join ', ') supports user-level agents (folder: $VisualStudioAgentsDir; must match Tools > Options > GitHub > Copilot)." }
        else { Write-Output "WARNING: Visual Studio 2026 version 18.5 or later not found (installed: $(if ($vsVersions.Count) { $vsVersions -join ', ' } else { 'none' })). Visual Studio shows user-level agents only from 18.5; update it, or use VS Code." }
    }
    $configured = (Test-Path $VSCodeSettings) -and ([IO.File]::ReadAllText($VSCodeSettings)).Contains($BlockStart)
    Write-Output "VSCODE    settings block $(if ($configured) { 'present' } else { 'not added (optional: install.ps1 -ConfigureVSCode)' }) in $VSCodeSettings"
    $desired = Get-DesiredFileMap
    $stale = @($desired.Keys | Where-Object { -not (Test-Path $_) -or (Get-FileSha $_) -ne (Get-Hash $desired[$_]) })
    if ($stale.Count) { Write-Output "OUTDATED: $($stale.Count) file(s) differ from this repository. Run install.ps1 to update." }
    if (Test-Path $Registry) {
        $configProblems = @(Test-Config)
        foreach ($c in $configProblems) { Write-Output "CONFIG    $c"; $problems++ }
        if (-not ($configProblems -match 'not valid JSON')) {
            $cfg = Read-Config
            foreach ($r in @($cfg.repos | Where-Object { $_ })) { Write-Output ("REPO      {0,-22} {1}" -f $r.id, $(if (Test-GitRepo $r.path) { 'ok ' + $r.path } else { 'NOT FOUND ' + $r.path })) }
            $tasks = Get-TasksDir $cfg
            if (Test-Path -LiteralPath $tasks) { Write-Output "TASKS     $tasks  (refined PBIs: <repo-id>\<PBI-ID>\refined-pbi.md)" }
            else { Write-Output "MISSING   tasks folder $tasks. Run install.ps1 to create it."; $problems++ }
        }
    } else { Write-Output "NO REGISTRY at $Registry"; $problems++ }

    # Installation status, one line per check (the setup window shows these). Files on disk and IDE settings are checked;
    # whether the IDE's agent picker lists the agent cannot be read from outside the IDE, so it stays 'Not Checked'.
    $checks = New-Object Collections.ArrayList
    $add = { param($status, $name, $detail) [void]$checks.Add("CHECK [$status] ${name}: $detail") }
    $agentFiles = @($manifest | Where-Object { $_.path -like '*.agent.md' })
    $absent = @($agentFiles | Where-Object { -not (Test-Path $_.path) })
    if (-not $agentFiles.Count) { & $add 'Failed' 'Agent file existence' 'no agent file in the install manifest; run Repair.' }
    elseif ($absent.Count) { & $add 'Failed' 'Agent file existence' "missing: $(@($absent.path) -join ', '). Run Repair." }
    else { & $add 'Verified' 'Agent file existence' (@($agentFiles.path) -join '; ') }
    $meta = @(foreach ($f in $agentFiles | Where-Object { Test-Path $_.path }) { foreach ($p in @(Test-AgentFrontMatter ([IO.File]::ReadAllText($f.path)) (Split-Path $f.path -Leaf))) { "$($f.path): $p" } })
    if ($meta.Count) { & $add 'Failed' 'Agent metadata validity' (($meta -join '; ') + '. Run Repair; if it persists, the package is damaged.') }
    elseif ($agentFiles.Count -gt $absent.Count) { & $add 'Verified' 'Agent metadata validity' 'front matter parses as strict YAML; name matches the file name; description present.' }
    else { & $add 'Not Checked' 'Agent metadata validity' 'no agent file to read.' }
    $vsc = @($agentFiles | Where-Object { $_.path -like (Join-Path $HomeRoot '.copilot\agents\*') })
    if ($Target -notin 'All', 'VSCode') { & $add 'Not Applicable' 'VS Code agent configuration' "installed for target '$Target' only." }
    else {
        $codes = @(Get-VSCodeInstall)
        $settingsText = if (Test-Path $VSCodeSettings) { [IO.File]::ReadAllText($VSCodeSettings) } else { '' }
        $where = 'user-level agent folder ~/.copilot/agents (VS Code default for chat.agentFilesLocations)'
        if (-not $vsc.Count -or @($vsc | Where-Object { -not (Test-Path $_.path) }).Count) { & $add 'Failed' 'VS Code agent configuration' "the agent file is not in the $where. Run Repair." }
        elseif ($settingsText -match '"chat\.disableAIFeatures"\s*:\s*true') { & $add 'Failed' 'VS Code agent configuration' "chat.disableAIFeatures is true in $VSCodeSettings; Copilot Chat and its agents are hidden. Set it to false." }
        elseif ($settingsText -match '"~/\.copilot/agents"\s*:\s*false') { & $add 'Failed' 'VS Code agent configuration' "chat.agentFilesLocations turns ~/.copilot/agents off in $VSCodeSettings. Set it to true." }
        elseif (-not $codes.Count) { & $add 'Not Applicable' 'VS Code agent configuration' 'VS Code not found in the usual install folders; the agent file is in place for it.' }
        elseif (-not @($codes | Where-Object { $_.readsUserAgents }).Count) { & $add 'Failed' 'VS Code agent configuration' "VS Code $(@($codes.version) -join ', ') does not list ~/.copilot/agents as an agent folder. Update VS Code (Help > Check for Updates), then reload." }
        else {
            $note = if ($settingsText -match '"chat\.agentFilesLocations"' -and $settingsText -notmatch '"~/\.copilot/agents"') { " Note: $VSCodeSettings sets chat.agentFilesLocations without ~/.copilot/agents; add `"~/.copilot/agents`": true if the agent is missing." } else { '' }
            & $add $(if ($note) { 'Warning' } else { 'Verified' }) 'VS Code agent configuration' ("VS Code $(@($codes | ForEach-Object { "$($_.version)$(if (-not $_.readsUserAgents) { ' (does not read it)' })" }) -join ', ') reads the $where; the agent file is there.$note")
        }
    }
    if ($Target -notin 'All', 'VisualStudio') { & $add 'Not Applicable' 'Visual Studio agent configuration' "installed for target '$Target' only." }
    elseif (-not (Test-Path $vswhere)) { & $add 'Not Applicable' 'Visual Studio agent configuration' 'Visual Studio not installed (no vswhere.exe).' }
    else {
        $vsAll = @(try { (& $vswhere -all -prerelease -format json -utf8 2>$null) -join "`n" | ConvertFrom-Json } catch { }) | Where-Object { $_.installationVersion }
        $vsName = { param($i) $ver = "$($i.catalog.productDisplayVersion)" -replace '\s*\(.*$'; "$($i.displayName) $ver ($($i.installationVersion))" }   # edition and version
        $new = @($vsAll | Where-Object { [version]$_.installationVersion -ge [version]'18.5' })
        $vsFile = Join-Path $VisualStudioAgentsDir 'akzo-master-sdd.agent.md'
        if (-not $vsAll.Count) { & $add 'Not Applicable' 'Visual Studio agent configuration' 'no Visual Studio installation found.' }
        elseif (-not (Test-Path $vsFile)) { & $add 'Failed' 'Visual Studio agent configuration' "$vsFile is missing. Run Repair." }
        elseif (-not $new.Count) { & $add 'Warning' 'Visual Studio agent configuration' "installed $(@($vsAll | ForEach-Object { & $vsName $_ }) -join ', ') has no user-level custom agents (Microsoft documents them from Visual Studio 2026 version 18.5). Use VS Code, or update Visual Studio." }
        else { & $add 'Verified' 'Visual Studio agent configuration' "$(@($new | ForEach-Object { & $vsName $_ }) -join ', '): agent file in $VisualStudioAgentsDir (the default user agent folder; it must match Tools > Options > GitHub > Copilot if you changed it)." }
    }
    $twins = @(foreach ($d in @($VSCodeUserDirs | ForEach-Object { Join-Path $_ 'prompts' }) + @((Join-Path $HomeRoot '.claude\agents'))) {
            Get-ChildItem -LiteralPath $d -Filter *.agent.md -File -ErrorAction SilentlyContinue | Where-Object { [IO.File]::ReadAllText($_.FullName) -match '(?m)^name:\s*["'']?akzo-master-sdd' } | ForEach-Object { $_.FullName } }) +
        @(foreach ($d in @((Join-Path $HomeRoot '.copilot\agents'), $VisualStudioAgentsDir) | Sort-Object -Unique) {   # the install folders: a renamed copy there is a second agent
            Get-ChildItem -LiteralPath $d -Filter *.agent.md -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'akzo-master-sdd.agent.md' -and [IO.File]::ReadAllText($_.FullName) -match '(?m)^name:\s*["'']?akzo-master-sdd' } | ForEach-Object { $_.FullName } })
    $legacy = @(Get-LegacyAgentFile)
    if ($legacy.Count -or $twins.Count) { & $add 'Failed' 'Old-version conflicts' "other Akzo agent files are discovered too: $(@($legacy + $twins) -join ', '). Repair removes earlier agents (backed up); remove copies you placed yourself." }
    else { & $add 'Verified' 'Old-version conflicts' 'no earlier or duplicate Akzo agent file in the agent folders.' }
    $helperOk = Test-Path (Join-Path $ModulesDir 'investigate\scripts\akzo.ps1')
    $profMiss = if (Test-Path $pj) { @($pmiss).Count } else { 1 }
    if (-not $helperOk -or $profMiss) { & $add 'Failed' 'Supporting scripts and skills' "$(if (-not $helperOk) { 'helper akzo.ps1 missing; ' })$profMiss profile file(s) missing. Run Repair." }
    else { & $add 'Verified' 'Supporting scripts and skills' "helper and $(@($plist).Count) profile skill/rule file(s) present in $ModulesDir." }
    # What the agent needs at run time: the helper running as the IDE runs it, SonarQube for IDE, and the .NET SDK. Nothing is installed.
    $run = $null
    if ($helperOk) {
        $keepHome = $env:AKZO_AGENT_HOME; $ErrorActionPreference = 'Continue'
        try { $env:AKZO_AGENT_HOME = $AkzoHome; $run = (& powershell.exe -NoProfile -File (Join-Path $ModulesDir 'investigate\scripts\akzo.ps1') home 2>$null) -join "`n" | ConvertFrom-Json } catch { }
        finally { $env:AKZO_AGENT_HOME = $keepHome; $ErrorActionPreference = 'Stop' }
    }
    if (-not $run.version) { & $add 'Failed' 'Helper runs' 'the installed helper did not answer under Windows PowerShell 5.1 (powershell -NoProfile -File ...akzo.ps1 home); an organization execution policy can block it. Use approved signed deployment when required.' }
    else { & $add 'Verified' 'Helper runs' "akzo.ps1 home answered under Windows PowerShell 5.1, as the agent runs it (version $($run.version))." }
    $ide = @($run.sonarIde | Where-Object { $_ })
    if ($run.version -and -not $run.PSObject.Properties['sonarIde']) { & $add 'Not Checked' 'SonarQube for IDE' 'the installed helper predates this check (its answer has no SonarQube field); run Install / Upgrade, then Verify again.' }
    elseif ($ide.Count) { & $add 'Verified' 'SonarQube for IDE' "$($ide -join '; '). Its enabled state is shown in the IDE (Extensions); sonar -Repo <id> compares a shared Connected Mode binding with the repository's Sonar project." }
    else { & $add 'Warning' 'SonarQube for IDE' 'not found in the Visual Studio or VS Code extension folders of this user. Optional: without it the agent checks changed files with the build analyzers and the Sonar server only. This setup installs no extension.' }
    $dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
    $sdk = if ($dotnet) { try { (& $dotnet.Source --version 2>$null) -join '' } catch { '' } } else { '' }
    if ($sdk) { & $add 'Verified' 'Build and test tools' ".NET SDK $sdk ($($dotnet.Source)): the agent can build and test .NET repositories from the IDE terminal." }
    else { & $add 'Warning' 'Build and test tools' 'no .NET SDK answered (dotnet on PATH): the agent cannot build or test .NET repositories, so every build, test, and analyzer check would be reported as not run.' }
    # arch selects the isolated framework host with Visual Studio MSBuild 18+, otherwise the dotnet host.
    $anDll = Join-Path $ModulesDir 'analyzers\architecture\Akzo.ArchitectureAnalyzer.dll'
    $anExe = Join-Path $ModulesDir 'analyzers\architecture\net472\Akzo.ArchitectureAnalyzer.exe'
    $rt8 = @(if ($dotnet) { & $dotnet.Source --list-runtimes 2>$null | Where-Object { $_ -match '^Microsoft\.NETCore\.App (\d+)\.' -and [int]$Matches[1] -ge 8 } })
    $vsMsb = @($vsAll | Where-Object { [version]$_.installationVersion -ge [version]'18.0' -and (Test-Path -LiteralPath (Join-Path $_.installationPath 'MSBuild\Current\Bin\MSBuild.exe')) })
    if (-not (Test-Path -LiteralPath $anDll)) { & $add 'Warning' 'Architecture analyzer' "not installed ($anDll): this package was built without it (scripts\build-analyzer.ps1). arch reports UNAVAILABLE and the agent uses the source-level index." }
    elseif ($vsMsb.Count -and (Test-Path -LiteralPath $anExe)) { & $add 'Verified' 'Architecture analyzer' "dual hosts installed; arch uses isolated .NET Framework with $(& $vsName $vsMsb[0]) MSBuild 18+. Runtime binding redirects use that selected toolset's dependencies in the caller's cache, never in the package." }
    elseif (-not $rt8.Count) { & $add 'Warning' 'Architecture analyzer' 'installed, but no .NET runtime 8 or later answered (dotnet --list-runtimes): arch reports UNAVAILABLE and the agent uses the source-level index. Installing a .NET runtime or SDK needs your organization''s approval; this setup installs none.' }
    else { & $add 'Verified' 'Architecture analyzer' "installed; runs on $(($rt8[-1] -split ' ')[0..1] -join ' '). SDK-style projects load with the .NET SDK$(if ($sdk) { " ($sdk)" } else { ' (none found: they are parsed only)' }); .NET Framework projects with Visual Studio's MSBuild$(if ($vsMsb.Count) { " ($(& $vsName $vsMsb[0]))" } else { ' (none found: they are parsed only)' })." }
    # sonar -Check issues reads Visual Studio's Error List through the automation interop assembly the installation ships.
    $auto = @($vsAll | Where-Object { [version]$_.installationVersion -ge [version]'17.0' -and (Test-Path -LiteralPath (Join-Path $_.installationPath 'Common7\IDE\PublicAssemblies\Microsoft.VisualStudio.Interop.dll')) })
    if ($auto.Count) { & $add 'Verified' 'IDE diagnostics for the agent' "$(@($auto | ForEach-Object { & $vsName $_ }) -join ', '): sonar -Check issues reads the Error List (SonarQube for IDE, compiler, analyzers) through its automation interface while it has the repository's solution open; rule ids come from the build or the server. In VS Code the agent reads the problems tool." }
    else { & $add 'Not Checked' 'IDE diagnostics for the agent' "no Visual Studio 2022 or 2026 automation interface found: in VS Code the agent reads the problems tool when its tool list has one. review -Report <build log> gives each changed C# file's analyzer warnings either way." }
    $regs = @(if (Test-Path $Registry) { try { @((Read-Config).repos | Where-Object { $_ -and $_.path }) } catch { } })
    $badRegs = @($regs | Where-Object { (Test-RepoPath $_.path $_.id).status -ne 'Valid' })
    if (-not (Test-Path $Registry)) { & $add 'Failed' 'Registered repositories' "no $Registry. Run Install." }
    elseif (-not $regs.Count) { & $add 'Warning' 'Registered repositories' 'none yet: add your local clone with Add Repository.' }
    elseif ($badRegs.Count) { & $add 'Warning' 'Registered repositories' "$($regs.Count) registered; check: $(@($badRegs | ForEach-Object { "$($_.id) ($((Test-RepoPath $_.path $_.id).message))" }) -join '; ')" }
    else { & $add 'Verified' 'Registered repositories' "$($regs.Count) registered, all found and Git repositories." }
    & $add 'Not Applicable' 'Repository-specific configuration' 'the agent is installed per user; nothing is written into repositories (their own .github guidance is read, never changed).'
    $agentVers = @($agentFiles | Where-Object { Test-Path $_.path } | ForEach-Object { if ([IO.File]::ReadAllText($_.path) -match 'Akzo Master SDD Agent v(\d+\.\d+\.\d+)') { $Matches[1] } else { '?' } } | Sort-Object -Unique)
    $modVer = if (Test-Path (Join-Path $ModulesDir 'VERSION')) { (Get-Content (Join-Path $ModulesDir 'VERSION') -TotalCount 1).Trim() } else { '?' }
    $vers = "manifest $installedVersion, agent $($agentVers -join '/'), modules $modVer, this folder $SourceVersion"
    if (@($agentVers + $modVer | Where-Object { $_ -ne $installedVersion }).Count) { & $add 'Failed' 'Installed version consistency' "$vers. Run Repair." }
    elseif ($installedVersion -ne $SourceVersion) { & $add 'Warning' 'Installed version consistency' "$vers. Run Install / Upgrade from this folder to change to $SourceVersion." }
    else { & $add 'Verified' 'Installed version consistency' $vers }
    $broken = @($manifest | Where-Object { -not (Test-Path $_.path) -or (Get-FileSha $_.path) -ne $_.sha256 })
    $pkg = if ($saved.package) { "; installed from: $($saved.package)" } else { '' }
    if ($broken.Count) { & $add 'Failed' 'Configuration integrity' "$($broken.Count) of $($manifest.Count) installed file(s) missing or changed since install$pkg. Run Repair." }
    elseif ($saved.package -eq 'working copy') { & $add 'Warning' 'Configuration integrity' "$($manifest.Count) installed file(s) match the install manifest; installed from a development working copy, so the package itself was not checked against a release manifest." }
    else { & $add 'Verified' 'Configuration integrity' "$($manifest.Count) installed file(s) match the install manifest$pkg." }
    if ($HomeRoot -ne $env:USERPROFILE) { & $add 'Warning' 'User profile' "installed for $HomeRoot, but this Windows user's profile is $env:USERPROFILE; the IDE reads the signed-in user's profile." }
    & $add 'Not Checked' 'Agent visible in the IDE picker' "cannot be read from outside the IDE. VS Code: reload the window (Ctrl+Shift+P > Reload Window), open Chat, and look for 'akzo-master-sdd-v$installedVersion' in the agent dropdown; if missing, Ctrl+Shift+P > 'Configure Custom Agents...' lists the agents VS Code found. Visual Studio 2026 18.5+: restart it and open the Copilot Chat agent picker. An organization policy can also turn off custom agents."
    $checks
    $failed = @($checks -match '^CHECK \[Failed\]').Count
    if ($failed -and -not $problems) { $problems = $failed }   # failures the file checks above did not already count
    Write-Output $(if ($problems) { "VERIFY FAILED: $problems problem(s)." } else { "VERIFY OK: $($manifest.Count) installed file(s) match the manifest." })
    Write-Output 'Note: this checks files on disk only. Confirm discovery in the IDE agent picker (see installation-guide.html).'
    exit $(if ($problems) { 1 } else { 0 })
}

$configProblems = @(Test-Config)
foreach ($c in $configProblems) { Write-Warning "CONFIG: $c" }
if ($configProblems -match 'not valid JSON') { throw "Fix $Registry (not valid JSON) and run again. Nothing was changed." }
$before = Get-RepoSnapshot

# ---------------------------------------------------------------- uninstall
if ($Uninstall) {
    $manifest = Read-Manifest
    if (-not $manifest.Count) { Write-Output "Nothing to uninstall (no manifest at $ManifestPath)."; exit 0 }
    foreach ($m in $manifest) {
        if (-not (Test-Path $m.path)) { continue }
        if ((Get-FileSha $m.path) -ne $m.sha256) { Backup $m.path }   # edited after install: keep a copy
        Say "remove  $($m.path)"
        if (-not $DryRun) { Remove-Item $m.path -Force }
    }
    foreach ($f in @(Get-LegacyAgentFile)) {
        Backup $f
        Say "remove  $f (earlier Akzo agent)"
        if (-not $DryRun) { Remove-Item -LiteralPath $f -Force }
    }
    if ((Test-Path $VSCodeSettings) -and ([IO.File]::ReadAllText($VSCodeSettings)).Contains($BlockStart)) { Set-VSCodeSettingsBlock -Remove }
    if (-not $DryRun) { Remove-EmptyAkzoDirectory; Remove-Item $ManifestPath -Force }
    $leaks = @(Get-AkzoMemoryFile)
    if ($leaks.Count) { Write-Warning "VS Code Copilot memory still mentions Akzo ($($leaks.Count) file(s)); other agents load it. Remove with: install.ps1 -CleanMemory, or VS Code 'Chat: Clear All Memory Files'." }
    Say "Uninstalled. Kept $AkzoHome (registry, tasks, maps, graphs, backups); delete it manually if no longer needed."
} else {
# ---------------------------------------------------------------- install / update
    Write-Output "Akzo Master SDD Agent $SourceVersion"
    foreach ($req in 'copilot\agents\akzo-master-sdd.agent.md', 'copilot\modules', 'config\repos.example.json', 'VERSION') {
        if (-not (Test-Path (Join-Path $Source $req))) { throw "Source incomplete: $req missing under $Source." }
    }
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Write-Warning 'git not found on PATH: the agent needs git to inspect repositories.' }

    $old = Read-Manifest
    $desired = Get-DesiredFileMap
    $counts = @{ written = 0; unchanged = 0; removed = 0 }
    $touched = New-Object Collections.ArrayList   # files changed by this run, restored on failure
    try {
        foreach ($dest in $desired.Keys) {
            $bytes = $desired[$dest]
            if ((Test-Path $dest) -and (Get-FileSha $dest) -eq (Get-Hash $bytes)) { $counts.unchanged++; continue }
            $was = $old | Where-Object { $_.path -eq $dest } | Select-Object -First 1
            if ($was -and (Test-Path $dest) -and (Get-FileSha $dest) -ne $was.sha256) { Write-Warning "$dest was edited after it was installed; your version is backed up. Keep custom profile rules in $AkzoHome\profiles-custom, which upgrades never touch." }
            if (Test-Path $dest) { Backup $dest }
            Say "write   $dest"
            if (-not $DryRun) {
                [void]$touched.Add($dest)
                New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
                [IO.File]::WriteAllBytes($dest, $bytes)
            }
            $counts.written++
        }
        $obsolete = @($old | Where-Object { -not $desired.Contains($_.path) } | ForEach-Object { $_.path }) + @(Get-LegacyAgentFile | Where-Object { -not $desired.Contains($_) })
        foreach ($p in $obsolete | Sort-Object -Unique) {
            if (-not (Test-Path -LiteralPath $p)) { continue }
            Backup $p
            Say "remove  $p (no longer shipped)"
            if (-not $DryRun) { [void]$touched.Add($p); Remove-Item -LiteralPath $p -Force }
            $counts.removed++
        }
    } catch {
        Write-Warning "Install failed: $($_.Exception.Message) Rolling back $($touched.Count) file(s)."
        foreach ($p in $touched) {
            if ($BackupOf[$p]) { Copy-Item -LiteralPath $BackupOf[$p] $p -Force } elseif (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
        }
        throw "Install failed and was rolled back; the previous installation is unchanged. Cause: $($_.Exception.Message)"
    }
    if (-not (Test-Path $Registry)) {
        Say "create  $Registry (from config\repos.example.json - set your local repository paths)"
        if (-not $DryRun) {
            New-Item -ItemType Directory -Force -Path $AkzoHome | Out-Null
            Copy-Item (Join-Path $Source 'config\repos.example.json') $Registry
        }
    } else { Say "keep    $Registry" }
    foreach ($r in $AddRepo | ForEach-Object { $_ -split ';' } | Where-Object { $_.Trim() }) { Add-Repository $r.Trim() }   # ';' joins several paths when called through -File
    if ($CleanMemory) {
        foreach ($f in @(Get-AkzoMemoryFile)) { Backup $f; Say "remove  $f (VS Code Copilot memory mentioning Akzo)"; if (-not $DryRun) { Remove-Item -LiteralPath $f -Force } }
    }
    $tasks = Get-TasksDir (Read-Config)
    if (Test-Path -LiteralPath $tasks) { Say "keep    $tasks (tasks folder)" }
    elseif ($configProblems -match '^tasksDir') { Say "skip    tasks folder $tasks (see CONFIG warning)" }
    else {
        Say "create  $tasks (tasks folder)"
        if (-not $DryRun) { New-Item -ItemType Directory -Force -Path $tasks | Out-Null }
    }
    $inbox = Join-Path $AkzoHome 'inbox'
    if (-not (Test-Path -LiteralPath $inbox)) {
        Say "create  $inbox (inbox: drop refined PBIs here)"
        if (-not $DryRun) { New-Item -ItemType Directory -Force -Path $inbox | Out-Null }
    }
    Write-Output "Drop refined PBIs (a .md file, or a folder with notes) in: $inbox"
    Write-Output "Refined PBIs go in: $tasks\<repo-id>\<PBI-ID>\refined-pbi.md"
    if ($ConfigureVSCode -or ((Test-Path $VSCodeSettings) -and ([IO.File]::ReadAllText($VSCodeSettings)).Contains($BlockStart))) { Set-VSCodeSettingsBlock }
    if (-not $DryRun) {
        Remove-EmptyAkzoDirectory
        $entries = foreach ($k in $desired.Keys) { [pscustomobject]@{ path = $k; sha256 = Get-Hash $desired[$k] } }
        $commit = try { & git -C $Source rev-parse --short HEAD 2>$null } catch { '' }   # source may be uncommitted
        [pscustomobject]@{ product = 'Akzo Master SDD Agent'; version = $SourceVersion; maintainer = 'Arun RG'; source = $Source; commit = "$commit"; installedAt = (Get-Date).ToString('o'); target = $Target; visualStudioAgentsDir = $VisualStudioAgentsDir; package = $PackageStatus; files = @($entries) } |
            ConvertTo-Json -Depth 4 | Set-Content -Path $ManifestPath -Encoding UTF8
    }
    Say ("Done: {0} written, {1} unchanged, {2} removed." -f $counts.written, $counts.unchanged, $counts.removed)
}

# ---------------------------------------------------------------- target repo check
$after = Get-RepoSnapshot
$changed = @(@($before.Keys) + @($after.Keys) | Sort-Object -Unique | Where-Object { $before[$_] -ne $after[$_] })
if (-not $before.Count) { Write-Output 'Target repositories: none registered on disk yet (edit repos.json).' }
elseif ($changed.Count) { Write-Warning "Target repositories changed during this run: $($changed -join ', ')"; exit 1 }
else { Write-Output "Target repositories: $($before.Count) registered repo(s) unchanged (HEAD and git status)." }
if (-not $Uninstall -and -not $DryRun) { Write-Output "Next: restart VS Code / Visual Studio, then pick `"akzo-master-sdd-v$SourceVersion`" in the Copilot Chat agent picker and type `"Start Development`"." }
