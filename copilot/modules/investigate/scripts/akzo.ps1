<#
.SYNOPSIS
  Helper for the Akzo SDD Copilot agent. Keeps agent state outside target repositories.
  Windows PowerShell 5.1 and PowerShell 7 compatible. Writes only under $env:AKZO_AGENT_HOME
  (default %USERPROFILE%\.akzo-agent) and the tasks folder (repos.json 'tasksDir', default <home>\tasks),
  except spec.md/plan.md in repo mode (repo 'specsDir' in repos.json, or -RepoMode), which go into the repo.
  Task layout: <tasks>\<repo-id>\<PBI-ID>\refined-pbi.md (user input, never modified), source\ (original of the
  converted PBI), supporting\ (managed copies of supporting documents; originals are never changed), other input
  files (read-only), inputs.json (input manifest: hash, type, role, status, extraction), .extract\ (cached text of
  .docx/.pdf/.xlsx, keyed by content hash), spec.md + plan.md (external mode), refined-pbi.baseline.md (copy the
  spec was last reconciled with), task.json (remembered spec location), evidence\.
  Project knowledge per repository: maps\<repo-id>.md (verified facts the agent writes) and maps\<repo-id>\
  architecture.json + component-index.tsv (derived from 'git ls-files', refreshed only when HEAD changes).
.EXAMPLE
  akzo.ps1 pick                                       # file dialogs: the refined PBI, then optional supporting documents
  akzo.ps1 pick -Source "C:\docs\PBI 305912.docx"     # same without the dialog
  akzo.ps1 pick -Source "C:\docs\PBI.docx" -Supporting "C:\docs\rules.xlsx;C:\docs\api.yaml"
  akzo.ps1 attach -Id 305912 -Source "C:\docs\late-notes.docx"   # add supporting files to an existing task
  akzo.ps1 role -Id 305912 -File "supporting\rules.xlsx" -Role business-rule   # correct a guessed role
  akzo.ps1 discover -Repo backend-functions          # rebuild the repository's architecture index now
  akzo.ps1 task -Id PBI-123                           # everything the agent needs to start or resume (one call)
  akzo.ps1 task -Path "C:\...\PBI-123\refined-pbi.md" # same, from the file
  akzo.ps1 task -Id PBI-123 -Repo backend-functions   # pick the repo / create the task folder
  akzo.ps1 task -Id PBI-123 -Feature ImitationRequestPaintSystem   # spec folder name in the repo's specsDir
  akzo.ps1 task -Id PBI-123 -Baseline                 # record refined-pbi.md as reconciled with spec/plan
  akzo.ps1 task -Id PBI-123 -RepoMode                 # spec/plan in <repo>\specs\PBI-123\ when no specsDir is set
  akzo.ps1 registry                                   # registered repos with path/git checks
  akzo.ps1 state -Repo backend-functions              # branch, HEAD, pre-existing changes
  akzo.ps1 graph -Repo backend-functions -Update      # optional Graphify code graph, stored outside the repo
  akzo.ps1 graph -Repo backend-functions -Query "where is measurement validated"
  akzo.ps1 sonar -Repo backend-functions              # Sonar setup of the repo and this machine (no network)
  akzo.ps1 sonar -Repo backend-functions -Check gate -Branch feature/x   # read-only server query, token from SONAR_TOKEN
  akzo.ps1 sonar -Repo backend-functions -Check issues -File "src/A.cs;src/B.cs" -NewCode
  akzo.ps1 sonar -Repo backend-functions -Check issues -File "src/A.cs" -Update   # get_sonar_issues: Visual Studio's Error List (opens and saves the file first), the build, the server
  akzo.ps1 sonar -Repo backend-functions -Check issues -Update -Text "<the fixed finding's text>"   # after a fix: changed files, validation per file
  akzo.ps1 sonar -Repo backend-functions -Check rule -Key csharpsquid:S3776
  akzo.ps1 profile -Repo backend-functions             # repository development profile (Modern / Framework / none) and the files to load
  akzo.ps1 review -Repo backend-functions -Base main   # pre-PR review of the branch: recorded PR regression scenarios, profile rules
  akzo.ps1 profile -Repo backend-functions -Query "change the order validator"   # only the profile files this request needs; the rest listed as deferred
  akzo.ps1 profile -Repo backend-functions -Task fix -Query "S3776 complexity"   # a small fix: source grounding and the Sonar rules only
  akzo.ps1 issue -Repo backend-functions -Query "OrderService" -Text "S3776 complexity"   # Fix Issue start in one call: git state, profile files, located code, Sonar tools
  akzo.ps1 review -Repo backend-functions -Report "C:\...\build.log"   # per changed C# file: analysis status and its analyzer warnings from the build log
  akzo.ps1 impact -Query "measurement validation before imitation request"   # one business operation across the registered repositories: components and the links between them
  akzo.ps1 arch -Repo backend-functions                # Roslyn architecture index: projects and frameworks, symbols, calls, DI, tests, patterns (incremental)
  akzo.ps1 arch -Repo backend-functions -Query "create order validation"   # existing implementations, reusable components, impact, conventions
  akzo.ps1 arch -Repo backend-functions -Queries "OrderHandler;OrderValidator"   # bounded C# queries, one helper startup and semantic refresh
  akzo.ps1 guidance -Repo backend-functions            # which repository instruction files make Copilot read which documents, and for which agents
  akzo.ps1 affected -Repo backend-functions -Base main # staged tests: build, focused, affected regression, full suite once
  akzo.ps1 coverage -Repo backend-functions -Report "C:\...\evidence\coverage.cobertura.xml"   # coverage of changed lines
  akzo.ps1 context -Repo backend-functions -Query "validate gloss measurement range" -Mode balanced   # ranked files, symbols, facts
  akzo.ps1 remember -Repo backend-functions -Type validation -Text "Input rules live in FluentValidation validators next to the command" -Evidence "src/Orders/CreateOrderValidator.cs:7" -Pbi 305912
  akzo.ps1 forget -Repo backend-functions -Id F-1a2b3c4d -Text "validators moved to a pipeline behaviour"
.NOTES
  Akzo SDD Agent — Developed and maintained by Arun RG
#>
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet('home', 'registry', 'state', 'inbox', 'pick', 'intake', 'attach', 'role', 'discover', 'task', 'graph', 'sonar', 'coverage', 'remember', 'forget', 'context', 'policy', 'authorize', 'guard', 'scan', 'security', 'purge', 'branchinfo', 'branchcreate', 'branchuse', 'tasks', 'snapshot', 'profile', 'review', 'affected', 'guidance', 'decide', 'trace', 'prtext', 'lesson', 'issue', 'impact', 'arch', 'graphql', 'workset', 'scope', 'writecheck')]
    [string]$Command,
    [string]$Reference,       # authorize: the approval you hold (ticket, policy, or approver)
    [ValidateSet('application', 'maintenance')]
    [string]$OperatingMode = 'application',
    [string]$Classification,  # authorize: public | internal | confidential (restricted needs an administrator policy)
    [string]$Model,           # authorize: the model in use, checked against the policy's approvedModels
    [string]$Hosts,           # authorize: hosts the helper may call for this repository (e.g. the Sonar server), ';'-separated
    [string]$Line,            # guard: the command line to check
    # guard only: Windows PowerShell 5.1 does not escape inner double quotes when it starts another program, so a quoted
    # command arrives in pieces. The pieces are rejoined (quotes are lost, the words are not) and checked as one command.
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Rest,
    [string]$ApprovedBy,      # guard: who approved a NEEDS_APPROVAL command
    [switch]$Confirmed,       # purge: required, the deletion cannot be undone
    [switch]$IncludeTasks,    # purge: also delete the repository's task folders
    [string]$Name,            # branchcreate / branchuse: the branch name
    [string]$Base,            # branchcreate: the base branch the developer confirmed; review: the branch the change will merge into
    [switch]$AllowDirty,      # branchcreate / branchuse: the developer agreed to switch with uncommitted changes (git never discards them)
    [switch]$Resume,          # intake: the developer chose to resume / modify an existing task (without it an existing task id is reported, not reused)
    [string]$Type,         # remember: fact type
    [string]$Text,         # remember: the fact; forget: the reason; issue: the rule id and error words (choose the profile files); sonar -Check issues: the fixed finding's text (validation)
    [string]$Evidence,     # remember: "path:line;path:line" (repo-relative)
    [string]$DependsOn,    # remember: fact ids joined with ';'
    [string]$Pbi,          # remember: the work item the fact was verified in
    [ValidateSet('', 'compact', 'balanced', 'deep')]
    [string]$Mode = '',    # context: retrieval budget
    [ValidateSet('', 'gate', 'issues', 'hotspots', 'coverage', 'duplication', 'rule')]
    [string]$Check = '',   # sonar: which read-only server query (issues also reads the IDE and the build)
    [ValidateSet('', 'active', 'changed', 'solution')]
    [string]$Scope = '',   # sonar -Check issues without -File: the IDE's active document, the changed files (default), or everything
    [string]$Branch,
    [string]$PullRequest,
    [string]$Key,          # sonar -Check rule: the rule key, e.g. csharpsquid:S3776; profile / review: the profile to confirm (e.g. framework)
    [string]$Report,       # coverage: Cobertura, OpenCover, or LCOV reports joined with ';'; review: build logs (-flp, normal verbosity) joined with ';'
    [switch]$NewCode,
    [string]$Supporting,   # several paths joined with ';'
    [string]$File,
    [string]$Role,
    [string]$Repo,
    [string]$Id,
    [string]$Path,
    [string]$Feature,
    [string]$Source,       # pick / attach / intake: the files; sonar -Check issues: ide;build;server (default all)
    [string]$Title,
    [switch]$Baseline,
    [switch]$RepoMode,
    [switch]$Update,       # graph / discover / arch: rebuild; sonar -Check issues: open and save the files in Visual Studio, then read
    [string]$Query,
    [string]$Queries,         # arch: up to eight independent C# queries, separated by ';'
    [ValidateSet('', 'fix', 'refactor', 'new', 'review')]
    [string]$Task = '',    # profile: the kind of work; fix and refactor load only source grounding and the Sonar rules (refactor adds topic matches)
    [ValidateSet('', 'G2', 'G3', 'G4')]
    [string]$Gate = '',    # decide: the gate the developer decided on
    [ValidateSet('', 'approve', 'changes', 'custom')]
    [Alias('Decision')]   # not $Decision: PowerShell names are case-insensitive and branchuse assigns $decision
    [string]$GateDecision = '', # decide: the choice the developer made (never inferred from an ambiguous reply)
    [ValidateSet('', 'add', 'approve', 'reject', 'list', 'report')]
    [string]$Action = '',  # lesson: what to do with PR review feedback (approve / reject only on the developer's word)
    [string]$Cause,        # lesson add: why the reviewed code was wrong (the verified root cause)
    [string]$Correction    # lesson add: what the verified fix changed
)
$ErrorActionPreference = 'Stop'
if ($Rest -and $Command -ne 'guard') { throw "Unexpected argument(s) for '$Command': $($Rest -join ' ')" }   # stray arguments stay an error everywhere but guard

$ModulesDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)   # ...\modules
$AkzoHome = if ($env:AKZO_AGENT_HOME) { $env:AKZO_AGENT_HOME } else { Join-Path $env:USERPROFILE '.akzo-agent' }
$Registry = Join-Path $AkzoHome 'repos.json'
$Config = $null
if (Test-Path $Registry) {
    try { $Config = Get-Content $Registry -Raw -Encoding UTF8 | ConvertFrom-Json } catch { throw "$Registry is not valid JSON: $($_.Exception.Message)" }
}
$TasksDir = if ($Config.tasksDir) { [Environment]::ExpandEnvironmentVariables($Config.tasksDir) } else { Join-Path $AkzoHome 'tasks' }
if (-not [IO.Path]::IsPathRooted($TasksDir)) { throw "tasksDir '$TasksDir' in $Registry must be an absolute path." }
$TasksDir = $TasksDir.TrimEnd('\', '/')
$InboxDir = Join-Path $AkzoHome 'inbox'   # drop refined PBIs (file or folder) here; 'intake' copies them into a task
$Utf8NoBom = New-Object Text.UTF8Encoding($false)
$VersionFile = Join-Path $ModulesDir 'VERSION'
$Version = if (Test-Path $VersionFile) { (Get-Content $VersionFile -TotalCount 1).Trim() } else { 'unknown' }

# Windows PowerShell 5.1 turns `2>$null` on a native command into a terminating error under 'Stop'.
function Invoke-Quiet {
    $ErrorActionPreference = 'Continue'
    $exe, $rest = $args
    & $exe @rest 2>$null
}

function Test-Dir([string]$p) {   # registry is user-edited: tolerate empty or malformed paths
    try { [bool]($p -and (Test-Path -LiteralPath $p)) } catch { $false }
}

function Get-Registry { @($Config.repos | Where-Object { $_ }) }

function Get-FeatureName([string]$t) {   # "Imitation request - paint system" -> ImitationRequestPaintSystem
    (@($t -split '[^A-Za-z0-9]+' | Where-Object { $_ }) | ForEach-Object { $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1) }) -join ''
}

function Find-PbiFile([string]$folder) {   # the refined PBI inside a dropped folder
    $md = @(Get-ChildItem -LiteralPath $folder -File -Filter *.md)
    $hit = @($md | Where-Object { $_.BaseName -match 'refined[-_ ]?pbi' })
    if ($hit.Count -eq 1) { return $hit[0].FullName }
    if ($md.Count -eq 1) { return $md[0].FullName }
    $null
}

function Get-GitTop([string]$dir) {   # work tree containing $dir (or its nearest existing parent), else empty
    while ($dir -and -not (Test-Path -LiteralPath $dir)) { $dir = Split-Path $dir }
    if ($dir) { Invoke-Quiet git -C $dir rev-parse --show-toplevel }
}

function Find-WorkspaceRegistration([string]$dir, [string]$top) {
    $directory = (Resolve-Path -LiteralPath $dir).ProviderPath.TrimEnd('\')
    Get-Registry | Where-Object {
        if (-not (Test-Dir $_.path)) { return $false }
        $workspace = (Resolve-Path -LiteralPath $_.path).ProviderPath.TrimEnd('\')
        ($directory -eq $workspace -or $directory.StartsWith("$workspace\", [StringComparison]::OrdinalIgnoreCase)) -and
            "$(Get-GitTop $_.path)" -eq "$top"
    } | Sort-Object { -(Resolve-Path -LiteralPath $_.path).ProviderPath.Length } | Select-Object -First 1
}

function Out-Task([string]$status, [Collections.IDictionary]$info) {
    $info.status = $status
    [pscustomobject]$info | ConvertTo-Json -Depth 4 -Compress   # compact: this output goes into the model's context
}

$ResolvedRepos = @{}   # one resolution per repository and process (issue and impact resolve the same repository again)
function Resolve-Repo([string]$r) {
    if ($ResolvedRepos.ContainsKey($r)) { return $ResolvedRepos[$r] }
    $reg = Get-Registry
    $hit = $reg | Where-Object { $_.id -eq $r } | Select-Object -First 1
    $path = if ($hit) { $hit.path } elseif ($r) { $r } else { (Get-Location).Path }
    if (-not (Test-Dir $path)) { throw "BLOCKED: repository '$r' is not registered in $Registry and '$path' is not a folder. Register it (install.ps1 -EditRepo) or clone it; nothing was changed." }
    $agentSource = { param($p) Test-Path -LiteralPath (Join-Path $p 'copilot\agents\akzo-master-sdd.agent.md') }
    if (& $agentSource $path) { throw "BLOCKED: '$path' is the agent framework's own source, not an application repository. Name the target with -Repo <id> from $Registry." }
    $top = Invoke-Quiet git -C $path rev-parse --show-toplevel
    if (-not $top) { throw "'$path' is not a git repository." }
    $full = (Resolve-Path $top).Path
    if (& $agentSource $full) { throw "BLOCKED: '$full' is the agent framework's own source, not an application repository. Name the target with -Repo <id> from $Registry." }
    if (-not $hit) {
        $hit = Find-WorkspaceRegistration $path $top
    }
    $workspace = if ($hit) { (Resolve-Path -LiteralPath $hit.path).Path } else { (Resolve-Path -LiteralPath $path).Path }
    $ResolvedRepos[$r] = [pscustomobject]@{ id = $(if ($hit) { $hit.id } else { Split-Path $full -Leaf }); path = $full; workspace = $workspace; registered = [bool]$hit; cfg = $hit }
    $ResolvedRepos[$r]
}

function Get-WorkspaceRepo {   # the registered repository that contains the current folder (the IDE workspace), else ''
    $top = Get-GitTop (Get-Location).Path
    if (-not $top) { return '' }
    $hit = Find-WorkspaceRegistration (Get-Location).Path $top
    "$($hit.id)"
}

# The repository's own Copilot/agent customizations (skills, instructions, prompts, AGENTS.md, CLAUDE.md), at the repo
# root and one folder down (e.g. src\.github). Paths and descriptions only; the agent reads the relevant ones.
# scope = when Copilot adds the file by itself (VS Code defaults checked in Copilot Chat 0.71): every-request (all agents,
# the regular one included), matching-files (applyTo), by-description (the model chooses), when-invoked, when-selected, or
# subfolder (only when that folder is the open workspace).
function Get-RepoGuidance([string]$root) {
    $skip = 'node_modules', 'bin', 'obj', 'dist', '.git', '.angular', '.vs'
    $bases = @($root) + @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -notin $skip } | ForEach-Object { $_.FullName })
    $patterns = 'AGENTS.md', 'CLAUDE.md', '.github\copilot-instructions.md', '.github\instructions\*.instructions.md', '.github\prompts\*.prompt.md',
        '.github\skills\*\SKILL.md', '.claude\skills\*\SKILL.md', '.agents\skills\*\SKILL.md', '.github\agents\*.agent.md'
    foreach ($b in $bases) {
        foreach ($p in $patterns) {
            foreach ($f in Get-ChildItem -Path (Join-Path $b $p) -File -Force -ErrorAction SilentlyContinue) {
                $head = (Get-Content -LiteralPath $f.FullName -TotalCount 15 -Encoding UTF8) -join "`n"
                $desc = if ($head -match '(?m)^description:\s*(.+)$') { $Matches[1].Trim(' ''"') } else { '' }
                $apply = if ($head -match '(?m)^applyTo:\s*(.+)$') { $Matches[1].Trim(' ''"') } else { '' }
                $scope = if ($b -ne $root) { 'subfolder' } elseif ($p -match '^(AGENTS|CLAUDE)\.md$|copilot-instructions') { 'every-request' }
                    elseif ($p -match 'instructions\\') { if ($apply -match '^\*\*(/\*(\.\*)?)?$') { 'every-request' } elseif ($apply) { 'matching-files' } else { 'by-description' } }
                    elseif ($p -match 'prompts') { 'when-invoked' } elseif ($p -match 'agents\\') { 'when-selected' } else { 'by-description' }
                [pscustomobject]@{ path = $f.FullName.Substring($root.Length).TrimStart('\'); description = $desc; applyTo = $apply; scope = $scope }
            }
        }
    }
}

# guidance: which instruction files tell Copilot to read which documents, and for whom. A reference is 'unconditional'
# when its file reaches every request and the line demands the read (always, must, before any task, ... first).
function Get-GuidanceAudit($r) {
    $rows = @(Get-RepoGuidance $r.path)
    $known = @(Invoke-Quiet git -C $r.path -c core.quotepath=off ls-files --cached --others --exclude-standard -- '*.md')
    $skills = @{}; foreach ($g in $rows | Where-Object { $_.path -match 'skills\\([^\\]+)\\SKILL\.md$' }) { $skills[($g.path -split '\\')[-2]] = $g.path }
    $demand = '(?i)\b(always|must|mandatory|required|before (any|every|each|starting|you)|at the start)\b|\bread\b.*\bfirst\b'
    $refs = foreach ($g in $rows) {
        $n = 0
        foreach ($line in [IO.File]::ReadAllLines((Join-Path $r.path $g.path))) {
            $n++
            $names = @([regex]::Matches($line, '[\w./\\-]+\.md\b') | ForEach-Object { $_.Value.TrimStart('./\') } | Where-Object { $_ -notmatch '\.(instructions|prompt|agent)\.md$' -and ($_ -split '[\\/]')[-1] -ne ($g.path -split '\\')[-1] }) +
                @($skills.Keys | Where-Object { $line -match "(?i)(?<![\w-])$([regex]::Escape($_))(?![\w-])" -and $skills[$_] -ne $g.path })
            foreach ($doc in $names | Select-Object -Unique) {
                $leaf = ($doc -split '[\\/]')[-1]
                $found = if ($skills.ContainsKey($doc)) { $skills[$doc] -replace '\\', '/' } else { @($known | Where-Object { $_ -eq ($doc -replace '\\', '/') -or ($_ -split '/')[-1] -ieq $leaf }) | Select-Object -First 1 }
                $must = $line -match $demand
                [pscustomobject][ordered]@{ document = $doc; found = "$found"; from = "$($g.path):$n"; scope = $g.scope; mandatory = $must
                    unconditional = ($must -and $g.scope -eq 'every-request'); affectsRegularAgent = ($g.scope -in 'every-request', 'matching-files')
                    text = $(if ($line.Length -gt 160) { $line.Substring(0, 160) + '...' } else { $line.Trim() }) }
            }
        }
    }
    $refs = @($refs)
    $unc = @($refs | Where-Object { $_.unconditional })
    [pscustomobject][ordered]@{ status = $(if (-not $rows.Count) { 'NO_GUIDANCE' } elseif ($unc.Count) { 'UNCONDITIONAL_LOADS' } else { 'SCOPED' }); repo = $r.id
        files = $rows; references = $refs; unconditional = $unc.Count; missing = @($refs | Where-Object { -not $_.found } | ForEach-Object { "$($_.document) ($($_.from))" })
        note = 'Scopes are VS Code defaults (Copilot Chat 0.71: copilot-instructions.md, root AGENTS.md and CLAUDE.md, and matching applyTo files join every request of every agent; linked files are not attached automatically, the model reads them because the text says so; skills load by description). Visual Studio 2022 17.14 reads copilot-instructions.md and .instructions.md files only. Changes to these files are the repository team''s decision: this command never edits them.'
        recommendation = $(if ($unc.Count) { 'Keep every-request files to short rules for all tasks. Move each unconditional document read into a scoped .github/instructions/<topic>.instructions.md (applyTo the files it concerns) or a skill with a description, phrased as "read <document> when <task or files>".' } else { 'No change needed.' }) }
}

function Get-InboxItem($i) {   # one inbox entry with the PBI number and title guessed from its name and first heading
    $pbiFile = if ($i.PSIsContainer) { Find-PbiFile $i.FullName } elseif ($i.Extension -in '.md', '.txt') { $i.FullName } else { $null }
    # "$(...)": a file without a heading yields '' instead of an empty array (which has no .Trim()).
    $heading = if ($pbiFile) { "$(Get-Content -LiteralPath $pbiFile -TotalCount 20 -Encoding UTF8 | Where-Object { $_ -match '^\s*#+\s*\S' } | Select-Object -First 1)" -replace '^\s*#+\s*', '' } else { '' }
    [pscustomobject]@{
        name = $i.Name; path = $i.FullName; kind = $(if ($i.PSIsContainer) { 'folder' } else { 'file' }); pbiFile = $pbiFile
        suggestedId = [regex]::Match("$($i.Name) $heading", '\d{4,}').Value; suggestedTitle = ($heading -replace '^\s*\d{4,}\s*[-:.]?\s*', '').Trim()
        modified = $i.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
    }
}

# Requirement document -> markdown text. Word is read from its XML (no Office needed); PDF needs pdftotext on PATH.
function ConvertTo-PbiText([string]$file) {
    $ext = [IO.Path]::GetExtension($file).ToLowerInvariant()
    if ($ext -in '.md', '.markdown', '.txt') { return [IO.File]::ReadAllText($file) }
    if ($ext -eq '.docx') {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [IO.Compression.ZipFile]::OpenRead($file)
        try {
            $entry = $zip.GetEntry('word/document.xml')
            if (-not $entry) { throw "'$file' is not a Word document (word/document.xml missing)." }
            $reader = New-Object IO.StreamReader($entry.Open())
            try { $xml = [xml]$reader.ReadToEnd() } finally { $reader.Dispose() }
        } finally { $zip.Dispose() }
        $ns = New-Object Xml.XmlNamespaceManager($xml.NameTable)
        $ns.AddNamespace('w', 'http://schemas.openxmlformats.org/wordprocessingml/2006/main')
        $lines = foreach ($p in $xml.SelectNodes('//w:body//w:p', $ns)) {
            $text = (@($p.SelectNodes('.//w:t|.//w:tab', $ns) | ForEach-Object { if ($_.LocalName -eq 'tab') { "`t" } else { $_.InnerText } }) -join '')
            $style = $p.SelectSingleNode('w:pPr/w:pStyle/@w:val', $ns)
            if ($style -and $style.Value -match '^(Heading|Title)(\d?)$') { ('#' * [Math]::Max(1, [Math]::Min(6, [int]"0$($Matches[2])"))) + " $text" }
            elseif ($p.SelectSingleNode('w:pPr/w:numPr', $ns)) { "- $text" }
            else { $text }
        }
        return ($lines -join "`n")
    }
    if ($ext -eq '.xlsx') { return ConvertFrom-Xlsx $file }
    if ($ext -eq '.pdf') {
        $tool = Get-Command pdftotext -ErrorAction SilentlyContinue
        if (-not $tool) { throw "A PDF needs 'pdftotext' (Poppler) on PATH. Save the PBI as .docx, .md, or .txt instead." }
        $tmp = [IO.Path]::GetTempFileName()
        try {
            & $tool.Source -layout -enc UTF-8 $file $tmp
            if ($LASTEXITCODE -ne 0) { throw "pdftotext failed ($LASTEXITCODE) on '$file'." }
            return [IO.File]::ReadAllText($tmp)
        } finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
    throw "Unsupported file type '$ext'. Use .md, .txt, .docx, .xlsx, or .pdf."
}

# Excel workbook -> one Markdown table per sheet, read from its XML (no Office needed). Values as stored
# (numbers and dates unformatted); at most 2000 rows per sheet.
function ConvertFrom-Xlsx([string]$file) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($file)
    try {
        $read = { param($name) $e = $zip.GetEntry($name); if (-not $e) { return $null }; $sr = New-Object IO.StreamReader($e.Open()); try { [xml]$sr.ReadToEnd() } finally { $sr.Dispose() } }
        $wb = & $read 'xl/workbook.xml'
        if (-not $wb) { throw "'$file' is not an Excel workbook (xl/workbook.xml missing)." }
        $rels = & $read 'xl/_rels/workbook.xml.rels'
        $ss = & $read 'xl/sharedStrings.xml'
        $strings = @(if ($ss) { foreach ($si in @($ss.sst.si)) { (@($si.SelectNodes('.//*[local-name()="t"]')) | ForEach-Object { $_.InnerText }) -join '' } })
        $out = New-Object Text.StringBuilder
        foreach ($sheet in @($wb.workbook.sheets.sheet)) {
            $rid = $sheet.GetAttribute('id', 'http://schemas.openxmlformats.org/officeDocument/2006/relationships')
            $target = (@($rels.Relationships.Relationship) | Where-Object { $_.Id -eq $rid } | Select-Object -First 1).Target
            if (-not $target) { continue }
            $doc = & $read $(if ($target.StartsWith('/')) { $target.TrimStart('/') } else { "xl/$target" })
            if (-not $doc) { continue }
            [void]$out.AppendLine("## Sheet: $($sheet.name)").AppendLine()
            $rows = @($doc.worksheet.sheetData.row | Where-Object { $_ })
            $n = 0
            foreach ($row in $rows) {
                if (++$n -gt 2000) { [void]$out.AppendLine("(... $($rows.Count - 2000) more rows not extracted)"); break }
                $cells = New-Object Collections.Generic.List[string]
                foreach ($c in @($row.c | Where-Object { $_ })) {
                    $col = 0
                    foreach ($ch in ($c.r -replace '\d', '').ToCharArray()) { $col = $col * 26 + ([int]$ch - 64) }
                    while ($cells.Count -lt $col - 1) { $cells.Add('') }   # keep empty cells in place
                    $v = if ($c.t -eq 's') { $strings[[int]$c.v] } elseif ($c.t -eq 'inlineStr') { $c.is.InnerText } else { $c.v }
                    $cells.Add((("$v" -replace '\|', '\|') -replace '\r?\n', ' '))
                }
                [void]$out.AppendLine('| ' + ($cells -join ' | ') + ' |')
            }
            [void]$out.AppendLine()
        }
        $out.ToString()
    } finally { $zip.Dispose() }
}

# Copies a user's document into <root>\<sub>\ without ever touching the original. Same content already there ->
# 'duplicate' (not copied); same name, other content -> '<name>-2.ext' ('renamed'). The origin is kept in .origins.tsv.
function Copy-Managed([string]$src, [string]$root, [string]$sub = 'supporting') {
    $leaf = Split-Path $src -Leaf
    if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { return [pscustomobject]@{ name = $leaf; from = $src; status = 'missing'; file = '' } }
    $destDir = Join-Path $root $sub
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    $item = Get-Item -LiteralPath $src
    $hash = (Get-FileHash -LiteralPath $src).Hash
    $same = Get-ChildItem -LiteralPath $destDir -File | Where-Object { $_.Length -eq $item.Length -and (Get-FileHash -LiteralPath $_.FullName).Hash -eq $hash } | Select-Object -First 1
    if ($same) { return [pscustomobject]@{ name = $leaf; from = $src; status = 'duplicate'; file = "$sub\$($same.Name)" } }
    $to = Join-Path $destDir $leaf; $status = 'added'
    for ($n = 2; Test-Path -LiteralPath $to; $n++) { $to = Join-Path $destDir ("{0}-{1}{2}" -f $item.BaseName, $n, $item.Extension); $status = 'renamed' }
    Copy-Item -LiteralPath $src $to
    $rel = "$sub\$(Split-Path $to -Leaf)"
    Add-Content -LiteralPath (Join-Path $root '.origins.tsv') -Value "$rel`t$($item.FullName)" -Encoding UTF8
    [pscustomobject]@{ name = $leaf; from = $src; status = $status; file = $rel }
}

$ManagedFiles = 'refined-pbi.md', 'refined-pbi.baseline.md', 'spec.md', 'plan.md', 'task.json', 'inputs.json', '.origins.tsv'
$InputRoles = 'business-rule', 'acceptance-criteria', 'functional-spec', 'technical-spec', 'api-contract', 'database-schema', 'architecture', 'test-case', 'sample-data', 'legacy-reference', 'general', 'primary-original'

function Get-InputKind([string]$ext) {
    switch -regex ($ext) {
        '^\.(docx|pdf|xlsx)$' { 'convert'; break }
        '^\.(png|jpe?g|gif|bmp|webp|tiff?)$' { 'image'; break }
        '^\.(md|markdown|txt|json|ya?ml|xml|csv|tsv|html?|sql|graphql|gql|feature|cs|ts|tsx|js|jsx|java|py|go|kt|rb|php|ps1|sh|config|ini|toml|svg|puml|mmd|drawio|log)$' { 'text'; break }
        default { 'unsupported' }
    }
}

# A first guess from the file name and headings; the developer can correct it ('role' command).
function Get-InputRole([string]$rel, [string]$heads) {
    if ($rel -like 'source\*') { return 'primary-original' }
    $t = "$rel $heads".ToLowerInvariant()
    $ext = [IO.Path]::GetExtension($rel).ToLowerInvariant()
    if ($t -match 'openapi|swagger|api[-_ ]?contract|\bendpoint' -or $ext -in '.graphql', '.gql') { return 'api-contract' }
    if ($t -match 'schema|\bddl\b|database|\btables?\b|\berd\b' -or $ext -eq '.sql') { return 'database-schema' }
    if ($t -match 'acceptance|criteria') { return 'acceptance-criteria' }
    if ($t -match 'business[-_ ]?rule|validation|\brules?\b|policy') { return 'business-rule' }
    if ($t -match 'test[-_ ]?case|scenario|\bqa\b|\buat\b' -or $ext -eq '.feature') { return 'test-case' }
    if ($t -match 'sample|payload|example|mock' -or $ext -in '.csv', '.tsv') { return 'sample-data' }
    if ($t -match 'architect|diagram|\bhld\b|component' -or (Get-InputKind $ext) -eq 'image' -or $ext -in '.puml', '.mmd', '.drawio') { return 'architecture' }
    if ($t -match 'technical|design|\blld\b|\btsd\b') { return 'technical-spec' }
    if ($t -match 'functional|\bfsd\b|\bfrs\b|requirement') { return 'functional-spec' }
    if ($t -match 'legacy|existing|current[-_ ]?system|as[-_ ]?is' -or $ext -in '.cs', '.ts', '.js', '.java', '.py', '.go', '.kt', '.rb', '.php') { return 'legacy-reference' }
    'general'
}

# Input manifest for one task folder. Hashes only files whose size or time changed; converts .docx/.pdf/.xlsx once
# per content hash into .extract\ (written to a temp file first, so an interrupted run never leaves half a file).
function Sync-InputManifest([string]$dir) {
    $mf = Join-Path $dir 'inputs.json'
    $cache = Join-Path $dir '.extract'
    $issues = New-Object Collections.Generic.List[string]
    $old = @{}
    if (Test-Path -LiteralPath $mf) {
        try { foreach ($e in @((Get-Content -LiteralPath $mf -Raw -Encoding UTF8 | ConvertFrom-Json).files)) { if ($e) { $old[$e.file] = $e } } }
        catch { $issues.Add('inputs.json was unreadable and has been rebuilt') }
    }
    $origins = @{}
    $of = Join-Path $dir '.origins.tsv'
    if (Test-Path -LiteralPath $of) { foreach ($l in Get-Content -LiteralPath $of -Encoding UTF8) { $p = $l -split "`t", 2; if ($p.Count -eq 2) { $origins[$p[0]] = $p[1] } } }
    $pbiFile = Join-Path $dir 'refined-pbi.md'
    $pbiHash = if (Test-Path -LiteralPath $pbiFile) { (Get-FileHash -LiteralPath $pbiFile).Hash } else { '' }
    $now = (Get-Date).ToString('s')
    $entries = @(); $changed = @(); $seen = @{}; $dirty = $issues.Count -gt 0
    $files = @(Get-ChildItem -LiteralPath $dir -Recurse -File | Where-Object {
            -not ($_.DirectoryName -eq $dir -and $_.Name -in $ManagedFiles) -and $_.FullName.Substring($dir.Length + 1) -notmatch '^(evidence|\.extract)\\' })
    foreach ($f in $files) {
        $rel = $f.FullName.Substring($dir.Length + 1)
        $prev = $old[$rel]
        $stamp = "$($f.Length)|$($f.LastWriteTimeUtc.Ticks)"
        $sha = if ($prev -and $prev.stamp -eq $stamp -and $prev.sha256) { $prev.sha256 } else { (Get-FileHash -LiteralPath $f.FullName).Hash }
        $kind = Get-InputKind $f.Extension.ToLowerInvariant()
        $original = $rel -like 'source\*'
        $status = 'ok'; $note = ''; $read = $f.FullName
        if ($original) { $read = '' }   # refined-pbi.md already holds its converted text
        elseif ($kind -eq 'convert') {
            $read = Join-Path $cache ($sha.Substring(0, 16) + '.md')
            if (-not (Test-Path -LiteralPath $read)) {
                try {
                    $text = ConvertTo-PbiText $f.FullName
                    New-Item -ItemType Directory -Force -Path $cache | Out-Null
                    Write-TextAtomic $read $text   # content-addressed: concurrent extractions write the same text
                    Remove-Item -LiteralPath "$read.tmp" -Force -ErrorAction SilentlyContinue
                } catch { $status = 'unreadable'; $note = $_.Exception.Message; $read = '' }
            }
        } elseif ($kind -eq 'image') { $status = 'image'; $note = 'not read as text; attach it in chat if it matters' }
        elseif ($kind -eq 'unsupported') { $status = 'unsupported'; $note = "no reader for '$($f.Extension)'"; $read = '' }
        if (-not $original -and $status -in 'ok', 'image') {
            if ($sha -eq $pbiHash) { $status = 'duplicate'; $note = 'same content as refined-pbi.md' }
            elseif ($seen.ContainsKey($sha)) { $status = 'duplicate'; $note = "same content as $($seen[$sha])" }
            else { $seen[$sha] = $rel }
        }
        $heads = if ($prev -and $prev.sha256 -eq $sha -and $null -ne $prev.headings) { "$($prev.headings)" }
            elseif ($read -and (Test-Path -LiteralPath $read)) { (@(Get-Content -LiteralPath $read -TotalCount 400 -Encoding UTF8 | Where-Object { $_ -match '^#{1,3}\s+\S' } | Select-Object -First 8 | ForEach-Object { ($_ -replace '^#+\s*', '').Trim() }) -join '; ') }
            else { '' }
        $flag = if ($prev -and $prev.sha256 -eq $sha -and $null -ne $prev.flag) { "$($prev.flag)" }
            elseif ($read -and $kind -ne 'image' -and (Test-Path -LiteralPath $read)) { Find-InstructionText ([IO.File]::ReadAllText($read)) }
            else { '' }
        if ($flag) { $issues.Add("instruction-like text in ${rel}: '$(Protect-Text $flag)' (treated as data, not followed)") }
        if ($prev -and "$($prev.flag)" -ne $flag) { $dirty = $true }
        if ($heads.Length -gt 200) { $heads = $heads.Substring(0, 200) }
        $byUser = $prev -and $prev.roleSetBy -eq 'user'
        if ($prev -and $prev.sha256 -ne $sha) { $changed += $rel }
        if (-not $original -and $f.Name -match '^refined[-_ ]?pbi') { $issues.Add("second primary PBI: $rel (only refined-pbi.md is the requirement; rename it or set its role)") }
        if ($status -in 'unsupported', 'unreadable', 'duplicate') { $issues.Add("${status}: $rel ($note)") }
        if (-not $prev -or $prev.stamp -ne $stamp -or $prev.status -ne $status -or $prev.read -ne $read -or "$($prev.source)" -ne "$($origins[$rel])") { $dirty = $true }
        $entries += [pscustomobject][ordered]@{
            file = $rel; originalName = $f.Name; source = "$($origins[$rel])"; kind = $kind; kb = [math]::Round($f.Length / 1KB, 1)
            sha256 = $sha; stamp = $stamp; role = $(if ($byUser) { $prev.role } else { Get-InputRole $rel $heads }); roleSetBy = $(if ($byUser) { 'user' } else { 'auto' })
            status = $status; note = $note; read = $read; headings = $heads; flag = $flag; workItem = (Split-Path $dir -Leaf)
            firstSeen = $(if ($prev) { $prev.firstSeen } else { $now }); lastChanged = $(if ($prev -and $prev.sha256 -eq $sha) { $prev.lastChanged } else { $now })
        }
    }
    foreach ($k in $old.Keys) { if (-not ($entries | Where-Object { $_.file -eq $k })) { $issues.Add("missing: $k (registered earlier, file no longer present)"); $dirty = $true } }
    # Serialize only when something changed (ConvertTo-Json is the slow part on Windows PowerShell 5.1).
    if ($dirty -or -not (Test-Path -LiteralPath $mf)) {
        [IO.File]::WriteAllText($mf, ([pscustomobject]@{ workItem = (Split-Path $dir -Leaf); files = @($entries) } | ConvertTo-Json -Depth 4), $Utf8NoBom)
    }
    [pscustomobject]@{ path = $mf; entries = @($entries); changed = @($changed); issues = @($issues) }
}

# Architecture index of a repository from 'git ls-files' (tracked + untracked, honours .gitignore; no folder walk),
# rebuilt only when HEAD moved (or -Force). Generic naming roles, no project-specific names.
$ComponentRoles = [ordered]@{
    'test' = '((Tests?|Spec|IT)\.[A-Za-z]+$|\.(spec|test)\.[jt]sx?$|(^|/)tests?/)'
    'ci' = '(azure-pipelines[^/]*\.ya?ml$|(^|/)\.github/workflows/|Jenkinsfile$|\.gitlab-ci\.yml$)'
    'contract' = '(openapi|swagger)[^/]*\.(json|ya?ml)$'
    'graphql' = '\.(graphqls?|gql)$'
    'schema' = '(\.sql$|\.prisma$|(^|/)Migrations?/)'
    'i18n' = '(^|/)i18n/.+\.json$'
    'ui' = '(\.component\.(ts|html)$|\.(tsx|jsx|vue|svelte)$)'
    'ui-service' = '\.service\.ts$'
    'endpoint' = '(Controller|Controllers|Function|Functions|Endpoint|Endpoints|Resolver|Routes?)\.[A-Za-z]+$'
    'command' = 'Command\.[A-Za-z]+$'
    'query' = 'Query\.[A-Za-z]+$'
    'handler' = 'Handler\.[A-Za-z]+$'
    'validator' = '(Validator|Validation|Rules?)\.[A-Za-z]+$'
    'service' = 'Service\.[A-Za-z]+$'
    'repository' = '(Repository|Repo|Store|Dao|DbContext)\.[A-Za-z]+$'
    'mapping' = '(Mapper|Mapping|Profile|Converter)\.[A-Za-z]+$'
    'model' = '(Dto|Request|Response|Model|Entity|ViewModel)\.[A-Za-z]+$'
    'di' = '(Program|Startup|DependencyInjection|ServiceCollectionExtensions|Module|Registration)\.[A-Za-z]+$'
    'config' = '(appsettings[^/]*\.json|host\.json|application\.(ya?ml|properties))$'
}

# Memory format of maps\<repo-id>\ (architecture.json, symbols.tsv, facts.json). Older or unreadable files are rebuilt.
$MemorySchema = 3
$FactTypes = 'architecture', 'pattern', 'decision', 'component', 'validation', 'testing', 'integration', 'command', 'convention', 'pitfall'

# Content fingerprint of every tracked and untracked file (honours .gitignore): repo-relative path -> git blob id.
# Index blobs come from 'git ls-files -s'; files changed in the working tree or untracked are hashed by 'git hash-object'.
function Get-FileBlobs([string]$root) {
    $ErrorActionPreference = 'Continue'   # native stderr (line-ending warnings) must not end the helper
    $map = New-Object 'Collections.Generic.Dictionary[string,string]'
    foreach ($l in @(git -C $root -c core.quotepath=off ls-files -s 2>$null)) {
        $tab = $l.IndexOf("`t"); if ($tab -gt 0) { $map[$l.Substring($tab + 1)] = $l.Split(' ')[1] }
    }
    # diff --name-only lists files changed or deleted in the work tree; ls-files -o lists untracked ones. A listed file that
    # no longer exists was deleted (dropped from the map); the others are hashed from disk.
    $listed = @(@(git -C $root -c core.quotepath=off diff --name-only 2>$null) + @(git -C $root -c core.quotepath=off ls-files -o --exclude-standard 2>$null) | Where-Object { $_ } | Sort-Object -Unique)
    $dirty = New-Object Collections.Generic.List[string]
    foreach ($f in $listed) { if (Test-Path -LiteralPath (Join-Path $root $f) -PathType Leaf) { $dirty.Add($f) } else { [void]$map.Remove($f) } }
    # Paths as arguments in batches: piping to --stdin-paths from Windows PowerShell can prefix a byte-order mark.
    for ($b = 0; $b -lt $dirty.Count; $b += 100) {
        $batch = @($dirty[$b..([math]::Min($b + 99, $dirty.Count - 1))])
        $ids = @(git -C $root hash-object -- @batch 2>$null)
        if ($ids.Count -eq $batch.Count) { for ($i = 0; $i -lt $batch.Count; $i++) { $map[$batch[$i]] = $ids[$i] } }
        else { foreach ($p in $batch) { $map[$p] = 'unhashed-' + (Get-Item -LiteralPath (Join-Path $root $p)).LastWriteTimeUtc.Ticks } }   # still changes the fingerprint
    }
    $map
}

function Get-TextHash([string]$s) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($sha.ComputeHash($Utf8NoBom.GetBytes($s))) -replace '-', '').ToLowerInvariant() } finally { $sha.Dispose() }
}

# Declarations per language, one per line: type, method/function, route, decorator, import. Named group n is the
# symbol; routes use m (verb) and p (path). Regex, not a parser: good enough to find and rank, never a proof.
$SymbolRules = @{
    cs = @(
        @{ kind = 'route'; rx = '\[(?<m>HttpGet|HttpPost|HttpPut|HttpDelete|HttpPatch|Route|Function)\(\s*"(?<p>[^"]+)"' },
        @{ kind = 'type'; rx = '^\s*(?:\[[^\]]*\]\s*)*(?:(?:public|internal|private|protected|static|sealed|abstract|partial|readonly|file|unsafe|ref|new)\s+)*(?:class|interface|record|struct|enum)\s+(?:class\s+|struct\s+)?(?<n>[A-Za-z_]\w*)' },
        @{ kind = 'method'; rx = '^\s*(?:\[[^\]]*\]\s*)*(?:(?:public|internal|private|protected|static|virtual|override|async|sealed|abstract|new|extern|partial|unsafe)\s+)+[\w<>\[\],.?()\s]*?\b(?<n>[A-Za-z_]\w*)\s*(?:<[^>()]*>)?\s*\(' },
        @{ kind = 'import'; rx = '^\s*using\s+(?:static\s+)?(?<n>[A-Za-z_][\w.]*)\s*;' })
    ts = @(
        @{ kind = 'route'; rx = '\b(?:app|router|server)\.(?<m>get|post|put|delete|patch)\(\s*[''"`](?<p>[^''"`]+)' },
        @{ kind = 'route'; rx = '^\s*\{?\s*path:\s*[''"](?<p>[^''"]*)[''"](?<m>)' },
        @{ kind = 'decorator'; rx = '^\s*@(?<n>Component|Injectable|NgModule|Directive|Pipe|Controller|Module)\(' },
        @{ kind = 'type'; rx = '^\s*(?:export\s+)?(?:default\s+)?(?:declare\s+)?(?:abstract\s+)?(?:class|interface|enum|type)\s+(?<n>[A-Za-z_$][\w$]*)' },
        @{ kind = 'function'; rx = '^\s*(?:export\s+)?(?:default\s+)?(?:async\s+)?function\s*\*?\s*(?<n>[A-Za-z_$][\w$]*)' },
        @{ kind = 'function'; rx = '^\s*(?:export\s+)?(?:const|let)\s+(?<n>[A-Za-z_$][\w$]*)\s*(?::[^=]+)?=\s*(?:async\s+)?(?:\([^)]*\)|[A-Za-z_$][\w$]*)\s*(?::[^=]+)?=>' },
        @{ kind = 'method'; rx = '^\s+(?:(?:public|private|protected|static|async|readonly|override|abstract|get|set)\s+)*(?<n>[A-Za-z_$][\w$]*)\s*\([^)]*\)\s*(?::\s*[^{;=]+)?\{\s*$' },
        @{ kind = 'import'; rx = '^\s*import\s+(?:type\s+)?(?:[^''"]*?\s+from\s+)?[''"](?<n>[^''"]+)[''"]' },
        @{ kind = 'import'; rx = '\brequire\(\s*[''"](?<n>[^''"]+)[''"]\s*\)' })
    py = @(
        @{ kind = 'route'; rx = '^\s*@\w+(?:\.\w+)*\.(?<m>get|post|put|delete|patch|route)\(\s*[''"](?<p>[^''"]+)' },
        @{ kind = 'type'; rx = '^\s*class\s+(?<n>[A-Za-z_]\w*)' },
        @{ kind = 'function'; rx = '^(?<i>\s*)(?:async\s+)?def\s+(?<n>[A-Za-z_]\w*)' },
        @{ kind = 'import'; rx = '^\s*from\s+(?<n>[\w.]+)\s+import\b' },
        @{ kind = 'import'; rx = '^\s*import\s+(?<n>[\w.]+)' })
    java = @(
        @{ kind = 'route'; rx = '@(?<m>Get|Post|Put|Delete|Patch|Request)Mapping\(\s*(?:value\s*=\s*|path\s*=\s*)?"(?<p>[^"]*)"' },
        @{ kind = 'type'; rx = '^\s*(?:@\w+(?:\([^)]*\))?\s*)*(?:(?:public|private|protected|internal|static|final|abstract|sealed|open|data)\s+)*(?:class|interface|enum|record|object)\s+(?<n>[A-Za-z_]\w*)' },
        @{ kind = 'function'; rx = '^\s*(?:(?:public|private|protected|internal|override|suspend|open)\s+)*fun\s+(?:<[^>]+>\s*)?(?<n>\w+)\s*\(' },
        @{ kind = 'method'; rx = '^\s*(?:(?:public|private|protected|static|final|abstract|synchronized|default)\s+)+[\w<>\[\],.?\s]*?\b(?<n>[A-Za-z_]\w*)\s*\(' },
        @{ kind = 'import'; rx = '^\s*import\s+(?:static\s+)?(?<n>[\w.]+)' })
    go = @(
        @{ kind = 'type'; rx = '^type\s+(?<n>[A-Za-z_]\w*)\s+(?:struct|interface)' },
        @{ kind = 'function'; rx = '^func\s+(?:\([^)]*\)\s*)?(?<n>[A-Za-z_]\w*)' })
    graphql = @(
        @{ kind = 'graphql-operation'; rx = '^\s*(?:query|mutation|subscription)\s+(?<n>[A-Za-z_]\w*)\b' },
        @{ kind = 'graphql-fragment'; rx = '^\s*fragment\s+(?<n>[A-Za-z_]\w*)\s+on\b' },
        @{ kind = 'graphql-type'; rx = '^\s*(?:extend\s+)?(?:type|input|interface|enum|union|scalar)\s+(?<n>[A-Za-z_]\w*)\b' })
}
# Compiled on first use (most commands never extract symbols), not at every start-up.
function Initialize-SymbolRules {
    if ($script:SymbolRulesReady) { return }
    foreach ($lang in @($SymbolRules.Keys)) { foreach ($rule in $SymbolRules[$lang]) { $rule.rx = [regex]::new($rule.rx, 'Compiled') } }
    $script:SymbolRulesReady = $true
}
$SymbolLanguages = @{ '.cs' = 'cs'; '.ts' = 'ts'; '.tsx' = 'ts'; '.js' = 'ts'; '.jsx' = 'ts'; '.mjs' = 'ts'; '.cjs' = 'ts'; '.py' = 'py'; '.java' = 'java'; '.kt' = 'java'; '.go' = 'go'; '.graphql' = 'graphql'; '.graphqls' = 'graphql'; '.gql' = 'graphql' }
$SymbolStop = [Collections.Generic.HashSet[string]]::new([string[]]('if', 'for', 'foreach', 'while', 'switch', 'catch', 'using', 'lock', 'return', 'new', 'else', 'do', 'try', 'sizeof', 'typeof', 'nameof', 'function', 'constructor', 'await', 'yield', 'get', 'set', 'when', 'base', 'this', 'super'))

function Get-FileSymbols([string]$full, [string]$lang) {
    $rows = New-Object Collections.Generic.List[string]
    try { if ($lang -ne 'graphql' -and (Get-Item -LiteralPath $full).Length -gt 1MB) { return $rows }; $text = [IO.File]::ReadAllLines($full) } catch { return $rows }
    Initialize-SymbolRules
    $rules = $SymbolRules[$lang]
    for ($i = 0; $i -lt $text.Length; $i++) {
        $l = $text[$i]
        if ($l.Length -gt 400 -or $l.Length -lt 3) { continue }   # minified or generated lines, and blanks
        $c0 = $l.TrimStart(); if (-not $c0.Length -or $c0[0] -in '}', '/', '*', '#') { continue }   # closing braces and comments never declare a symbol (an opening '{' can start a route entry)
        foreach ($rule in $rules) {
            $m = $rule.rx.Match($l)
            if (-not $m.Success) { continue }
            $n = if ($m.Groups['p'].Success) { ("$($m.Groups['m'].Value) $($m.Groups['p'].Value)").Trim() } else { $m.Groups['n'].Value }
            if (-not $n -or $SymbolStop.Contains($n)) { continue }
            $kind = if ($rule.kind -eq 'function' -and $m.Groups['i'].Length -gt 0) { 'method' } else { $rule.kind }
            $rows.Add("$($i + 1)`t$kind`t$n"); break
        }
    }
    $rows
}

# Frameworks and libraries named in the repository's manifests (project files, package.json, Python and JVM build files).
$FrameworkMarkers = [ordered]@{
    'aspnetcore' = 'Sdk="Microsoft\.NET\.Sdk\.Web"|Include="Microsoft\.AspNetCore\.'; 'azure-functions-isolated' = 'Microsoft\.Azure\.Functions\.Worker'
    'azure-functions-inproc' = 'Microsoft\.NET\.Sdk\.Functions'; 'mediator-cqrs' = 'Include="MediatR'; 'fluentvalidation' = 'Include="FluentValidation'
    'ef-core' = 'Include="Microsoft\.EntityFrameworkCore'; 'dapper' = 'Include="Dapper'; 'automapper' = 'Include="AutoMapper'; 'serilog' = 'Include="Serilog'
    'graphql' = 'Include="(HotChocolate|StrawberryShake|GraphQL)|"graphql"\s*:|"@apollo/client"|(?m)^\s*(graphene|strawberry-graphql)\b'
    'xunit' = 'Include="xunit"'; 'nunit' = 'Include="NUnit"'; 'mstest' = 'Include="MSTest\.TestFramework"'; 'mocking' = 'Include="(Moq|NSubstitute|FakeItEasy)"'
    'angular' = '"@angular/core"\s*:'; 'ngrx' = '"@ngrx/store"\s*:'; 'rxjs' = '"rxjs"\s*:'; 'react' = '"react"\s*:'; 'vue' = '"vue"\s*:'; 'nextjs' = '"next"\s*:'
    'express' = '"express"\s*:'; 'nestjs' = '"@nestjs/core"\s*:'; 'jest' = '"jest"\s*:'; 'karma-jasmine' = '"karma"\s*:|"jasmine-core"\s*:'; 'vitest' = '"vitest"\s*:'
    'cypress' = '"cypress"\s*:'; 'playwright' = '"@playwright/test"\s*:'
    'django' = '(?im)(^|[\s"''])django\b'; 'flask' = '(?im)(^|[\s"''])flask\b'; 'fastapi' = '(?im)(^|[\s"''])fastapi\b'; 'sqlalchemy' = '(?im)(^|[\s"''])sqlalchemy\b'
    'pydantic' = '(?im)(^|[\s"''])pydantic\b'; 'pytest' = '(?im)(^|[\s"''])pytest\b'; 'celery' = '(?im)(^|[\s"''])celery\b'
    'spring-boot' = 'spring-boot'; 'junit' = '<artifactId>junit|junit-jupiter'; 'gin' = 'gin-gonic/gin'
}
$LanguageNames = [ordered]@{ '.cs' = 'C#'; '.ts' = 'TypeScript'; '.tsx' = 'TypeScript'; '.js' = 'JavaScript'; '.jsx' = 'JavaScript'; '.py' = 'Python'; '.java' = 'Java'; '.kt' = 'Kotlin'; '.go' = 'Go'; '.rs' = 'Rust'; '.rb' = 'Ruby'; '.php' = 'PHP'; '.swift' = 'Swift'; '.scala' = 'Scala'; '.sql' = 'SQL'; '.html' = 'HTML'; '.scss' = 'SCSS' }

function Write-TextAtomic([string]$path, [string]$text) {   # a crash mid-write never leaves a half-written memory file
    $tmp = "$path.$([guid]::NewGuid().ToString('N')).tmp"   # unique per writer: concurrent processes never share a temporary file
    [IO.File]::WriteAllText($tmp, $text, $Utf8NoBom)
    for ($try = 1; ; $try++) {
        try {   # File.Replace is atomic on NTFS: readers see the old or the new file, never a missing one
            if ([IO.File]::Exists($path)) { [IO.File]::Replace($tmp, $path, [NullString]::Value) } else { [IO.File]::Move($tmp, $path) }   # [NullString]: PowerShell passes $null to a string parameter as ""
            return
        } catch {   # a reader holding the file open or a concurrent first write: retry briefly
            if ($try -ge 20) { if ([IO.File]::Exists($tmp)) { [IO.File]::Delete($tmp) }; throw }
            Start-Sleep -Milliseconds (20 * $try)
        }
    }
}

# One writer at a time per file across agent processes (concurrent chats, IDE and terminal), so a read-modify-write
# never loses another process's update. Reentrant for the same thread. Parameter names are unusual on purpose: the
# script block runs in the caller's dynamic scope and must see the caller's variables.
function Use-FileLock([string]$lockPath, [scriptblock]$lockBody, [int]$lockSeconds = 120) {
    $lockName = 'Local\akzo-sdd-' + (Get-TextHash ([IO.Path]::GetFullPath($lockPath).ToLowerInvariant())).Substring(0, 32)
    $lockMutex = New-Object Threading.Mutex($false, $lockName)
    $lockHeld = $false
    try {
        try { $lockHeld = $lockMutex.WaitOne([TimeSpan]::FromSeconds($lockSeconds)) }
        catch { if ($_.Exception -is [Threading.AbandonedMutexException] -or $_.Exception.InnerException -is [Threading.AbandonedMutexException]) { $lockHeld = $true } else { throw } }   # a crashed holder: its writes were atomic
        if (-not $lockHeld) { throw "Another agent process is still writing $lockPath (waited $lockSeconds s); nothing was changed. Retry when it finishes." }
        & $lockBody
    } finally { if ($lockHeld) { $lockMutex.ReleaseMutex() }; $lockMutex.Dispose() }
}
function Add-LineLocked([string]$appendPath, [string]$appendText) { Use-FileLock $appendPath { [IO.File]::AppendAllText($appendPath, $appendText, $Utf8NoBom) } }

function Read-JsonOrRecover([string]$path) {   # unreadable memory is set aside (kept for inspection) and rebuilt
    if (-not (Test-Path -LiteralPath $path)) { return @{ data = $null; recovered = $false } }
    try { return @{ data = (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json); recovered = $false } }
    catch { Move-Item -LiteralPath $path "$path.corrupt-$((Get-Date).ToString('yyyyMMddHHmmss'))" -Force; return @{ data = $null; recovered = $true } }
}

function Add-MemoryLog([string]$repoId, [string]$what, [string]$detail) {
    $log = Join-Path $AkzoHome "maps\$repoId\memory-log.tsv"
    try {
        Use-FileLock $log {
            [IO.File]::AppendAllText($log, "$((Get-Date).ToString('s'))`t$what`t$(Protect-Text ($detail -replace '[\t\r\n]+', ' '))`r`n", $Utf8NoBom)
            if ((Get-Item -LiteralPath $log).Length -gt 200KB) { $keep = @(Get-Content -LiteralPath $log -Encoding UTF8 | Select-Object -Last 1000); Write-TextAtomic $log (($keep -join "`r`n") + "`r`n") }
        } -lockSeconds 10
    } catch { }   # the log is diagnostics only
}

function Get-MemoryHitRate([string]$repoId) {   # share of the last 50 synchronizations served from memory without a refresh
    $log = Join-Path $AkzoHome "maps\$repoId\memory-log.tsv"
    if (-not (Test-Path -LiteralPath $log)) { return $null }
    $lines = [IO.File]::ReadAllLines($log)   # not Get-Content with a pipeline: that cost grows with the log
    $ev = New-Object Collections.Generic.List[string]
    for ($i = $lines.Length - 1; $i -ge 0 -and $ev.Count -lt 50; $i--) { $w = $lines[$i].Split("`t"); if ($w.Length -ge 2 -and $w[1] -in 'hit', 'refresh', 'rebuild') { $ev.Add($w[1]) } }
    if (-not $ev.Count) { return $null }
    $hits = 0; foreach ($e in $ev) { if ($e -eq 'hit') { $hits++ } }
    [math]::Round(100 * $hits / $ev.Count, 1)
}

# Verified facts of a repository (maps\<repo-id>\facts.json). A fact is 'verified' while every evidence file still has
# the content it was verified against, 'stale' when one changed (or a fact it depends on is not verified), 'invalid'
# when an evidence file is gone; invalid facts expire into facts-expired.json.
function Sync-Facts($r, $blobs, $retentionDays) { Use-FileLock (Join-Path $AkzoHome "maps\$($r.id)\facts.json") { Sync-FactsUnlocked $r $blobs $retentionDays } }
function Sync-FactsUnlocked($r, $blobs, $retentionDays) {
    $dir = Join-Path $AkzoHome "maps\$($r.id)"
    $file = Join-Path $dir 'facts.json'
    $load = Read-JsonOrRecover $file
    $facts = @($load.data.facts | Where-Object { $_ })
    $byId = @{}; foreach ($f in $facts) { $byId[$f.id] = $f }
    $changed = $load.recovered
    $now = (Get-Date).ToString('s')
    $cutoff = if ($retentionDays) { (Get-Date).AddDays(-[int]$retentionDays) } else { $null }
    foreach ($f in $facts) {
        $missing = @($f.evidence | Where-Object { -not $blobs.ContainsKey($_.path) })
        $moved = @($f.evidence | Where-Object { $blobs.ContainsKey($_.path) -and $blobs[$_.path] -ne $_.blob })
        $old = $cutoff -and $f.verifiedAt -and ([datetime]$f.verifiedAt) -lt $cutoff
        $status = if ($missing -or $old) { 'invalid' } elseif ($moved) { 'stale' } else { 'verified' }
        $reason = if ($old) { "retention: verified more than $retentionDays days ago" } elseif ($missing) { "evidence removed: $(@($missing | ForEach-Object { $_.path }) -join ', ')" } elseif ($moved) { "evidence changed: $(@($moved | ForEach-Object { $_.path }) -join ', ')" } else { '' }
        $f | Add-Member -NotePropertyName _status -NotePropertyValue $status -Force
        $f | Add-Member -NotePropertyName _reason -NotePropertyValue $reason -Force
    }
    foreach ($f in $facts) {   # a fact resting on an unverified fact is not verified either
        if ($f._status -eq 'verified') {
            $bad = @($f.dependsOn | Where-Object { $_ -and (-not $byId.ContainsKey($_) -or $byId[$_]._status -ne 'verified') })
            if ($bad) { $f._status = 'stale'; $f._reason = "depends on unverified $($bad -join ', ')" }
        }
    }
    $expired = @($facts | Where-Object { $_._status -eq 'invalid' })
    $keep = @($facts | Where-Object { $_._status -ne 'invalid' })
    foreach ($f in $facts) {
        if ("$($f.status)" -ne $f._status -or "$($f.reason)" -ne $f._reason) { $changed = $true }
        $f | Add-Member -NotePropertyName status -NotePropertyValue $f._status -Force
        $f | Add-Member -NotePropertyName reason -NotePropertyValue $f._reason -Force
        $f | Add-Member -NotePropertyName checkedAt -NotePropertyValue $now -Force
        $f.PSObject.Properties.Remove('_status'); $f.PSObject.Properties.Remove('_reason')
    }
    if ($expired) {
        $ef = Join-Path $dir 'facts-expired.json'
        $old = @((Read-JsonOrRecover $ef).data.facts | Where-Object { $_ })
        foreach ($f in $expired) { $f | Add-Member -NotePropertyName expiredAt -NotePropertyValue $now -Force }
        Write-TextAtomic $ef ([pscustomobject]@{ schemaVersion = 1; repo = $r.id; facts = @($old + $expired) } | ConvertTo-Json -Depth 5)
        Add-MemoryLog $r.id 'expire' "$($expired.Count) fact(s): $(@($expired | ForEach-Object { $_.id }) -join ', ')"
    }
    if ($changed -and (Test-Path -LiteralPath $dir)) { Write-TextAtomic $file ([pscustomobject]@{ schemaVersion = 1; repo = $r.id; facts = @($keep) } | ConvertTo-Json -Depth 5) }
    $stale = @($keep | Where-Object { $_.status -eq 'stale' })
    if ($stale -and $changed) { Add-MemoryLog $r.id 'stale' "$($stale.Count) fact(s): $(@($stale | ForEach-Object { $_.id }) -join ', ')" }
    [pscustomobject][ordered]@{
        path = $file; total = $keep.Count; verified = @($keep | Where-Object { $_.status -eq 'verified' }).Count; stale = $stale.Count
        expired = $expired.Count; recovered = $load.recovered
        staleFacts = @($stale | ForEach-Object { "$($_.id): $($_.reason)" })
        all = @($keep)
    }
}

function Sync-Architecture($r, [switch]$Force, [string]$Head) {   # serialized per repository: index, symbols and architecture.json come from one source state
    Use-FileLock (Join-Path $AkzoHome "maps\$($r.id)\architecture.json") { Sync-ArchitectureUnlocked $r -Force:$Force -Head $Head }
}
function Sync-ArchitectureUnlocked($r, [switch]$Force, [string]$Head) {
    $out = Join-Path $AkzoHome "maps\$($r.id)"
    $arch = Join-Path $out 'architecture.json'
    $index = Join-Path $out 'component-index.tsv'
    $symFile = Join-Path $out 'symbols.tsv'
    $head = if ($Head) { $Head } else { "$(Invoke-Quiet git -C $r.path rev-parse HEAD)" }
    $blobs = Get-FileBlobs $r.path
    $keys = [string[]]$blobs.Keys; [Array]::Sort($keys, [StringComparer]::Ordinal)
    $sb = New-Object Text.StringBuilder
    foreach ($k in $keys) { [void]$sb.Append($k).Append("`t").Append($blobs[$k]).Append("`n") }
    $fingerprint = Get-TextHash $sb.ToString()
    $load = Read-JsonOrRecover $arch
    $prev = $load.data
    $fresh = $prev -and -not $Force -and $prev.schemaVersion -eq $MemorySchema -and "$($prev.fingerprint)" -eq $fingerprint -and (Test-Path -LiteralPath $index) -and (Test-Path -LiteralPath $symFile)
    $stats = [ordered]@{ event = 'hit'; symbolsReused = 0; symbolsParsed = 0; symbolsRemoved = 0 }
    if (-not $fresh) {
        $stats.event = if ($prev -and $prev.schemaVersion -eq $MemorySchema -and -not $Force) { 'refresh' } else { 'rebuild' }
        $files = @($blobs.Keys | Sort-Object)
        $skip = [regex]'(^|/)(bin|obj|node_modules|dist|\.angular|[Gg]enerated)/|\.g\.cs$|\.[Dd]esigner\.cs$'
        $rx = [ordered]@{}; foreach ($k in $ComponentRoles.Keys) { $rx[$k] = [regex]::new($ComponentRoles[$k], 'IgnoreCase') }
        $roleCounts = [ordered]@{}; $dirs = @{}; $exts = @{}; $leaves = @{}
        $lines = New-Object Collections.Generic.List[string]
        foreach ($p in $files) {
            if ($skip.IsMatch($p)) { continue }
            $slash = $p.IndexOf('/')
            $top = if ($slash -gt 0) { $p.Substring(0, $slash) } else { '.' }
            $dirs[$top] = 1 + $dirs[$top]
            $leaf = $p.Substring($p.LastIndexOf('/') + 1)
            $leaves[$leaf.ToLowerInvariant()] = 1
            $dot = $leaf.LastIndexOf('.')
            if ($dot -gt 0) { $e = $leaf.Substring($dot).ToLowerInvariant(); $exts[$e] = 1 + $exts[$e] }
            foreach ($k in $rx.Keys) { if ($rx[$k].IsMatch($p)) { $lines.Add("$k`t$p"); $roleCounts[$k] = 1 + $roleCounts[$k]; break } }
        }
        $stack = New-Object Collections.Generic.List[string]
        $markers = [ordered]@{ '.sln' = 'dotnet'; '.csproj' = 'dotnet'; 'package.json' = 'node'; 'angular.json' = 'angular'; 'pom.xml' = 'java-maven'; 'build.gradle' = 'java-gradle'; 'go.mod' = 'go'; 'pyproject.toml' = 'python'; 'requirements.txt' = 'python'; 'host.json' = 'azure-functions'; 'dockerfile' = 'docker'; '.graphql' = 'graphql'; '.graphqls' = 'graphql'; '.gql' = 'graphql'; '.tf' = 'terraform' }
        foreach ($m in $markers.Keys) { if (($m.StartsWith('.') -and $exts.ContainsKey($m)) -or $leaves.ContainsKey($m)) { if (-not $stack.Contains($markers[$m])) { $stack.Add($markers[$m]) } } }
        $projects = @($files | Where-Object { $_ -match '\.(sln|csproj|fsproj)$|(^|/)(package\.json|pom\.xml|build\.gradle|go\.mod|pyproject\.toml)$' -and -not $skip.IsMatch($_) } | Select-Object -First 40)
        New-Item -ItemType Directory -Force -Path $out | Out-Null
        Protect-Directory $out | Out-Null   # owner-only memory
        Write-TextAtomic $index ((@($lines | Sort-Object) -join "`r`n") + "`r`n")

        # Symbols: re-extract only files whose blob changed since the last run; deleted and renamed files drop out.
        $old = @{}
        if ($stats.event -eq 'refresh') {
            try { foreach ($l in [IO.File]::ReadAllLines($symFile)) { $c = $l.Split("`t"); if ($c.Count -ge 5) { if (-not $old.ContainsKey($c[0])) { $old[$c[0]] = @{ blob = $c[1]; rows = New-Object Collections.Generic.List[string] } }; if ($c[2] -ne '0') { $old[$c[0]].rows.Add("$($c[2])`t$($c[3])`t$($c[4])") } } } }
            catch { $old = @{}; $stats.event = 'rebuild' }
        }
        $symLines = New-Object Collections.Generic.List[string]
        foreach ($p in $files) {
            if ($skip.IsMatch($p) -or $p -match '\.min\.js$') { continue }
            $dot = $p.LastIndexOf('.'); if ($dot -lt 0) { continue }
            $lang = $SymbolLanguages[$p.Substring($dot).ToLowerInvariant()]
            if (-not $lang) { continue }
            $blob = $blobs[$p]
            if ($old.ContainsKey($p) -and $old[$p].blob -eq $blob) { $rows = $old[$p].rows; $stats.symbolsReused++ }
            else { $rows = Get-FileSymbols (Join-Path $r.path $p) $lang; $stats.symbolsParsed++ }
            $old.Remove($p)
            if ($rows.Count) { foreach ($row in $rows) { $symLines.Add("$p`t$blob`t$row") } } else { $symLines.Add("$p`t$blob`t0`t-`t") }
        }
        $stats.symbolsRemoved = $old.Count
        Write-TextAtomic $symFile (($symLines -join "`r`n") + "`r`n")

        $manifests = @($files | Where-Object { $_ -match '\.(cs|fs|vb)proj$|(^|/)(Directory\.Packages\.props|package\.json|pyproject\.toml|Pipfile|setup\.py|pom\.xml|build\.gradle(\.kts)?|go\.mod)$|(^|/)requirements[^/]*\.txt$' -and -not $skip.IsMatch($_) } | Select-Object -First 80)
        $frameworks = [ordered]@{}
        foreach ($mf in $manifests) {
            $t = try { [IO.File]::ReadAllText((Join-Path $r.path $mf)) } catch { '' }
            foreach ($k in $FrameworkMarkers.Keys) { if (-not $frameworks.Contains($k) -and $t -match $FrameworkMarkers[$k]) { $frameworks[$k] = $mf } }
        }
        $languages = [ordered]@{}
        foreach ($e in $exts.Keys) { if ($LanguageNames.Contains($e)) { $languages[$LanguageNames[$e]] = $exts[$e] + $languages[$LanguageNames[$e]] } }
        $routeCount = @($symLines | Where-Object { $_.Split("`t")[3] -eq 'route' }).Count
        $count = { param($k) [int]$roleCounts[$k] }
        $patterns = @(
            if ((& $count 'handler') -and ((& $count 'command') + (& $count 'query'))) { "command/query objects with handlers ($(& $count 'command') commands, $(& $count 'query') queries, $(& $count 'handler') handlers)" }
            if ($frameworks.Contains('mediator-cqrs')) { "mediator dispatch ($($frameworks['mediator-cqrs']))" }
            if (& $count 'validator') { "validation in separate validator classes ($(& $count 'validator') files)" }
            if (& $count 'repository') { "data access behind repositories or contexts ($(& $count 'repository') files)" }
            if (& $count 'endpoint') { "entry points in controllers, functions, or routers ($(& $count 'endpoint') files)" }
            if ($routeCount) { "declared routes ($routeCount in symbols.tsv)" }
            if ((& $count 'ui') -and (& $count 'ui-service')) { "UI components with services ($(& $count 'ui') components, $(& $count 'ui-service') services)" }
            if (& $count 'di') { "dependency registration modules ($(& $count 'di') files)" }
            $layers = @($projects + @($dirs.Keys) | Where-Object { $_ -match '(Domain|Application|Infrastructure)' })
            if ($layers.Count -ge 2) { "layered projects by name ($(@($layers | Select-Object -First 4) -join ', '))" }
            if (& $count 'test') { "tests ($(& $count 'test') files)" })
        $prev = [pscustomobject][ordered]@{
            schemaVersion = $MemorySchema; repo = $r.id; commit = $head; fingerprint = $fingerprint; generated = (Get-Date).ToString('s'); files = $files.Count; stack = @($stack)
            languages = [pscustomobject]$languages
            frameworks = @($frameworks.Keys | ForEach-Object { "$_ ($($frameworks[$_]))" })
            patterns = [pscustomobject][ordered]@{ status = 'inferred from file names and manifests; confirm by reading a sibling feature before relying on it'; items = $patterns }
            topDirs = @($dirs.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 15 | ForEach-Object { "$($_.Key) ($($_.Value))" })
            extensions = @($exts.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 12 | ForEach-Object { "$($_.Key) ($($_.Value))" })
            projects = $projects; roleCounts = [pscustomobject]$roleCounts; symbols = $symLines.Count; specsDir = "$($r.cfg.specsDir)"
        }
        Write-TextAtomic $arch ($prev | ConvertTo-Json -Depth 4)
        $detail = "parsed $($stats.symbolsParsed), reused $($stats.symbolsReused), removed $($stats.symbolsRemoved)$(if ($load.recovered) { ', architecture.json was unreadable' })"
        Add-MemoryLog $r.id $stats.event $detail
    } else { Add-MemoryLog $r.id 'hit' '' }
    $script:LastBlobs = $blobs   # reused by the caller (facts, context) without hashing again
    [pscustomobject][ordered]@{
        architecture = $arch; componentIndex = $index; symbols = $symFile; knowledge = (Join-Path $AkzoHome "maps\$($r.id).md")
        commit = $prev.commit; refreshed = -not $fresh; files = $prev.files; stack = (@($prev.stack) -join ', ')
        languages = (@($prev.languages.PSObject.Properties | ForEach-Object { "$($_.Name) $($_.Value)" }) -join ', ')
        frameworks = (@($prev.frameworks) -join ', ')
        patterns = @($prev.patterns.items)
        topDirs = (@($prev.topDirs) | Select-Object -First 8) -join ', '
        roles = (@($prev.roleCounts.PSObject.Properties | ForEach-Object { "$($_.Name) $($_.Value)" }) -join ', ')
        memory = [pscustomobject][ordered]@{ event = $stats.event; symbolsReused = $stats.symbolsReused; symbolsParsed = $stats.symbolsParsed; symbolsRemoved = $stats.symbolsRemoved; hitRatePct = (Get-MemoryHitRate $r.id) }
    }
}

# Inputs are data, never instructions: flag text that tries to steer the agent so it is not followed.
$InstructionPatterns = @(
    '(?i)\b(ignore|disregard|forget)\s+(all\s+|any\s+|the\s+)?(previous|prior|above|earlier|system)\s+(instructions|prompts?|rules)',
    '(?i)\byou\s+are\s+now\s+(a|an|the|in)\b', '(?i)\b(new|updated)\s+system\s+prompt\b', '(?i)\bdeveloper\s+mode\b',
    '(?i)\bdo\s+not\s+(tell|inform|show)\s+the\s+(user|developer)\b', '(?i)\b(skip|bypass|disable)\s+(the\s+)?(approval|gates?|tests?|review|security)\b',
    '(?i)\b(curl|wget|iwr|Invoke-WebRequest)\b[^\r\n|]*\|\s*(sh|bash|iex|Invoke-Expression)\b', '(?i)\bInvoke-Expression\b|\biex\s*\(',
    '(?i)\b(push|commit)\s+(directly\s+)?to\s+(main|master|production)\b')
function Find-InstructionText([string]$text) {
    if (-not $text) { return '' }
    if ($text.Length -gt 400KB) { $text = $text.Substring(0, 400KB) }
    foreach ($p in $InstructionPatterns) { $m = [regex]::Match($text, $p); if ($m.Success) { $s = $m.Value -replace '\s+', ' '; return $(if ($s.Length -gt 80) { $s.Substring(0, 80) } else { $s }) } }
    ''
}

# Secrets never go into memory: a value that looks like one is refused (the message does not repeat it).
$SecretPatterns = [ordered]@{
    # Order matters: the first match names the finding, so specific, high-certainty patterns come before the generic
    # 'credential assignment' (which also matches many harmless lines and is therefore only a "review" finding).
    'connection string with credentials' = '(?i)(AccountKey|SharedAccessKey|Password|Pwd)=[^;\s]{4,}'
    'private key' = '-----BEGIN [A-Z ]*PRIVATE KEY-----'
    'GitHub token' = '\b(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}\b|\bgithub_pat_[A-Za-z0-9_]{20,}'
    'Sonar token' = '\bsq[uap]_[A-Za-z0-9]{20,}\b'
    'AWS access key' = '\bAKIA[0-9A-Z]{16}\b'
    'Slack token' = '\bxox[abprs]-[A-Za-z0-9-]{10,}'
    'JSON web token' = '\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}'
    'bearer token' = '(?i)\bBearer\s+[A-Za-z0-9._~+/=-]{20,}'
    'shared access signature' = '(?i)[?&]sig=[A-Za-z0-9%+/=]{20,}'
    'credential assignment' = '(?i)\b(password|passwd|pwd|secret|api[_-]?key|access[_-]?key|client[_-]?secret|auth[_-]?token|token)\b\s*[=:]\s*["'']?[^\s"'';,]{6,}'
}
function Find-Secret([string]$text) { foreach ($k in $SecretPatterns.Keys) { if ($text -match $SecretPatterns[$k]) { return $k } }; '' }

# Search terms: camelCase and separators split, lower case, simple suffix stemming (validation/validator/validate -> valid).
$StopWords = [Collections.Generic.HashSet[string]]::new([string[]]('the', 'and', 'for', 'with', 'from', 'that', 'this', 'when', 'then', 'given', 'should', 'must', 'shall', 'will', 'can', 'into', 'are', 'was', 'not', 'all', 'any', 'each', 'add', 'new', 'use', 'user', 'users', 'allow', 'able', 'via', 'per', 'its', 'has', 'have', 'been', 'only', 'also', 'such', 'than', 'cs', 'ts', 'js', 'py', 'java', 'go', 'src', 'app', 'lib', 'test', 'tests', 'spec', 'index', 'main', 'component', 'html'))
function Get-Stem([string]$w) {
    foreach ($s in 'ations', 'ation', 'ators', 'ator', 'ating', 'ates', 'ated', 'ate', 'ings', 'ing', 'ies', 'ed', 's') {   # no -er/-es: order, service stay whole
        if ($w.EndsWith($s) -and $w.Length - $s.Length -ge 3 -and -not ($s -eq 's' -and $w.EndsWith('ss'))) { return $w.Substring(0, $w.Length - $s.Length) + $(if ($s -eq 'ies') { 'y' } else { '' }) }
    }
    $w
}
function Get-Tokens([string]$s) {   # loops, not pipelines: called for every path and many symbols
    $s = [regex]::Replace([regex]::Replace($s, '([a-z0-9])([A-Z])', '$1 $2'), '([A-Z]+)([A-Z][a-z])', '$1 $2')
    $out = New-Object Collections.Generic.List[string]
    foreach ($w in [regex]::Split($s.ToLowerInvariant(), '[^a-z0-9]+')) {
        if ($w.Length -ge 2 -and -not $StopWords.Contains($w)) { $st = Get-Stem $w; if (-not $out.Contains($st)) { $out.Add($st) } }
    }
    $out.ToArray()
}

# Sonar setup of a repository, read from its tracked files and this machine. No network; a token is only
# reported as set or not, never read out.
# Visual Studio installations from vswhere (the installer's own query tool): edition, version, and whether the version
# shows user-level custom agents (Visual Studio 2026 version 18.5 or later).
function Get-VisualStudioInstance {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere)) { return @() }
    @(try { (Invoke-Quiet $vswhere -all -prerelease -format json -utf8) -join "`n" | ConvertFrom-Json } catch { }) | Where-Object { $_.installationPath } | ForEach-Object {
        [pscustomobject][ordered]@{ name = "$($_.displayName)"; version = "$($_.catalog.productDisplayVersion)" -replace '\s*\(.*$'; instance = "$($_.instanceId)"; path = "$($_.installationPath)"
            customAgents = [bool]([version]"$($_.installationVersion)" -ge [version]'18.5') }
    }
}
function Read-VsixSonar([object[]]$manifests, [string]$where) {   # SonarSource extensions among VSIX manifests, from each manifest's own identity
    foreach ($m in $manifests) {
        $t = try { [IO.File]::ReadAllText($m.FullName) } catch { '' }
        $id = [regex]::Match($t, '<Identity\b[^>]*>').Value
        if ($id -match 'Publisher="SonarSource"' -and $id -match 'Version="([^"]+)"') { "$([regex]::Match($t, '<DisplayName>([^<]+)<').Groups[1].Value) $($Matches[1]) ($where)" }
    }
}
# SonarQube for IDE on this machine, read from each extension's own manifest: Visual Studio's per-user extension folders
# (one per instance: 17.0_<id> is Visual Studio 2022, 18.0_<id> is 2026), the machine-wide folder of each Visual Studio
# installation, and VS Code's extension folders. Whether an extension is enabled is kept in the IDE's private settings and
# is not read. The machine-wide scan takes seconds, so its result is kept until that folder changes; -CachedOnly (issue)
# uses the kept result and never scans.
function Get-SonarIdeExtension([switch]$CachedOnly) {
    $vs = foreach ($m in @(Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Microsoft\VisualStudio\*\Extensions\*\extension.vsixmanifest') -File -ErrorAction SilentlyContinue)) {
        Read-VsixSonar @($m) "Visual Studio instance $($m.Directory.Parent.Parent.Name)"
    }
    $cacheFile = Join-Path $AkzoHome 'cache\vs-machine-extensions.json'
    $cached = @((Read-JsonOrRecover $cacheFile).data.instances | Where-Object { $_ })
    $machine = if ($CachedOnly) { @($cached | ForEach-Object { $_.sonar }) } else {
        $rows = @(foreach ($i in @(Get-VisualStudioInstance)) {
                $dir = Join-Path $i.path 'Common7\IDE\Extensions'
                $ticks = if (Test-Path -LiteralPath $dir) { (Get-Item -LiteralPath $dir).LastWriteTimeUtc.Ticks } else { 0 }
                $hit = $cached | Where-Object { $_.path -eq $dir -and $_.ticks -eq $ticks } | Select-Object -First 1
                $found = if ($hit) { @($hit.sonar) } else { @(Read-VsixSonar @(Get-ChildItem (Join-Path $dir '*\extension.vsixmanifest'), (Join-Path $dir '*\*\extension.vsixmanifest'), (Join-Path $dir '*\*\*\extension.vsixmanifest') -File -ErrorAction SilentlyContinue) "$($i.name), all users") }
                [pscustomobject]@{ path = $dir; ticks = $ticks; sonar = @($found | Where-Object { $_ }) } })
        try { New-Item -ItemType Directory -Force (Split-Path $cacheFile) | Out-Null; Write-TextAtomic $cacheFile ([pscustomobject]@{ instances = $rows } | ConvertTo-Json -Depth 4) } catch { }   # optional: costs the next call a scan
        @($rows | ForEach-Object { $_.sonar })
    }
    $code = foreach ($d in '.vscode', '.vscode-insiders') {
        @(Get-ChildItem (Join-Path $env:USERPROFILE "$d\extensions") -Directory -Filter 'sonarsource.sonarlint-vscode-*' -ErrorAction SilentlyContinue | ForEach-Object { if ($_.Name -match '-(\d+(?:\.\d+)+)') { [version]$Matches[1] } } | Sort-Object -Descending)[0] |
            Where-Object { $_ } | ForEach-Object { "SonarQube for IDE $_ ($(if ($d -eq '.vscode') { 'VS Code' } else { 'VS Code Insiders' }))" }
    }
    @(@($vs) + @($machine) + @($code) | Where-Object { $_ })
}

# Visual Studio's Error List through the IDE's automation model (EnvDTE: the documented out-of-process interface, bound
# through the interop assembly the installation ships), from the running instance whose open solution is inside the
# repository. Every severity is shown for the read and the developer's filters are put back. -Open (sonar -Update): each
# file not open yet is opened (ItemOperations.OpenFile), unsaved ones are saved (Document.Save: SonarQube for IDE analyzes
# on open, edit, and save, not on build), the active document is activated again, and the list is read until the rows of
# every opened or saved file changed and then held still (5 to 15 seconds: as long as the first rows took), at most 30
# seconds. A file's rows changing then,
# or since the previous read (kept in maps\<repo>\ide-diagnostics.json), is the evidence that an analysis ran. Each row
# has its text, file, line, column, severity, and project; the interface has no rule id, diagnostic source, or suppression state.
# shortcut: with several running instances of one Visual Studio version only the one Windows registered first is reachable (no native ROT walk); the result names its solution.
function Get-IdeDiagnostics([string]$repoId, [string]$root, [string[]]$files, [switch]$Open, [switch]$Active) {
    $res = [ordered]@{ status = 'UNAVAILABLE'; detail = ''; solution = ''; active = ''; files = [ordered]@{}; rows = @() }
    if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') { $res.detail = "PowerShell runs in $($ExecutionContext.SessionState.LanguageMode) mode, which blocks the IDE's automation interface (an organizational setting; not worked around)"; return [pscustomobject]$res }
    if ($PSVersionTable.PSEdition -eq 'Core') { $res.detail = "PowerShell $($PSVersionTable.PSVersion) runs on .NET, which cannot attach to a running Visual Studio (no GetActiveObject): run the helper with Windows PowerShell (powershell.exe), as the agent does"; return [pscustomobject]$res }
    $com = { param([scriptblock]$call)   # a busy IDE rejects automation calls (RPC_E_CALL_REJECTED, RPC_E_SERVERCALL_RETRYLATER): retry for up to 30 seconds
        for ($i = 0; ; $i++) {
            try { return & $call } catch {
                $e = $_.Exception; while ($e -and $e -isnot [Runtime.InteropServices.COMException]) { $e = $e.InnerException }
                if (-not $e -or $e.HResult -notin -2147418111, -2147417846 -or $i -ge 60) { throw }
                Start-Sleep -Milliseconds 500
            }
        }
    }
    $base = $root.TrimEnd('\') + '\'; $seen = @(); $dte = $null; $sln = ''
    foreach ($v in '18.0', '17.0') {   # Visual Studio 2026, 2022
        try { $d = [Runtime.InteropServices.Marshal]::GetActiveObject("VisualStudio.DTE.$v") } catch { continue }
        $sln = "$(& $com { $d.Solution.FullName })"
        if ($sln.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)) { $dte = $d; break }
        $seen += "Visual Studio $v has $(if ($sln) { $sln } else { 'no solution' }) open"
    }
    if (-not $dte) { $res.detail = $(if ($seen) { "no running Visual Studio has a solution of this repository open ($($seen -join '; '))" } else { 'no running Visual Studio is reachable (not running, or running elevated or as another user)' }); return [pscustomobject]$res }
    $res.solution = $sln
    $exe = "$(& $com { $dte.FullName })"
    if (-not $exe) { $res.detail = 'Visual Studio is still starting (it does not name its installation yet): run again in a moment'; return [pscustomobject]$res }
    $asmPath = Join-Path (Split-Path $exe) 'PublicAssemblies\Microsoft.VisualStudio.Interop.dll'
    if (-not (Test-Path -LiteralPath $asmPath)) { $res.detail = "the IDE's automation interop assembly is missing ($asmPath)"; return [pscustomobject]$res }
    $asm = [Reflection.Assembly]::LoadFrom($asmPath)
    $T = @{}; foreach ($n in 'EnvDTE80.DTE2', 'EnvDTE80.ToolWindows', 'EnvDTE80.ErrorList', 'EnvDTE80.ErrorItems', 'EnvDTE80.ErrorItem') { $T[$n] = $asm.GetType($n, $true) }
    $get = { param($obj, [string]$type, [string]$name) $T[$type].GetProperty($name).GetValue($obj, $null) }   # DTE2 members are not in the type information PowerShell binds to
    $el = & $com { & $get (& $get $dte 'EnvDTE80.DTE2' 'ToolWindows') 'EnvDTE80.ToolWindows' 'ErrorList' }
    $hidden = @(foreach ($f in 'ShowErrors', 'ShowWarnings', 'ShowMessages') { if (-not (& $com { & $get $el 'EnvDTE80.ErrorList' $f })) { $f } })
    $act = try { & $com { $dte.ActiveDocument } } catch { $null }
    if ($act) { $res.active = "$(& $com { $act.FullName })" }
    if ($Active -and -not $files.Count) {
        if (-not $res.active.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)) { $res.detail = "the active document is not in this repository ($(if ($res.active) { $res.active } else { 'none' }))"; return [pscustomobject]$res }
        $files = @($res.active)
    }
    $want = @{}; foreach ($f in $files) { $want[$f.ToLowerInvariant()] = 1 }
    $read = { & $com {
            $items = $T['EnvDTE80.ErrorList'].GetProperty('ErrorItems').GetValue($el, $null); $item = $T['EnvDTE80.ErrorItems'].GetMethod('Item')   # not through a script block: its output would be unrolled
            for ($i = 1; $i -le [int](& $get $items 'EnvDTE80.ErrorItems' 'Count'); $i++) {
                $e = $item.Invoke($items, @([object]$i)); $fn = "$(& $get $e 'EnvDTE80.ErrorItem' 'FileName')"
                if (-not $fn.StartsWith($base, [StringComparison]::OrdinalIgnoreCase) -or ($want.Count -and -not $want.ContainsKey($fn.ToLowerInvariant()))) { continue }
                $lvl = "$(& $get $e 'EnvDTE80.ErrorItem' 'ErrorLevel')"
                [pscustomobject][ordered]@{ file = $fn; line = [int](& $get $e 'EnvDTE80.ErrorItem' 'Line'); column = [int](& $get $e 'EnvDTE80.ErrorItem' 'Column')
                    severity = $(if ($lvl -like '*High') { 'error' } elseif ($lvl -like '*Medium') { 'warning' } else { 'info' })
                    text = "$(& $get $e 'EnvDTE80.ErrorItem' 'Description')"; project = "$(& $get $e 'EnvDTE80.ErrorItem' 'Project')" }
            } } }
    $sig = { param($rows) $m = @{}   # file -> its rows as sorted 'severity|text' lines: lines move with edits, text changes only with an analysis; kept in memory, so redacted
        foreach ($x in $rows) { $k = $x.file.ToLowerInvariant(); if (-not $m.ContainsKey($k)) { $m[$k] = New-Object Collections.Generic.List[string] }; $m[$k].Add((Protect-Text "$($x.severity)|$($x.text)")) }
        $o = @{}; foreach ($k in $m.Keys) { $o[$k] = (@($m[$k]) | Sort-Object) -join "`n" }; $o }
    $differs = { param($a, $b) [bool]@(@($a.Keys) + @($b.Keys) | Where-Object { $a[$_] -ne $b[$_] }).Count }
    try {
        foreach ($f in $hidden) { $null = & $com { $T['EnvDTE80.ErrorList'].GetProperty($f).SetValue($el, $true, $null) } }
        $first = & $sig @(& $read)
        if ($hidden.Count) { for ($i = 0; $i -lt 5; $i++) { Start-Sleep -Seconds 1; $again = & $sig @(& $read); if (-not (& $differs $first $again)) { break }; $first = $again } }   # the list refills after a filter change
        $touched = @()
        if ($Open) {
            foreach ($f in $files) {
                $st = [ordered]@{ opened = $false; saved = $false }
                if (Test-Path -LiteralPath $f -PathType Leaf) {
                    if (-not (& $com { $dte.ItemOperations.IsFileOpen($f) })) { $null = & $com { $dte.ItemOperations.OpenFile($f) }; $st.opened = $true }
                    $doc = try { & $com { $dte.Documents.Item($f) } } catch { $null }
                    if ($doc -and -not (& $com { $doc.Saved })) { $null = & $com { $doc.Save() }; $st.saved = $true }
                    if ($st.opened -or $st.saved) { $touched += $f.ToLowerInvariant() }
                } else { $st.note = 'not on disk' }
                $res.files[$f] = $st
            }
            if ($act -and $touched.Count) { try { $null = & $com { $act.Activate() } } catch { } }   # the developer's document stays in front
        }
        $now = $first; $moved = @{}
        if ($touched.Count) {
            $start = Get-Date; $still = $start; $quiet = 5
            while (((Get-Date) - $start).TotalSeconds -lt 30) {
                Start-Sleep -Milliseconds 1500
                $next = & $sig @(& $read)
                if (& $differs $now $next) { $now = $next; $still = Get-Date }
                foreach ($k in $touched) { if ($now[$k] -ne $first[$k] -and -not $moved[$k]) { $moved[$k] = $true; $quiet = [math]::Min(15, [math]::Max($quiet, ((Get-Date) - $start).TotalSeconds)) } }
                # compiler rows come first and analyzer rows later; a busy IDE is slower at both, so it gets a longer quiet time
                if (-not @($touched | Where-Object { -not $moved[$_] }).Count -and ((Get-Date) - $still).TotalSeconds -ge $quiet) { break }
            }
        }
        $res.rows = @(& $read); $now = & $sig $res.rows
        if ($act -and $touched.Count) {   # an opened document can take the front after the first activation: check again once the IDE settled
            for ($i = 0; $i -lt 3 -and "$(& $com { $dte.ActiveDocument.FullName })" -ne $res.active; $i++) { $null = & $com { $act.Activate() }; Start-Sleep -Milliseconds 500 }
        }
    } finally {
        foreach ($f in $hidden) { try { $null = & $com { $T['EnvDTE80.ErrorList'].GetProperty($f).SetValue($el, $false, $null) } } catch { } }
    }
    # Each file against the previous read: findings resolved and added (by text, so moved lines are not changes).
    $snapFile = Join-Path $AkzoHome "maps\$repoId\ide-diagnostics.json"
    $keep = @{}; $old = (Read-JsonOrRecover $snapFile).data
    if ($old.files) { foreach ($p in $old.files.PSObject.Properties) { $keep[$p.Name] = @($p.Value) } }
    $minus = { param([string[]]$a, [string[]]$b) $left = New-Object Collections.Generic.List[string]; foreach ($x in $b) { $left.Add($x) }; @(foreach ($x in $a) { if (-not $left.Remove($x)) { $x } }) }
    foreach ($f in $files) {
        $k = $f.ToLowerInvariant(); $st = if ($res.files.Contains($f)) { $res.files[$f] } else { [ordered]@{ opened = $false; saved = $false } }
        $cur = @(if ($now[$k]) { $now[$k] -split "`n" })
        $st.diagnostics = $cur.Count
        if ($keep.ContainsKey($k)) { $st.resolved = @(& $minus $keep[$k] $cur); $st.added = @(& $minus $cur $keep[$k]) }
        $st.analysis = if ($moved[$k] -or ($keep.ContainsKey($k) -and ($st.resolved.Count -or $st.added.Count))) { 'ANALYZED' } elseif ($st.opened -or $st.saved) { 'OPENED' } elseif (& $com { $dte.ItemOperations.IsFileOpen($f) }) { 'READ' } else { 'NOT_OPEN' }
        $res.files[$f] = $st; $keep[$k] = $cur
    }
    if ($files.Count) { try { New-Item -ItemType Directory -Force (Split-Path $snapFile) | Out-Null; Write-TextAtomic $snapFile ([pscustomobject]@{ at = (Get-Date).ToString('s'); files = $keep } | ConvertTo-Json -Depth 4) } catch { } }   # optional: without it the next read has no comparison
    $res.status = 'OK'
    $res.detail = "Visual Studio $(& $com { $dte.Version }) $(& $com { $dte.Edition }), solution $sln$(if ($hidden.Count) { "; the Error List hid $(($hidden -replace '^Show', '').ToLowerInvariant() -join ' and ') (shown for this read, then hidden again)" })"
    [pscustomobject]$res
}

function Get-SonarSetup($r, [switch]$Brief, [switch]$Binding) {   # -Brief: no machine tools (slow Get-Command calls), coverage diagnosis, or Connected Mode (-Binding adds it), as `task` on every call
    $root = $r.path
    # Files that can name Sonar settings, analyzers, or coverage tools. When the architecture sync just ran, its file list is
    # reused (no extra git call); otherwise git is asked.
    $sonarFiles = '(^|/)sonar-project\.properties$|\.(cs|vb)proj$|(^|/)Directory\.(Build|Packages)\.props$|\.ya?ml$|(^|/)Jenkinsfile$|(^|/)package\.json$|(^|/)\.editorconfig$|\.globalconfig$|\.ruleset$|\.runsettings$'
    $all = if ($script:LastBlobs -and $script:LastBlobs.Count) { @($script:LastBlobs.Keys) } else { @(Invoke-Quiet git -C $root -c core.quotepath=off ls-files -co --exclude-standard) }
    $files = @($all | Where-Object { $_ -match $sonarFiles -and $_ -notmatch '(^|/)(node_modules|bin|obj|dist)/' })
    $read = { param($f) try { [IO.File]::ReadAllText((Join-Path $root $f)) } catch { '' } }
    $props = [ordered]@{}
    $propFile = $files | Where-Object { $_ -match '(^|/)sonar-project\.properties$' } | Sort-Object Length | Select-Object -First 1
    if ($propFile) {
        foreach ($l in (& $read $propFile) -split '\r?\n') { if ($l -match '^\s*(sonar\.[\w.]+)\s*[=:]\s*(.*)$') { $props[$Matches[1]] = $Matches[2].Trim() } }
    }
    $key = $props['sonar.projectKey']; $org = $props['sonar.organization']
    $pipelines = @(); $analyzers = [ordered]@{}; $coverage = [ordered]@{}; $rules = @()
    # Coverage import: the report formats the tests produce (pipelines, run settings, projects) and the report paths Sonar reads.
    $produced = New-Object Collections.Generic.List[string]; $imported = New-Object Collections.Generic.List[string]
    $covEx = New-Object Collections.Generic.List[string]; $tests = New-Object Collections.Generic.List[object]; $central = $false
    $scanCov = { param($f, $t)
        foreach ($m in [regex]::Matches($t, '(?i)(sonar\.cs\.(?:opencover|vscoveragexml|dotcover)\.reportsPaths|sonar\.coverageReportPaths)\s*[=:]\s*["'']?([^"''\s]+)')) { $imported.Add("$($m.Groups[1].Value)=$($m.Groups[2].Value) ($f)") }
        if ($t -match '(?i)--collect[:\s]+"?XPlat Code Coverage') { $produced.Add("$(if ($t -match '(?i)Configuration\.Format=([\w,]+)') { $Matches[1] } elseif ($t -match '--settings') { 'format from the run settings' } else { 'cobertura' }) (XPlat Code Coverage in $f)") }
        if ($t -match '(?i)--collect[:\s]+"?Code Coverage') { $produced.Add("vscoverage (Code Coverage in $f)") }
        foreach ($m in [regex]::Matches($t, '(?i)<Format>([^<]+)</Format>|CoverletOutputFormat[>=]"?([\w,]+)')) { $produced.Add("$(($m.Groups[1].Value + $m.Groups[2].Value).ToLowerInvariant()) ($f)") }
        foreach ($m in [regex]::Matches($t, '(?i)<(Exclude|ExcludeByFile|ExcludeByAttribute)>([^<]+)<')) { $covEx.Add("$($m.Groups[1].Value)=$($m.Groups[2].Value) ($f)") }
    }
    foreach ($f in $files) {
        $leaf = $f.Substring($f.LastIndexOf('/') + 1)
        if ($f -match '\.ya?ml$' -or $leaf -eq 'Jenkinsfile') {
            $t = & $read $f
            if (-not $Brief) { & $scanCov $f $t }
            if ($t -match '(?i)SonarQube|SonarCloud|sonarscanner|sonar-scanner|sonar\.projectKey') {
                $pipelines += $f
                if (-not $key -and $t -match '(?:projectKey:\s*|/k:|sonar\.projectKey=)["'']?([\w.:-]+)') { $key = $Matches[1] }
                if (-not $org -and $t -match '(?:organization:\s*|/o:|sonar\.organization=)["'']?([\w.-]+)') { $org = $Matches[1] }
            }
        } elseif ($f -match '\.(cs|vb)proj$' -or $leaf -match '^Directory\.(Build|Packages)\.props$') {
            $t = & $read $f
            foreach ($m in [regex]::Matches($t, '(?i)Include="(SonarAnalyzer\.[\w.]+|coverlet\.[\w.]+|Microsoft\.Testing\.Extensions\.CodeCoverage|Microsoft\.CodeCoverage)"')) {
                $n = $m.Groups[1].Value
                if ($n -like 'SonarAnalyzer*') { if (-not $analyzers[$n]) { $analyzers[$n] = $f } } elseif (-not $coverage[$n]) { $coverage[$n] = $f }
            }
            if ($t -match '(?i)<TreatWarningsAsErrors>\s*true') { $rules += "$f (TreatWarningsAsErrors)" }
            if ($t -match '(?i)<CodeAnalysisRuleSet>') { $rules += "$f (CodeAnalysisRuleSet)" }
            if (-not $Brief) {
                & $scanCov $f $t
                if ($t -match '(?i)Microsoft\.NET\.Test\.Sdk|<IsTestProject>\s*true') { $tests.Add([pscustomobject]@{ f = $f; cov = $t -match '(?i)coverlet\.(collector|msbuild)|Microsoft\.Testing\.Extensions\.CodeCoverage' }) }
                if ($leaf -like 'Directory.*' -and $t -match '(?i)coverlet\.') { $central = $true }   # added to every test project centrally
            }
        } elseif ($leaf -eq 'package.json') {
            $t = & $read $f
            if ($t -match '"eslint-plugin-sonarjs"' -and -not $analyzers['eslint-plugin-sonarjs']) { $analyzers['eslint-plugin-sonarjs'] = $f }
            foreach ($n in 'karma-coverage', 'nyc', 'c8', '@vitest/coverage-v8', 'jest') { if ($t -match "`"$([regex]::Escape($n))`"" -and -not $coverage[$n]) { $coverage[$n] = $f } }
        } elseif ($leaf -like '*.runsettings') { if (-not $Brief) { & $scanCov $f (& $read $f) } }
        elseif ($leaf -ne 'sonar-project.properties') { $rules += $f }   # .editorconfig, .globalconfig, rule sets
    }
    if ($propFile -and -not $Brief) { & $scanCov $propFile (& $read $propFile) }
    $hostUrl = if ($env:SONAR_HOST_URL) { $env:SONAR_HOST_URL } elseif ($props['sonar.host.url']) { $props['sonar.host.url'] } elseif ($org) { 'https://sonarcloud.io' } else { '' }
    $tokenSet = [bool]$env:SONAR_TOKEN
    $tool = { param($n) [bool](Get-Command $n -ErrorAction SilentlyContinue) }
    $tools = if ($Brief) { 'run the sonar command to detect' } else {
        [pscustomobject][ordered]@{ sonarCli = (& $tool 'sonar'); dotnetSonarscanner = (& $tool 'dotnet-sonarscanner'); sonarScanner = (& $tool 'sonar-scanner'); ideExtension = @(Get-SonarIdeExtension) } }
    # Connected Mode binding shared in the repository: .sonarlint\<solution>.json (Visual Studio; *.slconfig before it),
    # .sonarlint\connectedMode.json or the sonarlint.connectedMode.project setting (VS Code). One kept only in the IDE is not read.
    $bind = @(foreach ($f in @($all | Where-Object { $_ -match '(^|/)\.sonarlint/[^/]+\.(json|slconfig)$' }) + '.vscode/settings.json') {
            $rx = if ($f -like '.vscode/*') { '(?s)"sonarlint\.connectedMode\.project"\s*:\s*\{[^}]*?"projectKey"\s*:\s*"([^"]+)"' } else { '(?i)"projectKey"\s*:\s*"([^"]+)"' }
            if ((& $read $f) -match $rx) { "$($Matches[1]) ($f)" } })
    $same = @($bind | Where-Object { $key -and $_ -like "$key (*" })
    $o = [ordered]@{
        projectKey = "$key"; organization = "$org"; host = $hostUrl; tokenSet = $tokenSet
        serverQueries = [bool]($key -and $hostUrl -and $tokenSet)
        propertiesFile = "$propFile"; pipelines = @($pipelines)
        analyzers = @($analyzers.Keys | ForEach-Object { "$_ ($($analyzers[$_]))" })
        coverageTools = @($coverage.Keys | ForEach-Object { "$_ ($($coverage[$_]))" })
        ruleConfig = @($rules | Select-Object -First 15)
        exclusions = @('sonar.exclusions', 'sonar.coverage.exclusions', 'sonar.cpd.exclusions', 'sonar.test.inclusions' | Where-Object { $props[$_] } | ForEach-Object { "$_=$($props[$_])" })
        tools = $tools
    }
    if (-not $Brief -or $Binding) {
        $o.connectedMode = [pscustomobject][ordered]@{
            status = $(if ($same.Count) { 'MATCH' } elseif ($bind.Count -and $key) { 'MISMATCH' } else { 'NOT VERIFIED' }); binding = $bind
            detail = $(if ($same.Count) { "bound to $key, the repository's Sonar project" } elseif ($bind.Count -and $key) { "bound to another project than ${key}: rebind Connected Mode in the IDE" } elseif ($bind.Count) { 'the repository names no Sonar project key to compare with' } else { 'no binding shared in the repository (.sonarlint, .vscode\settings.json); one kept only in the IDE is not read' }) }
    }
    if (-not $Brief) {
        $fmt = ($produced -join ' ').ToLowerInvariant()
        $fits = @{ opencover = 'opencover'; vscoveragexml = 'vscoverage|\bxml\b'; dotcover = 'dotcover'; coverageReportPaths = 'sonarqube|generic' }
        $ok = @($imported | Where-Object { $i = $_; @($fits.Keys | Where-Object { $i -match $_ -and $fmt -match $fits[$_] }).Count })
        $st = if (-not $imported.Count -or -not $produced.Count) { 'NOT_FOUND' } elseif ($ok.Count) { 'CONSISTENT' } else { 'MISMATCH' }
        $o.coverageImport = [pscustomobject][ordered]@{ status = $st; produced = @($produced | Select-Object -Unique); imported = @($imported | Select-Object -Unique)
            testProjectsWithoutCollector = @(if (-not $central -and $fmt -match 'xplat') { $tests | Where-Object { -not $_.cov } | ForEach-Object { $_.f } })
            coverageExclusions = @($covEx | Select-Object -Unique)
            notes = @(
                if ($st -eq 'MISMATCH') { 'Sonar reads a report format the tests do not produce, so SonarCloud gets no coverage from them: correct the format or the report path; more tests do not change it.' }
                if (-not $imported.Count) { 'No Sonar coverage report path in this repository (sonar.cs.opencover.reportsPaths or similar); it may be set in a pipeline template elsewhere: find it before adding tests for coverage.' }
                if ($imported.Count -and -not $produced.Count) { 'No coverage collection found in the pipelines, run settings, or projects of this repository.' }
                if (@($covEx | Where-Object { $_ -match '^ExcludeByAttribute=.*CompilerGenerated' }).Count) { 'ExcludeByAttribute names CompilerGenerated: the bodies of async and iterator methods (compiler-generated state machines) are left out of coverage.' }) }
    }
    [pscustomobject]$o
}

function Join-Ranges([int[]]$n) {   # 3,4,5,9 -> "3-5, 9"
    $out = @(); $n = @($n | Sort-Object -Unique)
    for ($i = 0; $i -lt $n.Count; $i++) {
        $s = $n[$i]; while ($i + 1 -lt $n.Count -and $n[$i + 1] -eq $n[$i] + 1) { $i++ }
        $out += $(if ($n[$i] -eq $s) { "$s" } else { "$s-$($n[$i])" })
    }
    $out -join ', '
}

# Read-only Sonar Web API call. The token comes from SONAR_TOKEN and goes only into the request header.
# The token is sent only over https (a loopback server is exempt, for local testing) and never follows a redirect.
function Get-HostIssue([string]$url) {
    try { $u = [Uri]$url } catch { return "'$url' is not a valid URL" }
    if ($u.Scheme -eq 'https') { return '' }
    if ($u.Scheme -eq 'http' -and $u.Host -in 'localhost', '127.0.0.1', '[::1]', '::1') { return '' }
    "the token would travel unencrypted ($($u.Scheme) to $($u.Host)); use https"
}
function Invoke-SonarApi([string]$hostUrl, [string]$apiPath) {
    $issue = Get-HostIssue $hostUrl; if ($issue) { throw "Refused: $issue." }
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($env:SONAR_TOKEN):"))
    Invoke-RestMethod -Method Get -Uri ($hostUrl.TrimEnd('/') + '/' + $apiPath) -Headers @{ Authorization = "Basic $auth" } -UseBasicParsing -TimeoutSec 60 -MaximumRedirection 0
}

# Lines added or changed against HEAD per repo-relative path (tracked edits and untracked files).
function Get-ChangedLines([string]$root, [string]$against = 'HEAD') {   # working tree against HEAD, or against a commit (review -Base)
    $map = @{}; $cur = $null
    foreach ($l in @(Invoke-Quiet git -C $root -c core.quotepath=off diff -U0 --no-color --no-ext-diff $against)) {
        if ($l -match '^\+\+\+ (.+)$') {
            $cur = if ($Matches[1] -eq '/dev/null') { $null } else { $Matches[1] -replace '^b/', '' }
            if ($cur -and -not $map.ContainsKey($cur)) { $map[$cur] = New-Object Collections.Generic.List[int] }
        } elseif ($cur -and $l -match '^@@ -\S+ \+(\d+)(?:,(\d+))? @@') {
            $count = if ($Matches[2]) { [int]$Matches[2] } else { 1 }
            for ($i = 0; $i -lt $count; $i++) { $map[$cur].Add([int]$Matches[1] + $i) }
        }
    }
    foreach ($u in @(Invoke-Quiet git -C $root -c core.quotepath=off ls-files --others --exclude-standard)) {
        $n = @(Get-Content -LiteralPath (Join-Path $root $u) -ErrorAction SilentlyContinue).Count
        $lines = New-Object Collections.Generic.List[int]; for ($i = 1; $i -le $n; $i++) { $lines.Add($i) }
        $map[$u] = $lines
    }
    $map
}

# Per-file line hits and partly covered branch lines from Cobertura XML, OpenCover XML (the format SonarCloud imports for
# C#), or LCOV, keyed by normalized full path.
function Read-CoverageReport([string]$file, [string]$repoRoot) {
    $result = @{}
    $norm = { param($p) ($p -replace '\\', '/').ToLowerInvariant() }
    $entry = { param($p) $k = & $norm $p; if (-not $result.ContainsKey($k)) { $result[$k] = @{ hits = @{}; partial = @{} } }; $result[$k] }
    $text = [IO.File]::ReadAllText($file)
    if ($text -match '<CoverageSession\b') {
        foreach ($mod in ([xml]$text).SelectNodes('//Module')) {
            $paths = @{}; foreach ($f in $mod.SelectNodes('Files/File')) { $paths[$f.GetAttribute('uid')] = $f.GetAttribute('fullPath') }
            foreach ($p in $mod.SelectNodes('.//SequencePoint|.//BranchPoint')) {
                $full = $paths[$p.GetAttribute('fileid')]; if (-not $full) { continue }
                $e = & $entry $full; $n = [int]$p.GetAttribute('sl'); $h = [long]$p.GetAttribute('vc')
                if ($p.LocalName -eq 'BranchPoint') { if ($h -eq 0) { $e.partial[$n] = $true } }
                elseif (-not $e.hits.ContainsKey($n) -or $e.hits[$n] -lt $h) { $e.hits[$n] = $h }
            }
        }
    } elseif ($text -match '^\s*(<\?xml|<coverage)') {
        $xml = [xml]$text
        $sources = @($xml.SelectNodes('//sources/source') | ForEach-Object { $_.InnerText.Trim() }) + @($repoRoot)
        foreach ($c in $xml.SelectNodes('//class')) {
            $fn = $c.GetAttribute('filename')
            $full = if ([IO.Path]::IsPathRooted($fn)) { $fn } else { $hit = $sources | Where-Object { $_ -and (Test-Path -LiteralPath (Join-Path $_ $fn)) } | Select-Object -First 1; if ($hit) { Join-Path $hit $fn } else { $fn } }
            $e = & $entry $full
            foreach ($ln in $c.SelectNodes('lines/line')) {
                $n = [int]$ln.GetAttribute('number'); $h = [long]$ln.GetAttribute('hits')
                if (-not $e.hits.ContainsKey($n) -or $e.hits[$n] -lt $h) { $e.hits[$n] = $h }
                if ($ln.GetAttribute('branch') -eq 'true' -and $ln.GetAttribute('condition-coverage') -match '\((\d+)/(\d+)\)' -and [int]$Matches[1] -lt [int]$Matches[2]) { $e.partial[$n] = $true }
            }
        }
    } else {
        $e = $null; $branches = @{}
        foreach ($l in $text -split '\r?\n') {
            if ($l -match '^SF:(.+)$') { $p = $Matches[1].Trim(); $e = & $entry $(if ([IO.Path]::IsPathRooted($p)) { $p } else { Join-Path $repoRoot $p }); $branches = @{} }
            elseif ($e -and $l -match '^DA:(\d+),(\d+)') { $n = [int]$Matches[1]; $h = [int]$Matches[2]; if (-not $e.hits.ContainsKey($n) -or $e.hits[$n] -lt $h) { $e.hits[$n] = $h } }
            elseif ($e -and $l -match '^BRDA:(\d+),[^,]*,[^,]*,(\S+)') { $n = [int]$Matches[1]; if (-not $branches[$n]) { $branches[$n] = @(0, 0) }; $branches[$n][1]++; if ($Matches[2] -ne '-' -and [int]$Matches[2] -gt 0) { $branches[$n][0]++ } }
            elseif ($e -and $l -eq 'end_of_record') { foreach ($n in $branches.Keys) { if ($branches[$n][0] -lt $branches[$n][1]) { $e.partial[$n] = $true } }; $e = $null }
        }
    }
    $result
}

# ---- Corporate security (G8) ------------------------------------------------------------------------------------
# Authorization evidence comes from an administrator policy (machine policy.json) or the optional developer statement
# ('authorize'). Missing evidence does not block ordinary tasks; explicit restrictions still fail closed.
# A policy counts as managed only when the current user cannot write it; everything the developer
# records is reported as their statement, never as corporate approval.
$MachinePolicy = if ($env:AKZO_AGENT_MACHINE_POLICY) { $env:AKZO_AGENT_MACHINE_POLICY } else { Join-Path $env:ProgramData 'AkzoAgent\policy.json' }
$UserPolicy = Join-Path $AkzoHome 'policy.json'
$AuthFile = Join-Path $AkzoHome 'authorizations.json'
$Classifications = 'public', 'internal', 'confidential', 'restricted'

function Test-UserCanWrite([string]$file) {
    try { $s = [IO.File]::Open($file, 'Open', 'Write', 'ReadWrite'); $s.Dispose(); $true } catch [UnauthorizedAccessException] { $false } catch { $true }
}

function Read-Policy {
    foreach ($p in @($MachinePolicy, $UserPolicy)) {
        if (-not (Test-Path -LiteralPath $p)) { continue }
        try { $d = Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json }
        catch { return [pscustomobject]@{ path = $p; data = $null; managed = $false; error = "unreadable policy file: $($_.Exception.Message)" } }
        return [pscustomobject]@{ path = $p; data = $d; managed = -not (Test-UserCanWrite $p); error = '' }
    }
    [pscustomobject]@{ path = ''; data = $null; managed = $false; error = '' }
}

function Read-Authorizations {   # the developer's recorded statements; unreadable -> set aside, treated as none (fail closed)
    $load = Read-JsonOrRecover $AuthFile
    if ($load.data) { $load.data } else { [pscustomobject]@{ schemaVersion = 1; repos = [pscustomobject]@{} } }
}

function Get-HostName([string]$url) { try { ([Uri]$url).Host.ToLowerInvariant() } catch { '' } }

function Get-Authorization($r) {
    $pol = Read-Policy
    $att = (Read-Authorizations).repos.$($r.id)
    $rp = if ($pol.data) { $pol.data.repositories.$($r.id) } else { $null }
    $def = if ($pol.data) { $pol.data.defaults } else { $null }
    $a = [ordered]@{
        repo = $r.id; status = 'NOT_AUTHORIZED'; source = ''; managed = $false; reference = ''; policyReference = "$($pol.data.reference)"; policyPath = $pol.path
        classification = "$(if ($rp.classification) { $rp.classification } elseif ($att.classification) { $att.classification } elseif ($def.classification) { $def.classification } else { 'unclassified' })"
        memory = "$(if ($rp.memory) { $rp.memory } elseif ($def.memory) { $def.memory } else { 'allowed' })"
        retentionDays = $(if ($rp.retentionDays) { [int]$rp.retentionDays } elseif ($def.retentionDays) { [int]$def.retentionDays } else { $null })
        approvedModels = @($pol.data.approvedModels | Where-Object { $_ }); model = "$($att.model)"
        allowedHosts = @(); reason = ''; recordedBy = "$($att.recordedBy)"; recordedAt = "$($att.recordedAt)"
    }
    $hosts = @(@($pol.data.allowedHosts) + @($rp.allowedHosts) | Where-Object { $_ })
    $attestOk = -not ($pol.data -and $pol.data.allowDeveloperAttestation -eq $false)
    if ($attestOk) { $hosts += @($att.allowedHosts | Where-Object { $_ }) }
    $a.allowedHosts = @($hosts | ForEach-Object { "$_".ToLowerInvariant() } | Select-Object -Unique)
    if ($pol.error) { $a.status = 'BLOCKED'; $a.reason = "$($pol.error) ($($pol.path)); fix or remove it, processing stays blocked until then"; return [pscustomobject]$a }
    if ($rp) {
        if ($rp.authorized -ne $true) { $a.status = 'BLOCKED'; $a.reason = "policy does not authorize this repository$(if ($rp.reason) { ": $($rp.reason)" })"; $a.source = $pol.path; return [pscustomobject]$a }
        $a.status = 'AUTHORIZED'; $a.source = $pol.path; $a.managed = $pol.managed; $a.reference = "$($rp.reference)"
    } elseif ($att -and $attestOk) {
        $a.status = 'ATTESTED'; $a.source = $AuthFile; $a.reference = "$($att.reference)"
        if ($a.classification -eq 'restricted') { $a.status = 'BLOCKED'; $a.reason = 'restricted data needs an administrator policy that lists this repository; a developer statement is not enough' }
    } else {
        if (-not $attestOk) {
            $a.status = 'BLOCKED'; $a.reason = "the policy ($($pol.path)) requires an administrator to list this repository"
        } else {
            $a.status = 'NOT_REQUIRED'; $a.reason = 'no repository approval record required; continue with the requested task'
            if ($a.classification -eq 'restricted') { $a.status = 'BLOCKED'; $a.reason = 'restricted data needs an administrator policy that lists this repository' }
        }
    }
    if ($a.status -in 'AUTHORIZED', 'ATTESTED', 'NOT_REQUIRED' -and $a.approvedModels.Count -and $a.model -and -not ($a.approvedModels -contains $a.model)) {
        $a.status = 'BLOCKED'; $a.reason = "model '$($a.model)' is not in the policy's approvedModels ($($a.approvedModels -join ', '))"
    }
    [pscustomobject]$a
}

function Get-PreflightRefusal($auth) {   # '' when processing may go ahead, else the status the caller reports
    if ($auth.status -in 'AUTHORIZED', 'ATTESTED', 'NOT_REQUIRED') { return '' }
    'BLOCKED_BY_POLICY'
}

function Assert-Preflight($r) {   # for commands without a JSON status: refuse with the authorization that is missing
    $auth = Get-Authorization $r
    $refusal = Get-PreflightRefusal $auth
    if ($refusal) { throw "${refusal}: repository '$($r.id)' - $($auth.reason)." }
    $auth
}

function Protect-Directory([string]$dir) {   # owner-only access, plus SYSTEM and Administrators so backup and endpoint protection keep working
    try {
        if (-not (Test-Path -LiteralPath $dir)) { return $false }
        if (Test-ProtectedDirectory $dir) { return $true }
        $sec = New-Object Security.AccessControl.DirectorySecurity
        $sec.SetAccessRuleProtection($true, $false)
        foreach ($sid in @([Security.Principal.WindowsIdentity]::GetCurrent().User, (New-Object Security.Principal.SecurityIdentifier 'S-1-5-18'), (New-Object Security.Principal.SecurityIdentifier 'S-1-5-32-544'))) {
            $sec.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sid, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')))
        }
        Set-Acl -LiteralPath $dir -AclObject $sec
        $true
    } catch { $false }
}

function Test-ProtectedDirectory([string]$dir) {
    try {
        $acl = (New-Object IO.DirectoryInfo $dir).GetAccessControl([Security.AccessControl.AccessControlSections]::Access)
        $ok = @([Security.Principal.WindowsIdentity]::GetCurrent().User.Value, 'S-1-5-18', 'S-1-5-32-544')
        $acl.AreAccessRulesProtected -and -not @($acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]) | Where-Object { $_.AccessControlType -eq 'Allow' -and $ok -notcontains $_.IdentityReference.Value }).Count
    } catch { $false }
}
function Protect-Text([string]$s) {   # secret-looking values replaced before anything is logged, reported, or output
    if (-not $s) { return $s }
    foreach ($k in $SecretPatterns.Keys) { $s = [regex]::Replace($s, $SecretPatterns[$k], "[REDACTED:$k]") }
    $s
}

# Command guard: the agent checks every terminal command that is not a helper call. BLOCK is never run (no approval
# can release it); NEEDS_APPROVAL runs only after the developer approves that command; ALLOW runs.
$CommandRules = @(
    @{ d = 'BLOCK'; c = 'security-tampering'; rx = '(?i)\b(Set|Add|Remove)-MpPreference\b|\b(Stop|Set)-Service\b[^\r\n]*\b(WinDefend|Sense|MsMpSvc|WdNisSvc)\b|\bsc(\.exe)?\s+(stop|config|delete)\s+(WinDefend|Sense)\b|\bnetsh\s+advfirewall\b|\b(Set|New|Remove)-NetFirewall\w*\b|\bbcdedit\b|\bauditpol\b|\bwevtutil\s+cl\b|\bClear-EventLog\b|\bUninstall-WindowsFeature\b' }
    @{ d = 'BLOCK'; c = 'execution-policy'; rx = '(?i)\bSet-ExecutionPolicy\b|-ExecutionPolicy\s+(Bypass|Unrestricted)\b|-ep\s+(bypass|unrestricted)\b' }
    @{ d = 'BLOCK'; c = 'registry-or-policy'; rx = '(?i)\breg(\.exe)?\s+(add|delete|import|load)\b|\b(Set|New|Remove)-ItemProperty\b[^\r\n]*\bHK(LM|CU|U|CR)\b|\bsecedit\b|\bgpupdate\b|\bnet(\.exe)?\s+(user|localgroup)\b|\b(Add|Remove)-LocalGroupMember\b|\bicacls\b[^\r\n]*/grant\b[^\r\n]*\b(Everyone|Users)\b' }
    @{ d = 'BLOCK'; c = 'privilege-escalation'; rx = '(?i)\brunas(\.exe)?\b|-Verb\s+RunAs\b|\bsudo\b|\bpsexec\b' }
    # Categories, not offensive-tool names: a signature list of attack tools inside this script is itself flagged by
    # endpoint protection (AMSI), and hiding such strings would be evasion.
    @{ d = 'BLOCK'; c = 'credential-access'; rx = '(?i)\bcmdkey\b|\bvaultcmd\b|\bGet-StoredCredential\b|\bConvertFrom-SecureString\b|\bExport-PfxCertificate\b|\.git-credentials\b|\bgit\s+credential\s+(fill|approve)\b|\bdpapi\b' }
    @{ d = 'BLOCK'; c = 'remote-code-execution'; rx = '(?i)\bInvoke-Expression\b|\biex\b|-EncodedCommand\b|\s-enc\s|\|\s*(sh|bash|pwsh|powershell|cmd)(\.exe)?\b|\bStart-BitsTransfer\b|\bmshta\b' }
    @{ d = 'BLOCK'; c = 'external-transfer'; rx = '(?i)\b(curl|wget)(\.exe)?\b[^\r\n]*(\s-T\s|--upload-file|\s-F\s|--form|-d\s*@|--data(-binary)?\s*@)|\bInvoke-(WebRequest|RestMethod)\b[^\r\n]*(-Method\s+(Post|Put|Patch)|-InFile)\b|\b(scp|sftp|ftp|rsync|rclone|gsutil)\b|\bSend-MailMessage\b|\baz\s+storage\b|\baws\s+s3\s+(cp|sync|mv)\b|\btransfer\.sh\b|\bpastebin\b|\bngrok\b|\bnc(at)?\s+-|\bgit\s+remote\s+(add|set-url)\b|\bgh\s+gist\b|\bCompress-Archive\b[^\r\n]*\\\\' }
    @{ d = 'NEEDS_APPROVAL'; c = 'destructive'; rx = '(?i)\bRemove-Item\b[^\r\n]*-Recurse\b|\brm\s+-[a-z]*r|\brmdir\s+/s\b|\bdel\s+/s\b|\bgit\s+(reset\s+--hard|clean\s+-[a-z]*f|checkout\s+--\s|push\b[^\r\n]*--force|branch\s+-D)\b|\b(DROP|TRUNCATE)\s+(TABLE|DATABASE|SCHEMA)\b|\bFormat-Volume\b|\bformat\s+[a-z]:' }
    @{ d = 'NEEDS_APPROVAL'; c = 'git-publish'; rx = '(?i)\bgit\s+(commit|push|merge|rebase|tag|stash|cherry-pick|am)\b' }
    @{ d = 'NEEDS_APPROVAL'; c = 'dependency-change'; rx = '(?i)\bdotnet\s+(add\s+\S*\s*package|tool\s+install)\b|\b(npm|pnpm)\s+(install|i|add)\s+(?!-)\S|\byarn\s+add\b|\bpip3?\s+install\b|\bpoetry\s+add\b|\b(choco|winget|scoop)\s+install\b|\bInstall-(Module|Package|Script)\b|\bnuget\s+install\b|\bgo\s+get\b|\bmvn\s+[^\r\n]*dependency:get\b' }
    @{ d = 'NEEDS_APPROVAL'; c = 'database-change'; rx = '(?i)\bdotnet\s+ef\s+(database|migrations\s+remove)\b|\b(alembic|flyway|liquibase)\b|\bmanage\.py\s+migrate\b|\bprisma\s+migrate\b' }
    @{ d = 'NEEDS_APPROVAL'; c = 'deployment'; rx = '(?i)\b(az|aws|gcloud|kubectl|helm|oc)\s|\bterraform\s+(apply|destroy)\b|\bfunc\s+azure\b|\bdotnet\s+publish\b[^\r\n]*PublishProfile|\bdocker\s+push\b' }
    @{ d = 'NEEDS_APPROVAL'; c = 'sonar-upload'; rx = '(?i)\b(dotnet-sonarscanner|sonar-scanner|sonarscanner)\b|\bdotnet\s+sonarscanner\b|\bsonar\s+analyze\b' }
    @{ d = 'NEEDS_APPROVAL'; c = 'network'; rx = '(?i)\b(curl|wget|iwr|irm|Invoke-WebRequest|Invoke-RestMethod)(\.exe)?\b|https?://' }
)
foreach ($rule in $CommandRules) { $rule.rx = [regex]::new($rule.rx) }

function Test-CommandLine([string]$line) {
    $me = [regex]::Escape(($PSCommandPath -replace '\\', '/'))
    $norm = $line -replace '\\', '/'
    # The helper itself (the one form the auto-approve rule accepts) is allowed; anything chained to it is checked too.
    if ($norm -match "^\s*(powershell|pwsh)(\.exe)?\s+-NoProfile\s+-File\s+`"?$me`"?\s" -and $line -notmatch '[;&|`$<>]') {
        return [pscustomobject]@{ decision = 'ALLOW'; category = 'helper'; reason = 'the agent helper' }
    }
    foreach ($rule in $CommandRules) { $m = $rule.rx.Match($line); if ($m.Success) { return [pscustomobject]@{ decision = $rule.d; category = $rule.c; reason = "matched '$($m.Value.Trim())'" } } }
    [pscustomobject]@{ decision = 'ALLOW'; category = 'routine'; reason = 'no rule matched (build, test, read-only, or repository-local command)' }
}

# Added suppressions and skipped tests on changed lines: gate integrity, checked technically.
$SuppressionPatterns = [ordered]@{
    'pragma warning disable' = '#pragma\s+warning\s+disable'; 'SuppressMessage' = '\[(assembly:\s*)?SuppressMessage'; 'NOSONAR' = '(//|#)\s*NOSONAR'
    'NoWarn' = '<NoWarn>'; 'eslint-disable' = 'eslint-disable'; 'ts-ignore' = '@ts-(ignore|nocheck|expect-error)'; 'SuppressWarnings' = '@SuppressWarnings'
    'noqa' = '#\s*noqa\b'; 'nosec' = '#\s*nosec\b'; 'type ignore' = '#\s*type:\s*ignore'
    'skipped test' = '\[(Fact|Theory|Test|TestMethod)\([^)]*Skip\s*=|\[Ignore(\(|\])|\bx(it|describe)\(|\b(it|describe|test)\.skip\(|@pytest\.mark\.skip|@unittest\.skip|@Disabled\b'
}

function Get-ChangeFindings([string]$root) {   # secrets and suppressions on lines changed against HEAD; values never returned
    $changed = Get-ChangedLines $root
    $secrets = New-Object Collections.Generic.List[object]; $supp = New-Object Collections.Generic.List[object]; $lines = 0
    foreach ($p in $changed.Keys) {
        $full = Join-Path $root $p
        try { if ((Get-Item -LiteralPath $full).Length -gt 1MB) { continue }; $bytes = [IO.File]::ReadAllBytes($full) } catch { continue }
        if ([Array]::IndexOf($bytes, [byte]0) -ge 0) { continue }   # binary
        $text = [IO.File]::ReadAllLines($full)
        foreach ($n in $changed[$p]) {
            if ($n -lt 1 -or $n -gt $text.Length) { continue }
            $l = $text[$n - 1]; $lines++
            $k = Find-Secret $l
            if ($k) { $secrets.Add([pscustomobject]@{ file = $p; line = $n; kind = $k; confidence = $(if ($k -eq 'credential assignment') { 'review' } else { 'high' }) }) }
            foreach ($s in $SuppressionPatterns.Keys) { if ($l -match $SuppressionPatterns[$s]) { $supp.Add([pscustomobject]@{ file = $p; line = $n; kind = $s }); break } }
        }
    }
    [pscustomobject]@{ files = $changed.Count; lines = $lines; secrets = $secrets.ToArray(); suppressions = $supp.ToArray() }
}

function Get-DependencyChanges([string]$root) {   # packages added or changed in manifests against HEAD (tracked edits and new files)
    $rx = '\.(cs|fs|vb)proj$|(^|/)(Directory\.Packages\.props|package\.json|pyproject\.toml|Pipfile|setup\.py|pom\.xml|build\.gradle(\.kts)?|go\.mod|packages\.config)$|(^|/)requirements[^/]*\.txt$'
    $tracked = @(Invoke-Quiet git -C $root -c core.quotepath=off diff --name-only HEAD | Where-Object { $_ -match $rx })
    $untracked = @(Invoke-Quiet git -C $root -c core.quotepath=off ls-files -o --exclude-standard | Where-Object { $_ -match $rx })
    $out = New-Object Collections.Generic.List[string]
    # Packages named in a manifest: project references, JSON dependency maps, requirement lines and arrays, Maven, Go.
    $pkg = [regex]::new('(?im)Include="(?<n>[^"]+)"(?:\s+Version="(?<v>[^"]+)")?|"(?<n>@?[\w./-]+)"\s*:\s*"(?<v>[~^<>=]*\d[^"]*)"|^\s*(?<n>[A-Za-z][\w.-]*)\s*(?<v>[=<>~!]=?[^\s;#]+)|"(?<n>[A-Za-z][\w.-]*)\s*(?<v>(?:==|>=|<=|~=|!=)[^"\s,;]*)"|<artifactId>(?<n>[^<]+)</artifactId>|^\s*require\s+(?<n>\S+)\s+(?<v>\S+)|^\s*(?<n>[\w.-]+/[\w./-]+)\s+(?<v>v\d\S*)')
    $skipNames = '^(name|version|description|main|scripts|private|license|type|node|npm|engines|requires-python)$'
    $names = { param($text) $set = New-Object 'Collections.Generic.HashSet[string]'; foreach ($m in $pkg.Matches($text)) { $n = $m.Groups['n'].Value; if ($n -notmatch $skipNames) { [void]$set.Add("$n $($m.Groups['v'].Value)".Trim()) } }; $set }
    # Compared with the same file at HEAD (empty for a new file), so reformatting is not a change and several
    # packages on one line are each judged on their own.
    foreach ($f in $tracked + $untracked) {
        $new = & $names ([IO.File]::ReadAllText((Join-Path $root $f)))
        $old = if ($untracked -contains $f) { New-Object 'Collections.Generic.HashSet[string]' } else { & $names ((Invoke-Quiet git -C $root -c core.quotepath=off show "HEAD:$f") -join "`n") }
        foreach ($p in $new) { if (-not $old.Contains($p)) { $out.Add("${f}: $p") } }
    }
    @($out | Select-Object -Unique)
}

function Test-InstalledIntegrity {   # installed files against the SHA-256 install manifest
    $mf = Join-Path $AkzoHome 'install-manifest.json'
    if (-not (Test-Path -LiteralPath $mf)) { return [pscustomobject]@{ status = 'NOT VERIFIED'; detail = 'no install manifest (helper runs from the package source, not an installation)' } }
    $files = @((Get-Content -LiteralPath $mf -Raw | ConvertFrom-Json).files)
    $bad = @($files | Where-Object { -not (Test-Path -LiteralPath $_.path) -or (Get-FileHash -LiteralPath $_.path -Algorithm SHA256).Hash -ne $_.sha256 } | ForEach-Object { $_.path })
    $sig = (Get-AuthenticodeSignature -LiteralPath $PSCommandPath).Status
    if ($bad) { [pscustomobject]@{ status = 'FAIL'; detail = "$($bad.Count) installed file(s) differ from the manifest: $($bad -join ', ')" } }
    else { [pscustomobject]@{ status = 'PASS'; detail = "$($files.Count) installed file(s) match the SHA-256 manifest ($mf); helper signature: $sig. Hashes prove the files are unchanged since installation, not who produced or approved the package." } }
}

# The task folder of a work item (for attach/role); throws when it does not exist or is ambiguous.
function Find-TaskDir([string]$workItem, [string]$repoId) {
    if ($workItem -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') { throw "Work-item id '$workItem' must be a folder name such as PBI-12345 (letters, digits, '.', '_', '-')." }
    if ($repoId -and $repoId -notmatch '^[A-Za-z0-9][A-Za-z0-9._ -]{0,99}$') { throw "Repository id '$repoId' is not a valid id." }
    $hits = @(Get-ChildItem -LiteralPath $TasksDir -Directory -ErrorAction SilentlyContinue |
        Where-Object { -not $repoId -or $_.Name -eq $repoId } | ForEach-Object { Join-Path $_.FullName $workItem } |
        Where-Object { Test-Path -LiteralPath $_ -PathType Container })
    if ($hits.Count -gt 1) { throw "Work item '$workItem' exists under several repositories ($($hits -join ', ')); add -Repo <id>." }
    if (-not $hits.Count) { throw "No task folder for '$workItem' under $TasksDir. Start it with intake or task first." }
    $hits[0]
}

# ---- Task, spec-location, and branch helpers (3.5.0) -----------------------------------------------------------
function ConvertTo-Slug([string]$s, [int]$max = 50) {   # lower case, Git-safe, hyphens
    $x = ("$s").ToLowerInvariant() -replace '[^a-z0-9]+', '-' -replace '^-+|-+$', ''
    if ($x.Length -gt $max) { $x = $x.Substring(0, $max) -replace '-+$', '' }
    $x
}
function Get-IdPart([string]$id) { ConvertTo-Slug $id 40 }   # the whole id, so PBI-15 stays pbi-15
function Get-SpecFolderName([string]$id, [string]$title) {   # 300186 + "Create paint system" -> 300186-create-paint-system
    $i = Get-IdPart $id; $s = ConvertTo-Slug $title 50
    if ($s) { "$i-$s" } else { $i }
}
function Get-BranchName([string]$id, [string]$title) { 'feature/' + (Get-SpecFolderName $id $title) }
function Get-PbiTitle([string]$pbiFile) {   # first heading of the refined PBI without its number
    if (-not $pbiFile -or -not (Test-Path -LiteralPath $pbiFile)) { return '' }
    $h = "$(Get-Content -LiteralPath $pbiFile -TotalCount 20 -Encoding UTF8 | Where-Object { $_ -match '^\s*#+\s*\S' } | Select-Object -First 1)" -replace '^\s*#+\s*', ''
    ($h -replace '(?i)^\s*(PBI|WI|US)?[-# ]?\d{3,}\s*[-:.]?\s*', '').Trim()
}
function Get-RepoTasks([string]$repoId) {   # every task folder of one repository, with its remembered state (task.json)
    $root = Join-Path $TasksDir $repoId
    foreach ($d in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
        $f = Join-Path $d.FullName 'task.json'
        $j = if (Test-Path -LiteralPath $f) { try { Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $null } } else { $null }
        [pscustomobject]@{ id = $d.Name; dir = $d.FullName; json = $j; hasPbi = (Test-Path -LiteralPath (Join-Path $d.FullName 'refined-pbi.md')); modified = $d.LastWriteTime }
    }
}
function Get-StatusLine([string]$file, [string]$key) {   # 'Status' or 'Gap map' line of a spec/plan; templates (with '|') read as not started
    if (-not $file -or -not (Test-Path -LiteralPath $file)) { return 'no file' }
    $l = (Select-String -LiteralPath $file -Pattern "^${key}:" -ErrorAction SilentlyContinue | Select-Object -First 1).Line
    if ($l -and $l -notmatch '\|') { ($l -replace "^${key}:\s*").Trim() } else { 'not started' }
}
function Get-TaskSummary($t) {
    $sd = "$($t.json.specDir)"; if (-not $sd) { $sd = $t.dir }
    $plan = Get-StatusLine (Join-Path $sd 'plan.md') 'Status'
    [pscustomobject][ordered]@{
        id = $t.id; title = "$($t.json.title)"; gapMap = (Get-StatusLine (Join-Path $sd 'spec.md') 'Gap map'); spec = (Get-StatusLine (Join-Path $sd 'spec.md') 'Status')
        plan = $plan; completed = [bool]($plan -match '(?i)^done'); branch = "$($t.json.branch)"; specDir = $sd; modified = $t.modified.ToString('yyyy-MM-dd HH:mm')
    }
}
# Workflow names (modules\plan\assets\workflow.json): people see gate and task titles; ids stay in files and logs.
function Read-Workflow {
    $f = Join-Path $ModulesDir 'plan\assets\workflow.json'
    try { Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json } catch { throw "Workflow configuration $f is missing or not valid JSON: $($_.Exception.Message)" }
}
function Get-TaskStatusLabel($wf, [string]$raw) {   # plan status cell -> user-facing label; old plans (todo / done) map too
    $v = $raw.Trim()
    foreach ($st in @($wf.taskStatuses)) { if ($v -match "(?i)$($st.match)") { return $st.label } }
    if ($v) { $v } else { 'Not Started' }
}
function Get-PlanTasks([string]$plan, $wf) {   # rows of plan section 2: id, descriptive title, status label (and the raw cell when it says more)
    if (-not (Test-Path -LiteralPath $plan) -or (Get-StatusLine $plan 'Status') -eq 'not started') { return @() }
    foreach ($l in [IO.File]::ReadAllLines($plan)) {
        if ($l -notmatch '^\|\s*(T\d+)\s*\|') { continue }
        $c = @($l.Trim().Trim('|').Split('|') | ForEach-Object { $_.Trim() })
        $raw = "$(@($c | Where-Object { $_ }) | Select-Object -Last 1)"
        if ($c.Count -lt 3 -or $raw -eq $c[0]) { $raw = '' }
        $label = Get-TaskStatusLabel $wf $raw
        $row = [ordered]@{ id = $c[0]; title = $(if ($c[1]) { $c[1] } else { '(no title: name this task in plan.md)' }); status = $label }
        if ($raw -and $raw -notmatch "(?i)^$([regex]::Escape($label))$" -and $raw -notmatch '(?i)^(todo|done)$') { $row.detail = $raw }
        [pscustomobject]$row
    }
}
function Get-ImplementationReadiness([string]$plan) {
    $allowed = [ordered]@{
        'GraphQL schema' = @('VERIFIED', 'NOT APPLICABLE')
        'GraphQL operations' = @('VERIFIED', 'NEW OPERATION PLANNED', 'NOT APPLICABLE')
        'Generated client' = @('COMPATIBLE', 'REGENERATION PLANNED', 'NOT APPLICABLE')
        'FluentValidation' = @('EXISTING RULES REUSED', 'NEW VALIDATOR PLANNED', 'NOT APPLICABLE')
        'Validator execution' = @('VERIFIED', 'EXPLICIT IMPLEMENTATION TASK')
        'Architecture compliance' = @('VERIFIED')
    }
    $issues = New-Object Collections.Generic.List[string]
    $rows = @{}
    $text = if (Test-Path -LiteralPath $plan -PathType Leaf) { [IO.File]::ReadAllText($plan) } else { '' }
    $section = [regex]::Match($text, '(?ms)^## 1b\. Contract and validation readiness\r?\n(?<body>.*?)(?=^## |\z)').Groups['body'].Value
    $taskIds = @([regex]::Matches($text, '(?m)^\|\s*(T\d+)\s*\|') | ForEach-Object { $_.Groups[1].Value })
    foreach ($line in $section -split '\r?\n') {
        if ($line -notmatch '^\|') { continue }
        $cells = @($line.Trim().Trim('|').Split('|') | ForEach-Object { $_.Trim().Trim('`').Trim() })
        if ($cells.Count -ne 4 -or -not $allowed.Contains($cells[0])) { continue }
        $name = $cells[0]
        if ($rows.ContainsKey($name)) { $issues.Add("Duplicate readiness row: $name"); continue }
        $rows[$name] = [pscustomobject]@{ check = $name; status = $cells[1]; evidence = $cells[2]; task = $cells[3] }
        if ($cells[1] -cnotin $allowed[$name]) { $issues.Add("$name needs an allowed readiness status.") }
        if (-not $cells[2] -or $cells[2] -match '^(?i:PENDING|TBD|UNKNOWN|UNVERIFIED|-+|<.*>)$') { $issues.Add("$name needs current evidence or an applicability reason.") }
        if ($cells[1] -like '*PLANNED' -or $cells[1] -eq 'EXPLICIT IMPLEMENTATION TASK') {
            $references = @([regex]::Matches($cells[3], '\bT\d+\b') | ForEach-Object { $_.Value })
            if (-not $references.Count -or @($references | Where-Object { $_ -notin $taskIds }).Count) { $issues.Add("$name needs a reference to an existing implementation task.") }
        } elseif ($cells[3] -and $cells[3] -ne '-') { $issues.Add("$name has an unresolved task/blocker; resolve it or use an allowed planned status.") }
    }
    foreach ($name in $allowed.Keys) { if (-not $rows.ContainsKey($name)) { $issues.Add("Missing readiness row: $name") } }
    if ($rows['GraphQL operations'].status -eq 'NOT APPLICABLE' -and $rows['GraphQL schema'].status -ne 'NOT APPLICABLE') {
        $issues.Add('GraphQL operations cannot be NOT APPLICABLE when a GraphQL schema is required.')
    }
    if ($rows['GraphQL schema'].status -eq 'NOT APPLICABLE' -and
        ($rows['GraphQL operations'].status -ne 'NOT APPLICABLE' -or $rows['Generated client'].status -ne 'NOT APPLICABLE')) {
        $issues.Add('A non-GraphQL plan must mark operations and generated client NOT APPLICABLE with reasons.')
    }
    [pscustomobject]@{ status = $(if ($issues.Count) { 'BLOCKED' } else { 'READY_FOR_APPROVAL' })
        approval = 'REQUIRED'; checks = @($allowed.Keys | Where-Object { $rows.ContainsKey($_) } | ForEach-Object { $rows[$_] })
        blockers = $issues.ToArray(); limitation = 'Recorded evidence/task validation; G4 approval also runs the mechanical GraphQL validator when the schema row is VERIFIED. Not approval authentication or an editor-write interceptor.' }
}
function Get-GateView([string]$specDir, $wf) {   # gate titles with the status of the document each gate approves
    $gates = foreach ($g in @($wf.gates)) {
        $row = [ordered]@{ id = $g.id; title = $g.title }
        if ($g.document) { $row.status = Get-StatusLine (Join-Path $specDir $g.document) $g.key }
        [pscustomobject]$row
    }
    $next = $gates | Where-Object { "$($_.status)" -match '(?i)^(draft|in review|changes requested)' -or ($_.id -eq 'G4' -and "$($_.status)" -match '(?i)^waived') } | Select-Object -First 1
    $detail = if ($next) { $g = @($wf.gates) | Where-Object { $_.id -eq $next.id }
        [pscustomobject][ordered]@{ id = $g.id; title = $g.title; status = $next.status; purpose = $g.purpose; deliverable = $g.deliverable; review = $g.review; afterApproval = $g.afterApproval
            choices = @('Approve', 'Request changes', 'Custom response') } } else { $null }
    @{ gates = @($gates); next = $detail }
}
function Read-Approvals([string]$taskDir) {
    $f = Join-Path $taskDir 'approvals.jsonl'
    if (-not (Test-Path -LiteralPath $f)) { return @() }
    @(foreach ($l in [IO.File]::ReadAllLines($f)) { if ($l.Trim()) { try { $l | ConvertFrom-Json } catch { } } })
}
function Read-TrxResults([string[]]$files) {   # test full name -> outcome; a newer file wins, and within one file a failed data row wins
    $res = @{}
    foreach ($f in @($files | Sort-Object { (Get-Item -LiteralPath $_).LastWriteTimeUtc })) {
        $x = try { [xml](Get-Content -LiteralPath $f -Raw -Encoding UTF8) } catch { $null }
        if (-not $x) { continue }
        $cls = @{}
        foreach ($u in @($x.GetElementsByTagName('UnitTest'))) { $m = @($u.GetElementsByTagName('TestMethod'))[0]; if ($m) { $cls[$u.GetAttribute('id')] = ($m.GetAttribute('className') -split ',')[0].Trim() } }
        $mine = @{}
        foreach ($t in @($x.GetElementsByTagName('UnitTestResult'))) {
            $n = $t.GetAttribute('testName') -replace '\s*\(.*$', ''   # data rows: Method(x: 1) -> Method
            $c = $cls[$t.GetAttribute('testId')]
            $full = if ($c -and -not $n.StartsWith("$c.")) { "$c.$n" } else { $n }
            if ($mine.ContainsKey($full) -and $res[$full].outcome -ne 'Passed') { continue }
            $mine[$full] = 1; $res[$full] = [pscustomobject]@{ outcome = $t.GetAttribute('outcome'); file = $f }
        }
    }
    $res
}
function Get-Trace([string]$specDir, $results) {   # ACs of spec.md -> the tests plan.md section 6 lists for them -> their TRX outcome
    $norm = { param($s) ($s -replace '[\s-]', '').ToUpperInvariant() }   # AC-1, AC 1, ac1 -> AC1
    $acs = [ordered]@{}
    $spec = Join-Path $specDir 'spec.md'
    if (Test-Path -LiteralPath $spec) { foreach ($l in [IO.File]::ReadAllLines($spec)) { if ($l -match '^\|\s*(AC[\s-]?\d+)\s*\|\s*([^|]*)\|') { $acs[(& $norm $Matches[1])] = @{ req = $Matches[2].Trim(); tests = New-Object Collections.Generic.List[string] } } } }
    $plan = Join-Path $specDir 'plan.md'; $col = $null
    if (Test-Path -LiteralPath $plan) {
        foreach ($l in [IO.File]::ReadAllLines($plan)) {
            $cells = @($l.Trim().Trim('|').Split('|') | ForEach-Object { $_.Trim() })
            if (-not $col) {
                if ($l -match '^\|.*\|\s*Test \(file::name\)\s*\|') { $col = @{}; for ($i = 0; $i -lt $cells.Count; $i++) { if ($cells[$i] -eq 'AC') { $col.ac = $i } elseif ($cells[$i] -eq 'REQ') { $col.req = $i } elseif ($cells[$i] -like 'Test (*') { $col.test = $i } elseif ($cells[$i] -like 'Code*') { $col.code = $i } } }
                continue
            }
            if ($l -notmatch '^\s*\|') { break }   # the matrix ended
            if ($l -match '^\s*\|\s*-') { continue }
            foreach ($a in [regex]::Matches("$($cells[$col.ac])", '(?i)AC[\s-]?\d+')) {
                $k = & $norm $a.Value
                if (-not $acs.Contains($k)) { $acs[$k] = @{ req = "$($cells[$col.req])"; tests = New-Object Collections.Generic.List[string] } }
                if ($null -ne $col.code -and "$($cells[$col.code])" -match '\w' -and "$($cells[$col.code])" -notmatch '^(-|—|n/?a|none)$') { $acs[$k].code = "$($cells[$col.code])" }
                foreach ($t in ("$($cells[$col.test])" -split ',|;|<br\s*/?>')) { $t = $t.Trim().Trim('`').Trim(); if ($t -and $t -notmatch '^(-|—|n/?a|none)$') { $acs[$k].tests.Add($t) } }
            }
        }
    }
    $keys = @($results.Keys)
    foreach ($k in @($acs.Keys)) {
        $tests = @(foreach ($t in $acs[$k].tests) {
                $tf, $tn = if ($t -match '^(.*)::(.+)$') { $Matches[1], $Matches[2] } else { '', $t }
                $tn = $tn.Trim() -replace '\(.*$', ''
                $hits = @($keys | Where-Object { $_ -eq $tn -or $_.EndsWith(".$tn") } | Sort-Object)
                if ($hits.Count -gt 1 -and $tf) {   # the file name of file::name picks the class
                    $stem = [IO.Path]::GetFileNameWithoutExtension((($tf -replace '\\', '/') -split '/')[-1])
                    $narrow = @($hits | Where-Object { $_ -eq "$stem.$tn" -or $_.EndsWith(".$stem.$tn") }); if ($narrow.Count) { $hits = $narrow }
                }
                $o = if (-not $hits.Count) { 'not found' } elseif ($hits.Count -gt 1) { "ambiguous: $($hits -join ', ')" } else { "$($results[$hits[0]].outcome)" }
                [pscustomobject][ordered]@{ test = (Protect-Text $t); outcome = $o; matched = $(if ($hits.Count -eq 1) { $hits[0] } else { '' }) } })
        $st = if (-not $tests.Count) { 'MISSING' } elseif (@($tests | Where-Object { $_.outcome -match '^(Failed|Error|Timeout|Aborted)$' }).Count) { 'FAILING' } elseif (-not @($tests | Where-Object { $_.outcome -ne 'Passed' }).Count) { 'COVERED' } else { 'NOT RUN' }
        [pscustomobject][ordered]@{ ac = $k; req = $acs[$k].req; status = $st; code = "$($acs[$k].code)"; tests = $tests }
    }
}
function Get-TraceReport([string]$dir, [string]$resultsPath) {   # trace output for one task folder; results from -Path, else the evidence folder and the repository's TestResults
    $j = try { Get-Content -LiteralPath (Join-Path $dir 'task.json') -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $null }
    $sd = if ($j.specDir) { "$($j.specDir)" } else { $dir }
    $rr = Get-Registry | Where-Object { $_.id -eq (Split-Path (Split-Path $dir) -Leaf) } | Select-Object -First 1
    $roots = @(if ($resultsPath) { $resultsPath.Trim('"') } else {
            # shortcut: walks the whole repository for TestResults folders; pass -Path when that is slow
            Join-Path $dir 'evidence'
            if ($rr -and (Test-Dir $rr.path)) { Get-ChildItem -LiteralPath $rr.path -Recurse -Directory -Filter TestResults -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName } } })
    if ($resultsPath -and -not (Test-Path -LiteralPath $roots[0])) { throw "-Path '$resultsPath' was not found." }
    $trx = @($roots | Where-Object { Test-Path -LiteralPath $_ } | ForEach-Object { if ((Get-Item -LiteralPath $_).PSIsContainer) { Get-ChildItem -LiteralPath $_ -Recurse -Filter *.trx -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName } } else { $_ } })
    $acs = @(Get-Trace $sd (Read-TrxResults $trx))
    $cnt = { param($s) @($acs | Where-Object { $_.status -eq $s }).Count }
    $missing = & $cnt 'MISSING'; $failing = & $cnt 'FAILING'; $notRun = & $cnt 'NOT RUN'
    $status = if (-not $acs.Count) { 'NO_ACS' } elseif ($missing -or $failing) { 'BLOCKED' } elseif ($notRun) { 'NOT_RUN' } else { 'COVERED' }
    # Freshness: results older than the newest source change (HEAD commit or an uncommitted edit) do not prove the current code.
    $ev = [ordered]@{ repo = "$($rr.id)"; branch = ''; head = ''; resultsAt = ''; latestSourceChange = ''; stale = $null; reason = '' }
    $newest = @($trx | ForEach-Object { (Get-Item -LiteralPath $_).LastWriteTime } | Sort-Object)[-1]
    if ($rr -and (Test-Dir $rr.path)) {
        $ev.branch = "$(Invoke-Quiet git -C $rr.path rev-parse --abbrev-ref HEAD)"; $ev.head = "$(Invoke-Quiet git -C $rr.path rev-parse --short HEAD)"
        $ct = "$(Invoke-Quiet git -C $rr.path log -1 --format=%ct)"
        $changes = @(if ($ct -match '^\d+$') { [DateTimeOffset]::FromUnixTimeSeconds([long]$ct).LocalDateTime })
        foreach ($s in @(Invoke-Quiet git -C $rr.path -c core.quotepath=off status --porcelain=v1 -uall)) {
            $f = ($s.Substring(3) -split ' -> ')[-1].Trim('"')
            if ($f -match '(?i)(^|/)(TestResults|bin|obj)/|\.trx$') { continue }   # outputs of the test run itself
            $full = Join-Path $rr.path $f; if (Test-Path -LiteralPath $full -PathType Leaf) { $changes += (Get-Item -LiteralPath $full).LastWriteTime }
        }
        $latest = @($changes | Sort-Object)[-1]
        if ($latest) { $ev.latestSourceChange = $latest.ToString('s') }
        if ($newest) { $ev.resultsAt = $newest.ToString('s'); $ev.stale = [bool]($latest -and $latest -gt $newest); if ($ev.stale) { $ev.reason = 'the code changed after the newest test results; run the tests again' } }
        else { $ev.reason = 'no test results' }
    } else { $ev.reason = 'the repository is not registered, so freshness cannot be checked'; if ($newest) { $ev.resultsAt = $newest.ToString('s') } }
    # Readiness (separate from status): implementation evidence per AC; stale or missing results never count as verified.
    foreach ($a in $acs) {
        $passed = @($a.tests | Where-Object { $_.outcome -eq 'Passed' }).Count
        $rd = switch ($a.status) {
            'COVERED' { if ($ev.stale -eq $false) { 'IMPLEMENTED_AND_VERIFIED' } else { 'NOT_VERIFIED' } }
            'FAILING' { 'BLOCKED' }
            'NOT RUN' { if ($passed) { 'PARTIALLY_IMPLEMENTED' } elseif ($a.code) { 'IMPLEMENTED_NOT_TESTED' } else { 'NOT_VERIFIED' } }
            default { if ($a.code) { 'IMPLEMENTED_NOT_TESTED' } else { 'MISSING' } } }
        $a | Add-Member -Force NoteProperty readiness $rd
    }
    [pscustomobject][ordered]@{ status = $status; pbi = (Split-Path $dir -Leaf); spec = (Join-Path $sd 'spec.md'); plan = (Join-Path $sd 'plan.md'); searched = $roots
        results = @($trx | ForEach-Object { [pscustomobject]@{ file = $_; written = (Get-Item -LiteralPath $_).LastWriteTime.ToString('yyyy-MM-dd HH:mm') } })
        counts = [ordered]@{ covered = (& $cnt 'COVERED'); failing = $failing; notRun = $notRun; missing = $missing }
        evidence = $ev
        readiness = [ordered]@{ verified = @($acs | Where-Object { $_.readiness -eq 'IMPLEMENTED_AND_VERIFIED' }).Count; notVerified = @($acs | Where-Object { $_.readiness -ne 'IMPLEMENTED_AND_VERIFIED' }).Count
            ready = [bool]($acs.Count -and -not @($acs | Where-Object { $_.readiness -ne 'IMPLEMENTED_AND_VERIFIED' }).Count) }
        acs = $acs
        next = $(switch ($status) {
                'NO_ACS' { 'spec.md has no acceptance criteria rows (| AC1 | REQ-1 | ... |); write them before tracing.' }
                'BLOCKED' { 'G5 is blocked: write a failing test for each MISSING AC and name it in the plan.md section 6 Test column (file::name); fix the cause of each FAILING test; run the tests and trace again.' }
                'NOT_RUN' { 'Run the listed tests so their TRX results exist, then trace again; an ambiguous or not-found name needs the exact file::name.' }
                default { 'Every AC has a passing test: build the handover matrix from this output.' } })
    }
}

# ---- Lessons from PR reviews (3.12.0) ---------------------------------------------------------------------------
# One file per repository. review-rules.json holds line patterns only; a lesson also keeps the review history (comment,
# reference, root cause, verified correction, evidence, approval) and checks a regex cannot express ("a new X while an
# existing X does the same"). A lesson is applied only after the developer approves it.
function Get-LessonFile([string]$repoId) { Join-Path $LearningDir "$($repoId -replace '[^\w.-]', '_').json" }
function Read-Lessons([string]$repoId) {   # an unreadable file is reported, never rewritten or silently replaced
    $f = Get-LessonFile $repoId
    if (-not (Test-Path -LiteralPath $f)) { return [pscustomobject]@{ file = $f; lessons = @(); error = '' } }
    try { $j = Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json; [pscustomobject]@{ file = $f; lessons = @(foreach ($l in $j.lessons) { if ($l.key) { $l } }); error = '' } }
    catch { [pscustomobject]@{ file = $f; lessons = @(); error = $_.Exception.Message } }
}
function Save-Lessons([string]$file, $lessons) {
    New-Item -ItemType Directory -Force (Split-Path $file) | Out-Null
    $arr = @(foreach ($x in $lessons) { $x })   # a plain array: 5.1's ConvertTo-Json fails on @() of a generic List ("Argument types do not match")
    Write-TextAtomic $file ([pscustomobject][ordered]@{ version = 1; lessons = $arr } | ConvertTo-Json -Depth 8)
}
function Read-LessonPatterns {   # known review patterns (profiles\lesson-patterns.json, or its profiles-custom copy)
    $p = (Get-ProfileFile 'lesson-patterns.json').path
    try { @(foreach ($x in (Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json)) { $x }) } catch { @() }
}
function Test-AnyToken($tokens, [string]$words) { foreach ($w in @(Get-Tokens $words)) { if ($tokens -contains $w) { return $true } }; $false }
function Test-LessonCheck($check) {   # '' when the check can run, else why not
    if (-not $check) { return 'no check' }
    switch ("$($check.kind)") {
        'reuse-before-new' { $rx = "$($check.typePattern)" }
        'regex' { $rx = "$($check.regex)" }
        default { return "check kind '$($check.kind)' is not reuse-before-new or regex" } }
    if (-not $rx) { return 'the check has no pattern' }
    try { [void][regex]::new($rx); '' } catch { "the pattern does not compile ($($_.Exception.GetBaseException().Message))" }
}
function Get-CheckId($c) { if ($c) { "$($c.kind)|$($c.typePattern)|$($c.regex)" } else { '' } }   # what a check matches, ignoring how it was written
function Get-LessonSummary([string]$repoId) {   # approved lessons, one line each, for planning (task output)
    @((Read-Lessons $repoId).lessons | Where-Object { $_.status -eq 'approved' } | ForEach-Object { "$($_.key): $($_.title)" })
}
function Update-TaskJson([string]$dir, [hashtable]$set) {   # merge keys into task.json; other keys are kept
    $f = Join-Path $dir 'task.json'
    Use-FileLock $f {
        $o = if (Test-Path -LiteralPath $f) { try { Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json } catch { [pscustomobject]@{} } } else { [pscustomobject]@{} }
        foreach ($k in $set.Keys) { $o | Add-Member -NotePropertyName $k -NotePropertyValue $set[$k] -Force }
        Write-TextAtomic $f ($o | ConvertTo-Json -Depth 4)
    }
}
# A spec/plan folder belongs to one work item. Taken when another task remembers it, or when it already holds work
# (not the untouched templates) that does not mention this work item. Returns the owner, or '' when it is free.
function Find-SpecOwner([string]$specDir, [string]$repoId, [string]$selfId) {
    $norm = { param($p) ("$p" -replace '/', '\').TrimEnd('\').ToLowerInvariant() }
    $want = & $norm $specDir
    foreach ($t in Get-RepoTasks $repoId) { if ($t.id -ne $selfId -and $t.json.specDir -and (& $norm $t.json.specDir) -eq $want) { return $t.id } }
    foreach ($n in 'spec', 'plan') {
        $f = Join-Path $specDir "$n.md"
        if (-not (Test-Path -LiteralPath $f)) { continue }
        $tmpl = (Get-FileHash -LiteralPath (Join-Path $ModulesDir "$n\assets\$n.md")).Hash
        if ((Get-FileHash -LiteralPath $f).Hash -eq $tmpl) { continue }
        $head = (Get-Content -LiteralPath $f -TotalCount 6 -Encoding UTF8) -join "`n"
        if ($head -notmatch "(?<![A-Za-z0-9])$([regex]::Escape($selfId))(?![A-Za-z0-9])") { return '(existing files that no task has recorded)' }
    }
    ''
}
function Get-TaskOverlap([string]$repoId, [string]$selfId, [string]$pbiFile) {   # other tasks of this repository that look like the same feature
    $read = { param($f, $title) $x = ''; if ($f -and (Test-Path -LiteralPath $f)) { $x = (Get-Content -LiteralPath $f -TotalCount 25 -Encoding UTF8) -join ' '; if ($x.Length -gt 700) { $x = $x.Substring(0, 700) } }; @(Get-Tokens "$title $x") }
    $mine = & $read $pbiFile (Get-PbiTitle $pbiFile)
    if ($mine.Count -lt 3) { return @() }
    $out = New-Object Collections.Generic.List[object]
    foreach ($t in @(Get-RepoTasks $repoId | Where-Object { $_.id -ne $selfId -and $_.hasPbi } | Sort-Object modified -Descending | Select-Object -First 30)) {
        $theirs = & $read (Join-Path $t.dir 'refined-pbi.md') "$($t.json.title)"
        $shared = @($mine | Where-Object { $theirs -contains $_ })
        $union = @($mine + $theirs | Select-Object -Unique).Count
        if ($shared.Count -ge 3 -and $union -gt 0 -and ($shared.Count / $union) -ge 0.25) {
            $s = Get-TaskSummary $t
            $out.Add([pscustomobject][ordered]@{ id = $t.id; title = $s.title; plan = $s.plan; completed = $s.completed; branch = $s.branch; similarity = [math]::Round($shared.Count / $union, 2); sharedTerms = ($shared | Select-Object -First 8) -join ', ' })
        }
    }
    @($out | Sort-Object similarity -Descending | Select-Object -First 5)
}
$IntegrationBranch = '^(main|master|develop|development|dev|trunk|staging|production|prod|qa|uat|test|integration.*|releases?[/-].*|hotfix[/-].*)$'
function Get-BranchInfo($r, [string]$pbiId, [string]$title, [switch]$Brief) {   # -Brief (issue): branch, HEAD, changes, operation only
    $root = $r.path
    $cur = "$(Invoke-Quiet git -C $root symbolic-ref --short -q HEAD)"   # empty when detached
    $head = "$(Invoke-Quiet git -C $root log -1 '--format=%h %s')"
    $dirty = @(Invoke-Quiet git -C $root -c core.quotepath=off status --porcelain=v1)
    $markers = [ordered]@{ 'MERGE_HEAD' = 'merge'; 'rebase-merge' = 'rebase'; 'rebase-apply' = 'rebase'; 'CHERRY_PICK_HEAD' = 'cherry-pick'; 'REVERT_HEAD' = 'revert' }
    $gitArgs = @('-C', $root, 'rev-parse'); foreach ($k in $markers.Keys) { $gitArgs += '--git-path', $k }
    $gps = @(Invoke-Quiet git @gitArgs)   # one process for all five markers, one path per line
    $op = @(for ($i = 0; $i -lt $gps.Count; $i++) {
            $gp = $gps[$i]
            if ($gp -and (Test-Path -LiteralPath $(if ([IO.Path]::IsPathRooted($gp)) { $gp } else { Join-Path $root $gp }))) { @($markers.Values)[$i] } }) | Select-Object -Unique
    if ($Brief) {
        return [pscustomobject][ordered]@{ branch = $(if ($cur) { $cur } else { '(detached HEAD)' }); head = $head; uncommitted = $dirty.Count; uncommittedPaths = @($dirty | Select-Object -First 15)
            conflicted = @($dirty | Where-Object { $_ -match '^(U.|.U|AA|DD) ' } | ForEach-Object { $_.Substring(3) }); operationInProgress = $(if ($op) { @($op) -join ', ' } else { '' }) }
    }
    $refs = @(Invoke-Quiet git -C $root for-each-ref '--format=%(refname)' refs/heads refs/remotes)
    $local = @($refs | Where-Object { $_ -like 'refs/heads/*' } | ForEach-Object { $_.Substring(11) })
    $remote = @($refs | Where-Object { $_ -like 'refs/remotes/*' -and $_ -notlike '*/HEAD' } | ForEach-Object { $_.Substring(13) })
    $remoteHead = "$(Invoke-Quiet git -C $root symbolic-ref --short -q refs/remotes/origin/HEAD)" -replace '^origin/', ''
    $bases = @(@($remoteHead) + 'main', 'master', 'develop', 'development' | Where-Object { $_ -and ($local -contains $_ -or $remote -contains "origin/$_") } | Select-Object -Unique)
    $tasks = @(Get-RepoTasks $r.id)
    $recordedFor = @($tasks | Where-Object { $cur -and "$($_.json.branch)" -eq $cur } | ForEach-Object { $_.id })
    $mine = $tasks | Where-Object { $_.id -eq $pbiId } | Select-Object -First 1
    $forThis = "$($mine.json.branch)"
    $isIntegration = [bool]($cur -match $IntegrationBranch)
    $proposed = ''; $exists = $false; $alternative = ''
    if ($pbiId -or $title) {
        $proposed = Get-BranchName $pbiId $title
        $exists = ($local -contains $proposed) -or ($remote | Where-Object { $_ -like "*/$proposed" })
        if ($exists) { for ($n = 2; $n -lt 20; $n++) { $alt = "$proposed-$n"; if (-not ($local -contains $alt) -and -not ($remote | Where-Object { $_ -like "*/$alt" })) { $alternative = $alt; break } } }
    }
    $others = @($recordedFor | Where-Object { $_ -ne $pbiId })
    $recommend = 'new'; $reason = ''
    if (-not $cur) { $reason = 'HEAD is detached; commits made here belong to no branch' }
    elseif ($isIntegration) { $reason = "'$cur' is a shared integration branch" }
    elseif ($others.Count) { $reason = "'$cur' is recorded for another PBI ($($others -join ', '))" }
    elseif ($forThis -and $forThis -eq $cur) { $recommend = 'current'; $reason = "'$cur' is already recorded for this PBI" }
    else { $recommend = 'current'; $reason = "'$cur' is not a shared branch and is not recorded for another PBI" }
    [pscustomobject][ordered]@{
        repo = $r.id; path = $root; branch = $(if ($cur) { $cur } else { '(detached HEAD)' }); head = $head; commits = [bool]$head
        uncommitted = $dirty.Count; uncommittedPaths = @($dirty | Select-Object -First 15)
        staged = @($dirty | Where-Object { $_ -match '^[MADRCTU]' }).Count; unstaged = @($dirty | Where-Object { $_ -match '^.[MDTU]' }).Count
        untracked = @($dirty | Where-Object { $_ -like '[?][?]*' }).Count; conflicted = @($dirty | Where-Object { $_ -match '^(U.|.U|AA|DD) ' } | ForEach-Object { $_.Substring(3) })
        operationInProgress = $(if ($op) { @($op) -join ', ' } else { '' })
        integrationBranch = $isIntegration; recordedForPbis = $recordedFor; recordedForThisPbi = $forThis
        recommend = $recommend; reason = $reason
        defaultBase = $(if ($bases.Count) { $bases[0] } else { '' }); baseCandidates = $bases; baseNote = 'Confirm the base branch with the developer; do not assume it.'
        proposedBranch = $proposed; proposedExists = [bool]$exists; alternativeBranch = $alternative
        localBranches = @($local | Select-Object -First 40); remoteBranches = @($remote | Select-Object -First 40)
        options = @('create a new feature branch for this PBI', 'continue on the current branch', 'use an existing branch')
    }
}
function Invoke-GitSwitch([string]$root, [string[]]$gitArgs) {   # git writes "Switched to ..." to stderr, which Windows PowerShell 5.1 turns into an error under 'Stop'
    $keep = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $o = & git -C $root switch @gitArgs 2>&1 | Out-String } finally { $ErrorActionPreference = $keep }
    $o
}
function Test-BranchName([string]$n) {
    if ($n -notmatch '^[a-z0-9][a-z0-9._/-]{0,80}$' -or $n -match '\.\.|//|/$|\.lock$|-$') { return $false }
    $keep = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { & git check-ref-format --branch $n 2>&1 | Out-Null; $ok = ($LASTEXITCODE -eq 0) } finally { $ErrorActionPreference = $keep }
    $ok
}
# Repository development profiles (modules\profiles\profiles.json). At most one profile applies, and only when its
# solution file is in the repository; package, file, and code markers are supporting evidence, never enough alone.
$ProfilesDir = Join-Path $ModulesDir 'profiles'
$CustomProfilesDir = Join-Path $AkzoHome 'profiles-custom'   # the developer's own versions; the installer never writes here
$LearningDir = Join-Path $AkzoHome 'learning'   # lessons from PR reviews, one file per repository; the installer never writes here
$LessonClasses = 'ONE_TIME_FIX', 'REUSABLE_PATTERN', 'PROJECT_SPECIFIC_RULE', 'BUSINESS_RULE_CLARIFICATION', 'UNVERIFIED_FEEDBACK'
function Read-Profiles {
    $p = Join-Path $ProfilesDir 'profiles.json'
    $custom = Join-Path $CustomProfilesDir 'profiles.json'
    if (Test-Path -LiteralPath $custom -PathType Leaf) { $p = $custom }
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json
}
function Get-ProfileFile([string]$rel) {   # a file with the same relative path under profiles-custom wins
    $c = Join-Path $CustomProfilesDir $rel; $s = Join-Path $ProfilesDir $rel
    if (Test-Path -LiteralPath $c) { return [pscustomobject][ordered]@{ file = $rel; path = $c; source = 'custom' } }
    [pscustomobject][ordered]@{ file = $rel; path = $s; source = $(if (Test-Path -LiteralPath $s) { 'shipped' } else { 'MISSING' }) }
}
function Get-ProfileCacheKey($r, [string]$defsText) {   # HEAD + working-tree status + size/time of every changed file + the profile definitions
    $ErrorActionPreference = 'Continue'
    $sb = New-Object Text.StringBuilder
    [void]$sb.Append((Get-TextHash $defsText)).Append("`n")
    # One git process: porcelain v2 carries HEAD ('# branch.oid') and every changed, staged, renamed, or untracked path.
    foreach ($l in @(git -C $r.path -c core.quotepath=off status --porcelain=v2 --branch -uall 2>$null)) {
        [void]$sb.Append($l)
        $rel = switch ($l[0]) { '1' { $l.Split(' ', 9)[8] } '2' { $l.Split(' ', 10)[9].Split("`t")[0] } 'u' { $l.Split(' ', 11)[10] } '?' { $l.Substring(2) } default { '' } }
        $f = if ($rel) { Join-Path $r.path ($rel -replace '^"|"$', '') } else { '' }
        if ($f -and (Test-Path -LiteralPath $f -PathType Leaf)) { $i = Get-Item -LiteralPath $f; [void]$sb.Append("|$($i.Length)|$($i.LastWriteTimeUtc.Ticks)") }
        [void]$sb.Append("`n")
    }
    Get-TextHash $sb.ToString()
}
function Get-RepoProfile($r, [string]$want, [string]$intent, [string]$work) {
    $defs = Read-Profiles
    if (-not $defs) { return [pscustomobject][ordered]@{ status = 'NO_PROFILES_INSTALLED'; repo = $r.id; profile = ''; solutions = @(); detail = "no profiles.json under $ProfilesDir" } }
    # Detection is cached per repository; any commit, checkout, edit, new or deleted file, or profile change misses the cache.
    $cacheDir = Join-Path $AkzoHome "maps\$($r.id)"; $cacheFile = Join-Path $cacheDir 'profile-detection.json'
    $key = Get-ProfileCacheKey $r ("$($r.path)|" + ($defs | ConvertTo-Json -Depth 20 -Compress))
    $cached = Read-JsonOrRecover $cacheFile
    $cacheEvent = if ($cached.recovered) { 'recovered' } else { 'miss' }
    if ($cached.data -and $cached.data.schema -eq 1 -and $cached.data.key -eq $key) {
        $cacheEvent = 'hit'; $slns = @($cached.data.solutions | Where-Object { $_ })
        $found = @(foreach ($c in @($cached.data.found)) { [pscustomobject]@{ def = @($defs.profiles | Where-Object { $_.id -eq $c.id })[0]; solution = "$($c.solution)"; evidence = @($c.evidence | Where-Object { $_ }) } })
    } else {
    $files =@(Invoke-Quiet git -C $r.path -c core.quotepath=off ls-files --cached --others --exclude-standard)
    $slns = @($files | Where-Object { $_ -match '\.slnx?$' })
    $projText = (@($files | Where-Object { $_ -match '\.(cs|fs|vb)proj$|(^|/)(Directory\.Packages\.props|packages\.config)$' } | Select-Object -First 300 | ForEach-Object {
                try { [IO.File]::ReadAllText((Join-Path $r.path $_)) } catch { '' } }) -join "`n")
    $found = @(foreach ($d in @($defs.profiles)) {
            $sln = $slns | Where-Object { (($_ -split '/')[-1] -replace '\.slnx?$') -ieq ($d.solution -replace '\.slnx?$') } | Select-Object -First 1   # .sln and .slnx (Visual Studio 2026) are the same solution
            $ev = New-Object Collections.Generic.List[string]
            if ($sln) { $ev.Add("solution $sln") }
            foreach ($p in @($d.markers.packages | Where-Object { $_ })) { $m = [regex]::Match($projText, 'Include="(' + [regex]::Escape($p) + '[^"]*)"'); if ($m.Success) { $ev.Add("package $($m.Groups[1].Value)") } }
            foreach ($x in @($d.markers.files | Where-Object { $_ })) { $hit = $files | Where-Object { $_ -match $x } | Select-Object -First 1; if ($hit) { $ev.Add("file $hit") } }
            foreach ($t in @($d.markers.code | Where-Object { $_ })) { $hit = @(Invoke-Quiet git -C $r.path -c core.quotepath=off grep -l --untracked -w -F $t -- '*.cs') | Select-Object -First 1; if ($hit) { $ev.Add("code '$t' in $hit") } }
            [pscustomobject]@{ def = $d; solution = "$sln"; evidence = $ev.ToArray() }
        })
    try {   # the cache is optional: a failed write only costs the next call a detection
        New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null; Protect-Directory $cacheDir | Out-Null
        Write-TextAtomic $cacheFile ([pscustomobject]@{ schema = 1; key = $key; solutions = $slns; found = @($found | ForEach-Object { [pscustomobject]@{ id = $_.def.id; solution = $_.solution; evidence = $_.evidence } }) } | ConvertTo-Json -Depth 4)
    } catch { }
    }
    $withSln = @($found | Where-Object { $_.solution })
    $pick = $null
    if ($want) {
        $asked = $found | Where-Object { $_.def.id -eq $want } | Select-Object -First 1
        if (-not $asked) { throw "Unknown profile '$want' (known: $(@($defs.profiles | ForEach-Object { $_.id }) -join ', '))." }
        if ($asked.solution) { $pick = $asked; $status = 'CONFIRMED' } else { $status = 'NOT_CONFIRMED' }
    } elseif ($withSln.Count -eq 1) { $pick = $withSln[0]; $status = 'DETECTED' }
    elseif ($withSln.Count -gt 1) { $status = 'AMBIGUOUS' }
    elseif (@($found | Where-Object { $_.evidence.Count -ge 2 }).Count) { $status = 'UNCERTAIN' }   # one common package alone is no hint
    else { $status = 'NO_PROFILE' }
    $o = [ordered]@{ status = $status; repo = $r.id; profile = ''; name = ''; solution = ''; evidence = @()
        solutions = @($slns | ForEach-Object { ($_ -split '/')[-1] } | Select-Object -Unique)
        candidates = @($found | Where-Object { $_.evidence.Count } | ForEach-Object { [pscustomobject][ordered]@{ profile = $_.def.id; solution = "$($_.solution)"; evidence = $_.evidence } }) }
    $o.cache = $cacheEvent; $o.task = $(if ($work) { $work } else { 'new' })
    # Lazy loading: with -Query only the core files and the files whose topic matches the request are loaded; the rest of
    # the same profile is 'deferred' (read when the work reaches that topic). Without -Query everything is loaded.
    # -Task fix / refactor (small technical changes): only source grounding and the Sonar rules; refactor adds the topic matches.
    $lean = $work -in 'fix', 'refactor'
    $onDemand = @{}; if ($defs.shared.onDemand) { foreach ($pp in $defs.shared.onDemand.PSObject.Properties) { $onDemand[$pp.Name] = $pp.Value } }
    $wanted = { param($file, $rx) (-not $intent) -or ($rx -and $intent -match "(?i)$rx") }
    $sharedAll = @(@($defs.shared.skills | Where-Object { $_ }) + @($onDemand.Keys | Sort-Object | Where-Object { & $wanted $_ $onDemand[$_] }))
    $shared = @($sharedAll | Where-Object { -not $lean -or $_ -match 'source-grounded' })
    $deferred = @(@($sharedAll | Where-Object { $shared -notcontains $_ }) + @($onDemand.Keys | Sort-Object | Where-Object { -not (& $wanted $_ $onDemand[$_]) }))
    if ($pick) {
        $d = $pick.def
        $dir = if ($pick.solution -match '/') { Join-Path $r.path (($pick.solution -replace '/[^/]+$', '') -replace '/', '\') } else { $r.path }
        $missing = @($d.commandFiles | Where-Object { $_ -and -not (Test-Path -LiteralPath (Join-Path $dir $_)) })
        $o.profile = $d.id; $o.name = $d.name; $o.solution = $pick.solution; $o.evidence = $pick.evidence
        $core = @($d.core | Where-Object { $_ })
        $mine = @($d.skills | Where-Object { $_ -and $(if ($lean) { $work -eq 'refactor' -and $intent -and $d.triggers.$_ -and $intent -match "(?i)$($d.triggers.$_)" }
                    else { -not $intent -or $core -contains $_ -or (& $wanted $_ $d.triggers.$_) }) })
        $deferred += @($d.skills | Where-Object { $_ -and $mine -notcontains $_ })
        $o.load = @(@($shared) + $mine + @($d.sonarRules) | Where-Object { $_ } | ForEach-Object { Get-ProfileFile $_ })
        $o.deferred = @($deferred | ForEach-Object { Get-ProfileFile $_ })
        $o.neverLoad = @($defs.profiles | Where-Object { $_.id -ne $d.id } | ForEach-Object { @($_.skills) + @($_.sonarRules) } | Where-Object { $_ })
        $o.otherSolutions = @($defs.profiles | Where-Object { $_.id -ne $d.id } | ForEach-Object { $_.solution })
        $o.commands = [ordered]@{ workingDirectory = $dir; build = $d.commands.build; test = $d.commands.test; missingFiles = $missing; verified = (-not $missing.Count) }
        $o.review = $d.review
        $o.next = "Read every file in 'load' before investigating; $(if ($lean) { "read a 'deferred' file only when the $work reaches its topic, and say why in one line" } else { "read a 'deferred' file as soon as the work reaches its topic (when unsure, read it)" }); never read or apply 'neverLoad'. Run 'commands' from workingDirectory$(if ($missing.Count) { " after checking $($missing -join ', ') (not found next to the solution)" })."
    } else {
        $o.load = @($shared | ForEach-Object { Get-ProfileFile $_ })
        $o.deferred = @($deferred | ForEach-Object { Get-ProfileFile $_ })
        $o.neverLoad = @($defs.profiles | ForEach-Object { @($_.skills) + @($_.sonarRules) } | Where-Object { $_ })
        $o.next = switch ($status) {
            'AMBIGUOUS' { "Solutions of several profiles are here ($(@($withSln | ForEach-Object { $_.solution }) -join ', ')). Ask the developer which solution the work belongs to, then run profile -Repo $($r.id) -Key <profile>. Load no profile files before that." }
            'UNCERTAIN' { 'Profile markers were found but no profile solution file. Do not choose a profile from names or markers: follow the repository''s own patterns and the generic stack profiles, and tell the developer which solution was expected.' }
            'NOT_CONFIRMED' { "The solution of profile '$want' is not in this repository, so that profile is not applied. Inspect the solution files and ask the developer." }
            default { 'No repository profile applies: follow the repository''s own patterns and the generic stack profiles.' }
        }
    }
    [pscustomobject]$o
}
function Test-SolutionUse($r, [string]$line) {   # a dotnet command names a solution of this repository, never another profile's
    $named = @([regex]::Matches($line, '[^\s"''=;|&]+\.slnx?\b') | ForEach-Object { ($_.Value -split '[\\/]')[-1] } | Select-Object -Unique)
    if (-not $named.Count) { return $null }
    $p = Get-RepoProfile $r ''
    foreach ($n in $named) {
        if ($p.solutions -notcontains $n) { return [pscustomobject]@{ decision = 'BLOCK'; category = 'wrong-solution'; reason = "solution $n is not in repository $($r.id) (solutions here: $(@($p.solutions) -join ', '))" } }
        $other = @((Read-Profiles).profiles | Where-Object { $_.solution -ieq $n -and $_.id -ne $p.profile })
        if ($p.profile -and $other.Count) { return [pscustomobject]@{ decision = 'BLOCK'; category = 'wrong-solution'; reason = "solution $n belongs to the $($other[0].name) profile; repository $($r.id) is $($p.name)" } }
    }
    $null
}

function Get-ParamNames([string]$sig) {   # parameter names of the first parameter list in a C# signature
    $open = $sig.IndexOf('('); if ($open -lt 0) { return @() }
    $depth = 0; $buf = ''; $parts = New-Object Collections.Generic.List[string]
    for ($k = $open + 1; $k -lt $sig.Length; $k++) {
        $c = "$($sig[$k])"
        if ($c -eq ')' -and $depth -eq 0) { break }
        if ('(', '<', '[' -contains $c) { $depth++ } elseif (')', '>', ']' -contains $c) { $depth-- }
        if ($c -eq ',' -and $depth -eq 0) { $parts.Add($buf); $buf = '' } else { $buf += $c }
    }
    if ($buf.Trim()) { $parts.Add($buf) }
    @($parts | ForEach-Object { $x = (($_ -replace '\[[^\]]*\]', '') -replace '=.*$', '').Trim(); if ($x -match '(\w+)$') { $Matches[1] } })
}

# Pre-PR review: the recorded PR regression scenarios and the profile's rules, on the real diff (static; no build).
function Get-ChangeBase($r, [string]$base) {   # what a change is compared with: HEAD, or the merge base of -Base and HEAD
    if (-not $base) { return 'HEAD', 'uncommitted changes against HEAD only (committed work on the branch is not included; pass -Base <branch>)' }
    if ($base -notmatch '^\w[\w./~^-]*$') { throw "-Base '$base' is not a valid branch or commit name." }
    $mb = "$(Invoke-Quiet git -C $r.path merge-base $base HEAD)".Trim()
    if (-not $mb) { throw "Base '$base' was not found, or has no common history with HEAD." }
    $mb, "working tree against the merge base of $base and HEAD ($($mb.Substring(0, 10))): committed and uncommitted work"
}
function Get-BuildLogDir([string]$repoId) { Join-Path $AkzoHome "maps\$repoId\builds" }   # review reads the build logs here (owner-only, like the rest of maps)
function Get-BuildLogArg([string]$repoId, [string]$name) {   # one file log per build target; normal verbosity records the build's start time
    " ""-flp:LogFile=$(Join-Path (Get-BuildLogDir $repoId) "$name.log");Verbosity=normal"""
}
function Get-ProjectGraph([string]$root, [string[]]$files) {   # project file -> its folder, the projects it references (repo-relative), test or not; $files: a file list already read
    $proj = @{}
    $projFiles = if ($files) { @($files | Where-Object { $_ -match '\.(cs|fs|vb)proj$' }) } else { @(Invoke-Quiet git -C $root -c core.quotepath=off ls-files --cached --others --exclude-standard -- '*.csproj' '*.fsproj' '*.vbproj') }
    foreach ($pf in @($projFiles | Where-Object { Test-Path -LiteralPath (Join-Path $root $_) })) {
        $text = try { [IO.File]::ReadAllText((Join-Path $root $pf)) } catch { '' }
        $dir = if ($pf -match '/') { $pf -replace '/[^/]+$', '' } else { '' }
        $refs = @(foreach ($m in [regex]::Matches($text, 'ProjectReference\s+Include="([^"]+)"')) { Resolve-RelativePath $dir $m.Groups[1].Value })
        $isTest = ($text -match 'Microsoft\.NET\.Test\.Sdk|"xunit|"NUnit|"MSTest|<IsTestProject>\s*true') -or ($pf -match '(?i)[./]tests?[^/]*\.\w+proj$')
        $proj[$pf] = [pscustomobject]@{ path = $pf; dir = $dir; refs = $refs; test = $isTest }
    }
    $proj
}
function Resolve-RelativePath([string]$dir, [string]$rel) {   # 'src/Api' + '..\Data\Data.csproj' -> 'src/Data/Data.csproj'
    $parts = New-Object Collections.Generic.List[string]; if ($dir) { $parts.AddRange([string[]]($dir -split '/')) }
    foreach ($seg in ($rel -replace '\\', '/') -split '/') { if ($seg -eq '..') { if ($parts.Count) { $parts.RemoveAt($parts.Count - 1) } } elseif ($seg -and $seg -ne '.') { $parts.Add($seg) } }
    $parts -join '/'
}
function Get-ProjectDepth($proj, [string[]]$skipEdges) {   # project -> layer depth (0: references nothing); edges 'from|to' in $skipEdges are left out
    $depth = @{}
    $walk = $null; $walk = { param($p, $seen) if ($depth.ContainsKey($p)) { return $depth[$p] }; if ($seen -contains $p -or -not $proj.ContainsKey($p)) { return 0 }
        $d = 0; foreach ($t in @($proj[$p].refs | Where-Object { $skipEdges -notcontains "$p|$_" })) { $d = [math]::Max($d, 1 + (& $walk $t (@($seen) + $p))) }
        $depth[$p] = $d; $d }
    foreach ($p in $proj.Keys) { $null = & $walk $p @() }
    $depth
}
$PlacedRoles = 'endpoint', 'command', 'query', 'handler', 'validator', 'service', 'repository', 'mapping', 'model', 'ui', 'ui-service'
$RoleRegex = $null
# Role -> (folder pattern -> file count) for the placed roles, in one loop: a function call per file costs Windows
# PowerShell about five times the matching (measured on 612 files: 81 ms against 15 ms). Code files only (a project file
# such as Function.csproj is no endpoint). The pattern generalizes the feature segment, in ASCII for any console:
# src/Application/Orders/Commands/X.cs -> src/Application/*/Commands.
function Get-RoleHomes([string[]]$files) {
    if (-not $script:RoleRegex) { $script:RoleRegex = [ordered]@{}; foreach ($k in $ComponentRoles.Keys) { $script:RoleRegex[$k] = [regex]::new($ComponentRoles[$k], 'IgnoreCase') } }
    $code = [regex]'(?i)\.(cs|fs|vb|ts|tsx|js|jsx|vue|svelte|py|java|kt|go)$'; $skip = [regex]'(?i)(^|/)(bin|obj|node_modules|dist|\.angular|[Gg]enerated)/'; $slash = [char[]]'/'
    $homes = @{}
    foreach ($f in $files) {
        if (-not $code.IsMatch($f) -or $skip.IsMatch($f)) { continue }
        $role = $null; foreach ($k in $script:RoleRegex.Keys) { if ($script:RoleRegex[$k].IsMatch($f)) { $role = $k; break } }
        if ($PlacedRoles -notcontains $role) { continue }
        $i = $f.LastIndexOf('/'); $s = if ($i -gt 0) { $f.Substring(0, $i).Split($slash, [StringSplitOptions]::RemoveEmptyEntries) } else { @() }
        $h = if (-not $s.Count) { '.' } elseif ($s.Count -le 2) { $s -join '/' } elseif ($s.Count -eq 3) { "$($s[0])/$($s[1])/*" } else { "$($s[0])/$($s[1])/*/$($s[-1])" }
        if (-not $homes.ContainsKey($role)) { $homes[$role] = @{} }; $homes[$role][$h] = 1 + $homes[$role][$h]
    }
    $homes
}
# The repository's conventions as data (project and solution boundaries, dependency direction, where each component role
# lives), so a change can follow them. Derived from file names and project references, not from reading code.
function Get-ArchitectureConventions([string]$root, [string[]]$files) {
    $proj = Get-ProjectGraph $root $files; $depth = Get-ProjectDepth $proj @()
    $homes = Get-RoleHomes $files
    $name = { param($p) [IO.Path]::GetFileNameWithoutExtension($p) }   # compact: this goes into every task and issue output
    [pscustomobject][ordered]@{
        projects = (@($proj.Values | Where-Object { -not $_.test } | Sort-Object { $depth[$_.path] }, path | Select-Object -First 15 | ForEach-Object { "$(& $name $_.path) (depth $($depth[$_.path]))$(if ($_.refs.Count) { ' -> ' + (@($_.refs | ForEach-Object { & $name $_ }) -join ', ') })" }) -join '; ')
        roles = (@($PlacedRoles | Where-Object { $homes.ContainsKey($_) } | ForEach-Object { $hm = $homes[$_]; "${_}: " + (@($hm.Keys | Sort-Object { -$hm[$_] }, { $_ } | Select-Object -First 2 | ForEach-Object { "$_ ($($hm[$_]))" }) -join ', ') }) -join '; ')
        note = 'Depth 0 references nothing; confirm a convention in the closest sibling.' }
}
function Get-AffectedTests($r, [string]$against) {   # staged test selection: changed files -> owning projects -> dependent test projects
    $root = $r.path
    $changed = @(@(Invoke-Quiet git -C $root -c core.quotepath=off diff --name-only $against) + @(Invoke-Quiet git -C $root -c core.quotepath=off ls-files -o --exclude-standard) | Where-Object { $_ } | Sort-Object -Unique)
    $proj = Get-ProjectGraph $root
    $owner = { param($f) $best = $null; foreach ($k in $proj.Keys) { $d = $proj[$k].dir; if (($d -eq '' -or $f.StartsWith("$d/", [StringComparison]::OrdinalIgnoreCase)) -and ($null -eq $best -or $d.Length -gt $proj[$best].dir.Length)) { $best = $k } }; $best }
    $direct = New-Object 'Collections.Generic.HashSet[string]'; $global = New-Object Collections.Generic.List[string]; $focus = @{}
    foreach ($f in $changed) {
        $o = if ($proj.ContainsKey($f)) { $f } else { & $owner $f }
        if (-not $o -or ($proj[$o].dir -eq '' -and $f -notmatch '\.(cs|fs|vb)$')) { $global.Add($f); continue }   # build-wide files (solution, props, editorconfig, packages) narrow nothing
        [void]$direct.Add($o)
        if ($f -match '\.(cs|fs|vb)$') { $focus[$f] = $o }
    }
    # Reverse dependencies: every project that references a changed project, directly or through others.
    $affected = New-Object 'Collections.Generic.HashSet[string]'; foreach ($d in $direct) { [void]$affected.Add($d) }
    do { $grew = $false; foreach ($k in $proj.Keys) { if (-not $affected.Contains($k) -and @($proj[$k].refs | Where-Object { $affected.Contains($_) }).Count) { [void]$affected.Add($k); $grew = $true } } } while ($grew)
    # Focused tests: test classes named after a changed type (FooTests, FooTest, Foo_Tests), and changed test files themselves.
    $testFiles = @(Invoke-Quiet git -C $root -c core.quotepath=off ls-files --cached --others --exclude-standard -- '*.cs' '*.fs' '*.vb' | Where-Object { $tp = & $owner $_; $tp -and $proj[$tp].test })
    $filters = @{}; $untested = New-Object Collections.Generic.List[string]
    foreach ($f in @($focus.Keys | Sort-Object)) {
        $stem = ($f -split '/')[-1] -replace '\.\w+$', ''
        $hits = if ($proj[$focus[$f]].test) { @($f) } else { @($testFiles | Where-Object { (($_ -split '/')[-1] -replace '\.\w+$', '') -match "^$([regex]::Escape($stem))_?Tests?$" }) }
        if (-not $hits.Count) { $untested.Add($f) }
        foreach ($h in $hits) { $tp = & $owner $h; if (-not $filters.ContainsKey($tp)) { $filters[$tp] = New-Object Collections.Generic.List[string] }; $cls = ($h -split '/')[-1] -replace '\.\w+$', ''; if (-not $filters[$tp].Contains($cls)) { $filters[$tp].Add($cls) } }
    }
    $q = { param($x) '"' + ($x -replace '/', '\') + '"' }
    [pscustomobject][ordered]@{
        changed = $changed.Count; changedFiles = @($changed | Select-Object -First 50); projects = $proj.Count; testProjects = @($proj.Values | Where-Object { $_.test }).Count
        buildWide = @($global); directProjects = @($direct | Sort-Object); affectedProjects = @($affected | Sort-Object); untestedChanges = @($untested)
        build = @($direct | Sort-Object | ForEach-Object { "dotnet build $(& $q $_)$(Get-BuildLogArg $r.id (($_ -replace '\.\w+proj$', '') -replace '/', '-'))" })
        focused = @($filters.Keys | Sort-Object | ForEach-Object { "dotnet test $(& $q $_) --filter '$(@($filters[$_] | ForEach-Object { "FullyQualifiedName~$_" }) -join '|')'" })
        regression = @($affected | Where-Object { $proj[$_].test } | Sort-Object | ForEach-Object { "dotnet test $(& $q $_)" })
    }
}
function Get-DiffRisk($r, $def, [string]$against) {   # changed files ranked by the risk rules of profiles.json (shared + the detected profile only)
    $root = $r.path; $defs = Read-Profiles
    $rules = @(@($defs.shared.riskRules) + @($def.riskRules) | Where-Object { $_ })
    $churnMax = if ($defs.shared.riskChurnLines) { [int]$defs.shared.riskChurnLines } else { 200 }
    $churn = @{}
    foreach ($l in @(Invoke-Quiet git -C $root -c core.quotepath=off diff --numstat --no-renames $against)) {
        if ($l -match '^(\d+|-)\t(\d+|-)\t(.+)$') { $churn[$Matches[3]] = $(if ($Matches[1] -eq '-') { 0 } else { [int]$Matches[1] + [int]$Matches[2] }) }   # '-': binary
    }
    foreach ($u in @(Invoke-Quiet git -C $root -c core.quotepath=off ls-files --others --exclude-standard)) { $churn[$u] = @(Get-Content -LiteralPath (Join-Path $root $u) -ErrorAction SilentlyContinue).Count }
    $untested = @((Get-AffectedTests $r $against).untestedChanges)
    $rank = @{ high = 0; medium = 1; low = 2 }
    $out = foreach ($f in @($churn.Keys | Sort-Object)) {
        $hit = @($rules | Where-Object { $f -match $_.path })
        $level = 'low'; foreach ($h in $hit) { if ($rank[$h.level] -lt $rank[$level]) { $level = $h.level } }
        $why = @(@($hit | ForEach-Object { $_.reason }) + @(if ($untested -contains $f) { 'no test named after it' }) + @(if ($churn[$f] -gt $churnMax) { "$($churn[$f]) changed lines (over $churnMax)" }))
        [pscustomobject][ordered]@{ file = $f; level = $level; reasons = $why }
    }
    $note = if (-not @($def.riskRules | Where-Object { $_ }).Count) { "No profile risk rules$(if ($def) { " for $($def.id)" }): only the shared build-file rules apply; other files are low." } else { '' }
    [pscustomobject]@{ risk = @($out | Where-Object { $_ } | Sort-Object { $rank[$_.level] }, file); note = $note }
}
# Per changed C# file (staged, unstaged, or new): ANALYZED when its project compiled after the file's last write (the
# compiler runs the analyzers on every compile) inside a logged build (-flp at normal verbosity: between the log's 'Build
# started' time and its last write), with the file's warnings and errors read from that log; EXCLUDED when the compiler
# treats it as generated code (file name or <auto-generated> header: analyzers skip it) or never compiles it (bin, obj);
# otherwise NOT VERIFIED, never clean. A build that found nothing to compile logs no warnings, so its log proves nothing.
# shortcut: assumes RunAnalyzers is not switched off and ignores .editorconfig generated_code; read those when in doubt.
function Get-AnalysisStatus([string]$root, [string[]]$files, $changed, [string[]]$logs, [switch]$Rows) {   # -Rows: each ANALYZED file's diagnostics as data too (sonar -Check issues)
    $runs = @(foreach ($l in $logs) {
            $t = [IO.File]::ReadAllText($l); $d = @{}
            foreach ($m in [regex]::Matches($t, '(?m)^\s*(?:\d+>)?(?<f>[A-Za-z]:\\[^\r\n(]+?)\((?<l>\d+),(?<c>\d+)(?:,\d+,\d+)?\): (?<s>warning|error) (?<id>[A-Za-z]+\d+): (?<msg>[^\r\n]*?)(?: \[[^\]\r\n]*\])?\r?$')) {
                $k = $m.Groups['f'].Value.ToLowerInvariant(); if (-not $d.ContainsKey($k)) { $d[$k] = [ordered]@{} }
                $text = "$($m.Groups['s'].Value) $($m.Groups['id'].Value): $($m.Groups['msg'].Value)"
                $d[$k]["$($m.Groups['l'].Value)|$text"] = [pscustomobject]@{ line = [int]$m.Groups['l'].Value; column = [int]$m.Groups['c'].Value; severity = $m.Groups['s'].Value; id = $m.Groups['id'].Value; message = $m.Groups['msg'].Value; text = $text }   # inline and summary copies are one
            }
            $start = if ($t -match '(?m)^Build started (.+?)\.\r?$') { try { [datetime]::Parse($Matches[1]) } catch { $null } }
            [pscustomobject]@{ start = $start; end = (Get-Item -LiteralPath $l).LastWriteTime; diag = $d }
        })
    foreach ($f in $files) {
        $full = (Join-Path $root $f) -replace '/', '\'
        $row = [ordered]@{ file = $f; status = 'NOT VERIFIED'; project = ''; analyzers = ''; reason = '' }
        $head = try { $s = [IO.File]::ReadAllText($full); $s.Substring(0, [math]::Min(1500, $s.Length)) } catch { '' }
        if ($f -match '(?i)(^|/)(bin|obj)/') { $row.status = 'EXCLUDED'; $row.reason = 'build output: MSBuild does not compile files under bin or obj' }
        elseif ($f -match '(?i)\.(g|g\.i|designer|generated)\.cs$|(^|/)TemporaryGeneratedFile_' -or $head -match '(?i)<auto-?generated') { $row.status = 'EXCLUDED'; $row.reason = 'generated code by the compiler''s rule (file name or <auto-generated> header): analyzers skip it' }
        if ($row.status -eq 'EXCLUDED') { [pscustomobject]$row; continue }
        $dir = Split-Path $full; $proj = $null
        while ($dir -and $dir.Length -ge $root.Length) { $proj = Get-ChildItem -LiteralPath $dir -Filter *.csproj -File -ErrorAction SilentlyContinue | Select-Object -First 1; if ($proj) { break }; $dir = Split-Path $dir }
        if (-not $proj) { $row.reason = 'no project file contains this file'; [pscustomobject]$row; continue }
        $settings = @($proj.FullName) + @(for ($d = $proj.DirectoryName; $d -and $d.Length -ge $root.Length; $d = Split-Path $d) { Join-Path $d 'Directory.Build.props'; Join-Path $d 'Directory.Packages.props' }) | Where-Object { Test-Path -LiteralPath $_ }
        $sonar = [bool](@($settings | Where-Object { [IO.File]::ReadAllText($_) -match '(?i)PackageReference\s+Include="SonarAnalyzer\.CSharp"' }).Count)   # a PackageVersion entry only sets the version
        $row.project = $proj.FullName.Substring($root.Length).TrimStart('\', '/').Replace('\', '/')
        $row.analyzers = if ($sonar) { 'SonarAnalyzer.CSharp (its local rule set) and .NET analyzers' } else { '.NET analyzers only (no SonarAnalyzer.CSharp reference: Sonar rules not checked locally)' }
        $built = Get-ChildItem -LiteralPath (Join-Path $proj.DirectoryName 'obj') -Recurse -Filter *.dll -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
        if (-not $built -or $built.LastWriteTimeUtc -le (Get-Item -LiteralPath $full).LastWriteTimeUtc) { $row.reason = $(if ($built) { 'changed after the last compile: build the project' } else { 'project not built' }); [pscustomobject]$row; continue }
        $at = $built.LastWriteTime
        $run = @($runs | Where-Object { $_.start -and $_.start -le $at -and $_.end -ge $at } | Sort-Object start)[-1]
        if (-not $run) { $row.reason = "compiled $($at.ToString('s')) after the last change, but in no logged build$(if (-not $runs.Count) { ' (no build log found)' }); a build without the log, or one with nothing left to compile, records no warnings: run the affected stage A command with --no-incremental added, then review again"; [pscustomobject]$row; continue }
        $mine = @(if ($run.diag.ContainsKey($full.ToLowerInvariant())) { $run.diag[$full.ToLowerInvariant()].Values })
        $isChanged = { param($n) [bool]($changed -and $changed[$f] -and $changed[$f].Contains($n)) }
        $row.status = 'ANALYZED'; $row.reason = "compiled $($at.ToString('s')) in the logged build, after the last change"
        $row.diagnosticCount = $mine.Count; $row.onChangedLines = @($mine | Where-Object { & $isChanged $_.line }).Count
        $row.diagnostics = @($mine | Sort-Object { -not (& $isChanged $_.line) }, line | Select-Object -First 25 | ForEach-Object { "L$($_.line) $($_.text)$(if (& $isChanged $_.line) { ' [changed line]' })" })
        if ($Rows) { $row.rows = $mine }
        [pscustomobject]$row
    }
}

function Get-ReviewFindings($r, $def, [string]$against) {
    $root = $r.path
    $changed = Get-ChangedLines $root $against
    $rules = if ($def.review) { $def.review } else { [pscustomobject]@{ xmlDocs = 'convention'; maxLineLength = 0; broadCatch = '' } }
    $all = @(Invoke-Quiet git -C $root -c core.quotepath=off ls-files --cached --others --exclude-standard | Where-Object { Test-Path -LiteralPath (Join-Path $root $_) })   # not files moved or deleted in the working tree
    $testRx = '(?i)(^|/)[^/]*tests?[^/]*/|tests?\.cs$'
    $genRx = '(?i)(^|/)(bin|obj|generated)/|\.(g|generated|designer)\.cs$'
    $out = New-Object Collections.Generic.List[object]
    $add = { param($rule, $sev, $file, $line, $msg, $scenario) $out.Add([pscustomobject][ordered]@{ rule = $rule; severity = $sev; file = $file; line = $line; scenario = $scenario; message = $msg }) }
    $cs = @($changed.Keys | Where-Object { $_ -match '\.cs$' -and $_ -notmatch $genRx -and (Test-Path -LiteralPath (Join-Path $root $_)) } | Sort-Object)
    $prod = @($cs | Where-Object { $_ -notmatch $testRx })
    $lines = @{}; $set = @{}
    foreach ($p in $cs) {
        $lines[$p] = @([IO.File]::ReadAllLines((Join-Path $root $p)))
        $h = New-Object 'Collections.Generic.HashSet[int]'; foreach ($n in $changed[$p]) { [void]$h.Add($n) }; $set[$p] = $h
    }
    $isNew = { param($p) $set[$p].Count -ge $lines[$p].Count }

    # Scenarios 1-2: a function converts the validation exception although the exception middleware already does.
    $mw = @(Invoke-Quiet git -C $root -c core.quotepath=off grep -l --untracked -F 'IFunctionsWorkerMiddleware' -- '*.cs' | Where-Object { [IO.File]::ReadAllText((Join-Path $root $_)) -match 'ValidationException' })
    foreach ($p in $prod) {
        $t = $lines[$p]
        if (($t -join "`n") -notmatch '\[Function\(|HttpTrigger') { continue }
        foreach ($n in @($changed[$p] | Sort-Object -Unique)) {
            if ($n -gt $t.Count -or $t[$n - 1] -notmatch 'catch\s*\(\s*(?:[\w.]+\.)?(\w*ValidationException)\b') { continue }
            $ex = $Matches[1]; $verb = ''
            for ($i = $n - 1; $i -ge 1 -and $i -ge $n - 200; $i--) {
                if ($t[$i - 1] -match 'HttpTrigger') { $verb = (@([regex]::Matches((($t[($i - 1)..([math]::Min($i + 2, $t.Count - 1))]) -join ' '), '(?i)"(get|post|put|patch|delete)"') | ForEach-Object { $_.Groups[1].Value.ToUpper() }) -join '/'); break }
            }
            if (-not $mw.Count) { continue }
            $sc = if ($verb -match 'PUT') { 1 } elseif ($verb -match 'POST') { 2 } else { '' }
            & $add 'redundant-validation-conversion' 'error' $p $n "$(if ($verb) { "$verb function" } else { 'Function' }) converts $ex itself, but $($mw[0]) already translates it into the HTTP response. Trace function -> dispatcher -> handler -> validation -> middleware, and remove this conversion only if the middleware response keeps the field, message, status, and contract." $sc
        }
    }

    # Scenario 3: the same changed block twice (copied logic, or one review fix applied in two places).
    $win = 4; $seen = @{}; $lastEnd = @{}
    foreach ($p in $cs) {
        $t = $lines[$p]
        $sig = @($changed[$p] | Sort-Object -Unique | Where-Object { $_ -le $t.Count -and ($s = $t[$_ - 1].Trim()).Length -ge 8 -and $s -notmatch '^(using |//|/\*|\*|\[|#)|^[{}()\[\];,\s]*$' })
        for ($i = 0; $i + $win -le $sig.Count; $i++) {
            if ($sig[$i + $win - 1] - $sig[$i] -gt 2 * $win) { continue }
            $key = (@($i..($i + $win - 1) | ForEach-Object { $t[$sig[$_] - 1].Trim() -replace '\s+', ' ' })) -join "`n"
            if (-not $seen.ContainsKey($key)) { $seen[$key] = @{ p = $p; n = $sig[$i] }; continue }
            $first = $seen[$key]
            if ($first.p -eq $p -and $sig[$i] - $first.n -lt $win) { continue }
            if ($lastEnd.ContainsKey($p) -and $sig[$i] -le $lastEnd[$p]) { $lastEnd[$p] = $sig[$i + $win - 1]; continue }
            $lastEnd[$p] = $sig[$i + $win - 1]
            & $add 'duplicate-change' 'error' $p $sig[$i] "The same changed block also appears at $($first.p):$($first.n); keep one implementation." 3
        }
    }

    # Scenario 4: a validator that does not follow the sibling validators' FluentValidation pattern.
    $validators = @($all | Where-Object { $_ -match 'Validator\.cs$' -and $_ -notmatch $testRx -and $_ -notmatch $genRx })
    $near = { param($a, $b) $x = $a -split '/'; $y = $b -split '/'; $k = 0; while ($k -lt $x.Count -and $k -lt $y.Count -and $x[$k] -eq $y[$k]) { $k++ }; $k }
    foreach ($p in @($prod | Where-Object { $_ -match 'Validator\.cs$' })) {
        $sib = @($validators | Where-Object { $_ -ne $p } | Sort-Object { - (& $near $_ $p) } | Select-Object -First 40)
        if (-not $sib.Count) { continue }
        $st = @($sib | ForEach-Object { try { [IO.File]::ReadAllText((Join-Path $root $_)) } catch { '' } })
        $me = $lines[$p] -join "`n"
        $at = 1; for ($i = 0; $i -lt $lines[$p].Count; $i++) { if ($lines[$p][$i] -match '\bclass\s+\w+') { $at = $i + 1; break } }
        $half = [math]::Ceiling($sib.Count / 2)
        $abs = @($st | Where-Object { $_ -match 'AbstractValidator<' }).Count
        $rf = @($st | Where-Object { $_ -match '\bRuleFor\s*\(' }).Count
        $wm = @($st | Where-Object { $_ -match '\.WithMessage\s*\(' }).Count
        $th = @($st | Where-Object { $_ -match 'throw\s+new\s+\w*Exception' }).Count
        if ($abs -ge $half -and $me -notmatch 'AbstractValidator<') { & $add 'validator-pattern' 'error' $p $at "Does not derive from AbstractValidator<T>, as $abs of $($sib.Count) sibling validators do (closest: $($sib[0]))." 4 }
        elseif ($rf -ge $half -and $me -notmatch '\bRuleFor\s*\(') { & $add 'validator-pattern' 'error' $p $at "Has no RuleFor rules; $rf of $($sib.Count) sibling validators declare their rules with RuleFor (closest: $($sib[0]))." 4 }
        if (-not $th -and $me -match 'throw\s+new\s+\w*Exception') { & $add 'validator-pattern' 'error' $p $at 'Throws exceptions itself; no sibling validator does, they declare rules and let the validation pipeline report them.' 4 }
        if ($wm -ge $half -and $me -match '\bRuleFor\s*\(' -and $me -notmatch '\.WithMessage\s*\(') { & $add 'validator-pattern' 'warning' $p $at "Sets no messages; $wm of $($sib.Count) sibling validators set them with WithMessage." 4 }
    }

    # Scenario 5: command and query dependencies in the wrong place.
    $kindOf = { param($p) if ($p -match '(?i)(^|/)commands?/') { 'command' } elseif ($p -match '(?i)(^|/)quer(y|ies)/') { 'query' } else { '' } }
    foreach ($p in $prod) {
        $k = & $kindOf $p; if (-not $k) { continue }
        $t = $lines[$p]; $new = & $isNew $p
        for ($i = 0; $i -lt $t.Count; $i++) {
            if ($t[$i] -notmatch '^\s*(?:(?:public|internal|sealed|abstract|static|partial|file)\s+)*(?:class|record|interface|struct|enum)\s+(\w+)') { continue }
            $name = $Matches[1]
            if (-not $new -and -not $set[$p].Contains($i + 1)) { continue }
            if (($k -eq 'command' -and $name -match 'Query(Handler|Validator|Response|Result)?$') -or ($k -eq 'query' -and $name -match 'Command(Handler|Validator|Response|Result)?$')) {
                & $add 'dependency-organization' 'error' $p ($i + 1) "$name is placed in a $k folder; put it with the other $(if ($k -eq 'command') { 'query' } else { 'command' }) types of this feature." 5; continue
            }
            if ($name -match '(Command|Query)(Handler|Validator|Response|Result|Dto)?$|Handler$|Validator$') { continue }
            $other = if ($k -eq 'command') { 'query' } else { 'command' }
            $cross = @(Invoke-Quiet git -C $root -c core.quotepath=off grep -l --untracked -w -F $name -- '*.cs' | Where-Object { $_ -ne $p -and $_ -notmatch $testRx -and (& $kindOf $_) -eq $other })
            if ($cross.Count) { & $add 'dependency-organization' 'error' $p ($i + 1) "$name lives in a $k folder but $other code uses it ($($cross[0])); keep a dependency shared by commands and queries where sibling features keep shared dependencies." 5 }
        }
    }

    # Scenario 6: missing or outdated XML documentation on changed public members.
    $mode = "$($rules.xmlDocs)"
    foreach ($p in $prod) {
        $t = $lines[$p]; $h = $set[$p]; $text = $t -join "`n"
        $iface = $text -match '\binterface\s+\w+'
        $conv = $null
        for ($i = 0; $i -lt $t.Count; $i++) {
            $l = $t[$i]; $kind = ''; $name = ''; $ret = ''
            if ($l -match '^\s*public\s+(?:(?:static|sealed|abstract|partial|readonly|ref|unsafe)\s+)*(?:class|record|interface|struct|enum)\s+(\w+)') { $kind = 'type'; $name = $Matches[1] }
            elseif ($l -match '^\s*public\s+(?:(?:static|virtual|override|abstract|async|sealed|new|extern|unsafe|partial|readonly)\s+)*(?:(?<ret>[\w.?\[\],]+(?:<[^()]*>)?\??)\s+)?(?<name>\w+)\s*(?:<[^()]*>)?\s*\(') { $kind = 'method'; $name = $Matches['name']; $ret = "$($Matches['ret'])" }
            elseif ($l -match '^\s*public\s+(?:(?:static|virtual|override|abstract|new|required)\s+)*[\w.?\[\],]+(?:<[^()]*>)?\??\s+(\w+)\s*(\{|=>|$)') { $kind = 'property'; $name = $Matches[1] }
            elseif ($iface -and $l -match '^\s+(?<ret>[\w.?\[\],]+(?:<[^()]*>)?\??)\s+(?<name>\w+)\s*(?:<[^()]*>)?\s*\(' -and $l -notmatch '^\s*(return|await|new|if|for|foreach|while|switch|using|var|throw|public|private|protected|internal)\b') { $kind = 'method'; $name = $Matches['name']; $ret = "$($Matches['ret'])" }
            if (-not $kind) { continue }
            $end = $i
            if ($kind -eq 'method') { $sigText = $l; while (($sigText.Split('(').Count -gt $sigText.Split(')').Count) -and $end -lt [math]::Min($t.Count - 1, $i + 15)) { $end++; $sigText += ' ' + $t[$end].Trim() } }
            $j = $i - 1; while ($j -ge 0 -and $t[$j] -match '^\s*\[') { $j-- }
            $docTop = $j; while ($docTop -ge 0 -and $t[$docTop] -match '^\s*///') { $docTop-- }
            $doc = if ($j -gt $docTop) { ($t[($docTop + 1)..$j]) -join "`n" } else { '' }
            $touched = $false; for ($x = $docTop + 2; $x -le $end + 1; $x++) { if ($h.Contains($x)) { $touched = $true; break } }
            if (-not $touched) { continue }
            if ($doc -match '<inheritdoc') { continue }
            if ($doc -notmatch '<summary>') {
                if ($null -eq $conv) {
                    $dir = $p -replace '/?[^/]+$', ''
                    $conv = ($mode -eq 'required') -or ($text -match '///\s*<summary>') -or [bool](@($all | Where-Object { ($_ -replace '/?[^/]+$', '') -eq $dir -and $_ -ne $p -and $_ -match '\.cs$' } | Select-Object -First 10 | Where-Object { [IO.File]::ReadAllText((Join-Path $root $_)) -match '///\s*<summary>' }).Count)
                }
                & $add 'xml-doc-missing' $(if ($conv) { 'error' } else { 'warning' }) $p ($i + 1) "Public $kind $name has no XML documentation$(if ($mode -eq 'required') { ' (required by this profile)' } elseif ($conv) { ' (the surrounding code documents its public members)' })." 6
                continue
            }
            if ($kind -ne 'method') { continue }
            $params = @(Get-ParamNames $sigText)
            $documented = @([regex]::Matches($doc, '<param\s+name="(\w+)"') | ForEach-Object { $_.Groups[1].Value })
            $gone = @($documented | Where-Object { $params -notcontains $_ })
            $undoc = @($params | Where-Object { $documented -notcontains $_ })
            if ($gone.Count -or $undoc.Count) {   # one finding per signature: stale names and undocumented parameters together
                $what = @(if ($gone.Count) { "names parameter(s) $($gone -join ', ') that the signature does not have" }; if ($undoc.Count) { "has no <param> for $($undoc -join ', ')" }) -join ' and '
                $stale = $gone.Count -or $documented.Count
                & $add $(if ($stale) { 'xml-doc-outdated' } else { 'xml-doc-incomplete' }) $(if ($stale -or $mode -eq 'required') { 'error' } else { 'warning' }) $p ($i + 1) "XML documentation of $name $what; update it with the signature." 6
            }
            if ($mode -eq 'required' -and $ret -and $ret -notmatch '^(void|Task|ValueTask)$' -and $doc -notmatch '<returns>') { & $add 'xml-doc-incomplete' 'error' $p ($i + 1) "XML documentation of $name has no <returns>." 6 }
        }
    }

    # A newly added collaborator, helper, wrapper, or similar type (or its interface) that at most one other production file uses.
    foreach ($p in @($prod | Where-Object { & $isNew $_ })) {
        $t = $lines[$p]
        for ($i = 0; $i -lt $t.Count; $i++) {
            if ($t[$i] -notmatch '^\s*(?:(?:public|internal|sealed|static|partial)\s+)*(?:class|interface|record)\s+(\w+(?:Collaborator|Helper|Wrapper|Manager|Provider|Factory|Container|Dependencies|Utility|Utils))\b') { continue }
            $name = $Matches[1]
            $users = @(Invoke-Quiet git -C $root -c core.quotepath=off grep -l --untracked -w -F $name -- '*.cs' | Where-Object { $_ -ne $p -and $_ -notmatch $testRx -and $_ -notmatch $genRx })
            if ($users.Count -le 1) { & $add 'single-use-abstraction' 'warning' $p ($i + 1) "New type $name is used by $(if ($users.Count) { "only $($users[0])" } else { 'no other production file' }). Reuse an existing equivalent or keep the logic with its one consumer, unless sibling features use the same kind of type." '' }
        }
    }

    # Approved lessons from earlier PR reviews of this repository: a new type that repeats a corrected mistake is an error.
    $ls = Read-Lessons $r.id
    if ($ls.error) { & $add 'lesson-file-invalid' 'warning' $ls.file 0 "The lessons file cannot be read ($($ls.error)); no lesson was applied. Restore or fix it." '' }
    $declRx = '^\s*(?:(?:public|internal|sealed|static|partial|abstract)\s+)*(?:class|interface|record)\s+(\w+)'
    $decls = $null
    foreach ($l in @($ls.lessons | Where-Object { $_.status -eq 'approved' -and "$($_.check.kind)" -eq 'reuse-before-new' -and -not (Test-LessonCheck $_.check) -and ("$($_.profile)" -in '', 'shared' -or "$($_.profile)" -eq "$($def.id)") })) {
        $tp = "$($l.check.typePattern)"
        $ref = "$(@($l.occurrences | ForEach-Object { $_.reference } | Where-Object { $_ }) | Select-Object -First 1)"
        foreach ($p in @($prod | Where-Object { & $isNew $_ })) {
            for ($i = 0; $i -lt $lines[$p].Count; $i++) {
                if ($lines[$p][$i] -notmatch $declRx) { continue }
                $nm = $Matches[1]; if ($nm -notmatch $tp) { continue }
                if ($null -eq $decls) {   # every type declared in tracked production code, read once and only when needed
                    $decls = @(foreach ($g in @(Invoke-Quiet git -C $root -c core.quotepath=off grep -n -E '(class|interface|record)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' -- '*.cs')) {
                            if ($g -match '^(.+?):(\d+):(.*)$' -and $Matches[3] -match $declRx) { [pscustomobject]@{ file = ($g -split ':\d+:', 2)[0]; name = $Matches[1] } } })
                    $decls = @($decls | Where-Object { $_.file -notmatch $testRx -and $_.file -notmatch $genRx -and -not ($set.ContainsKey($_.file) -and (& $isNew $_.file)) })
                }
                $same = @($decls | Where-Object { $_.name -ne $nm -and $_.name -match $tp } | Sort-Object { $_.name -like 'I*' }, file)
                if ($same.Count) { & $add "lesson:$($l.key)" 'error' $p ($i + 1) "New type $nm repeats a mistake corrected in an earlier PR review$(if ($ref) { " ($ref)" }): $($l.title) $($same[0].name) in $($same[0].file) already exists; reuse it, or record in the plan why it cannot serve this case." '' }
            }
        }
    }

    # Profile rules and hygiene on changed lines of production code.
    $mx = [int]$rules.maxLineLength
    foreach ($p in $prod) {
        $t = $lines[$p]
        foreach ($n in @($changed[$p] | Sort-Object -Unique)) {
            if ($n -gt $t.Count) { continue }
            $l = $t[$n - 1]
            if ($mx -gt 0 -and $l.Length -gt $mx) { & $add 'line-length' 'error' $p $n "Line has $($l.Length) characters; this profile allows $mx." '' }
            if ($l -match 'throw\s+new\s+NotImplementedException|\b(TODO|FIXME)\b|\bPLACEHOLDER\b|<Your\w*>|\{\{\s*\w+\s*\}\}') { & $add 'placeholder' 'error' $p $n 'Placeholder or unfinished code in a change that is about to be reviewed.' '' }
            if ($rules.broadCatch -and $l -match 'catch\s*\(\s*(System\.)?Exception\b|^\s*catch\s*(\{|$)') { & $add 'broad-catch' "$($rules.broadCatch)" $p $n 'Catches every exception; catch only what this code handles, as sibling code at this layer does.' '' }
        }
    }
    foreach ($p in @($all | Where-Object { $_ -match '(?i)\.cs$' -and $_ -match $genRx -and $_ -notmatch '(?i)(^|/)(bin|obj)/' })) {
        if ((Get-Item -LiteralPath (Join-Path $root $p)).Length -eq 0) { & $add 'generated-empty' 'error' $p 0 'Generated file is empty: code generation failed or was interrupted. Rerun the repository''s generation command and build; never hand-edit or pick a side of a generated file.' '' }
    }
    # The developer's own regex rules (profiles-custom\review-rules.json) on changed lines; a bad file or rule is a warning, never a crash.
    $crFile = Join-Path $CustomProfilesDir 'review-rules.json'
    if (Test-Path -LiteralPath $crFile) {
        $parsed = try { Get-Content -LiteralPath $crFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch { & $add 'custom-rule-invalid' 'warning' $crFile 0 "review-rules.json is not valid JSON ($($_.Exception.Message)); no custom rule was applied." ''; $null }
        foreach ($c in $parsed) {   # foreach, not @(): ConvertFrom-Json in 5.1 emits a JSON array as one object
            $rx = $null
            $why = if (-not "$($c.id)") { 'no id' } elseif ("$($c.severity)" -notin 'error', 'warning') { "severity '$($c.severity)' is not error or warning" } elseif (-not "$($c.regex)") { 'no regex' } elseif (-not "$($c.message)") { 'no message' } else { '' }
            if (-not $why) { try { $rx = [regex]::new("$($c.regex)", [Text.RegularExpressions.RegexOptions]::None, [TimeSpan]::FromSeconds(1)) } catch { $why = "the regex does not compile ($($_.Exception.GetBaseException().Message))" } }
            if ($why) { & $add 'custom-rule-invalid' 'warning' $crFile 0 "Custom rule $(if ($c.id) { "'$($c.id)' " })skipped: $why." ''; continue }
            if ($c.profile -and "$($c.profile)" -ne '*' -and "$($c.profile)" -ne "$($def.id)") { continue }
            $glob = if ($c.pathGlob) { "$($c.pathGlob)" } else { '*' }
            foreach ($p in @($changed.Keys | Where-Object { $_ -like $glob -and $_ -notmatch $genRx } | Sort-Object)) {
                $full = Join-Path $root $p; if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }
                $t = if ($lines.ContainsKey($p)) { $lines[$p] } else { @([IO.File]::ReadAllLines($full)) }
                try { foreach ($n in @($changed[$p] | Sort-Object -Unique)) { if ($n -le $t.Count -and $rx.IsMatch($t[$n - 1])) { & $add "custom:$($c.id)" "$($c.severity)" $p $n (Protect-Text "$($c.message)") '' } } }
                catch { & $add 'custom-rule-invalid' 'warning' $crFile 0 "Custom rule '$($c.id)' stopped on $p (the regex took too long); simplify the pattern." ''; break }
            }
        }
    }
    foreach ($c in @(Invoke-Quiet git -C $root -c core.quotepath=off diff --check $against)) {
        if ($c -match '^(.+?):(\d+):\s*(.+)$') { & $add 'diff-check' 'error' $Matches[1] ([int]$Matches[2]) "git diff --check: $($Matches[3])" '' }
    }
    # Project architecture: a new file of a component role outside every folder where that role already lives (when the role
    # has at least three files), and a new project reference that points up the dependency direction the other references set.
    $added = @(@(Invoke-Quiet git -C $root -c core.quotepath=off diff --name-only --diff-filter=A $against) + @(Invoke-Quiet git -C $root -c core.quotepath=off ls-files -o --exclude-standard) | Where-Object { $_ -and $_ -notmatch $genRx } | Sort-Object -Unique)
    $addedSet = New-Object 'Collections.Generic.HashSet[string]' (, [string[]]@($added))
    $roleHomes = Get-RoleHomes @(foreach ($f in $all) { if (-not $addedSet.Contains($f) -and $f -notmatch $genRx) { $f } })   # where each role lives before the change
    foreach ($f in $added) {
        $one = Get-RoleHomes @($f); if (-not $one.Count) { continue }
        $ro = @($one.Keys)[0]; $h = @($one[$ro].Keys)[0]
        if (-not $roleHomes.ContainsKey($ro)) { continue }
        $hm = $roleHomes[$ro]
        if (($hm.Values | Measure-Object -Sum).Sum -ge 3 -and -not $hm.ContainsKey($h)) { & $add 'architecture:placement' 'warning' $f 1 "New $ro in $h, where no $ro of this repository lives; the others live in $(@($hm.Keys | Sort-Object { -$hm[$_] }, { $_ } | Select-Object -First 3) -join ', '). Follow them, or justify the new place." '' }
    }
    $projChanged = @($changed.Keys | Where-Object { $_ -match '\.(cs|fs|vb)proj$' -and (Test-Path -LiteralPath (Join-Path $root $_)) })
    if ($projChanged.Count) {
        $graph = Get-ProjectGraph $root
        $newEdges = @(foreach ($p in $projChanged) {
                $pl = @([IO.File]::ReadAllLines((Join-Path $root $p)))
                foreach ($n in $changed[$p]) { if ($n -le $pl.Count -and $pl[$n - 1] -match 'ProjectReference\s+Include="([^"]+)"') { [pscustomobject]@{ from = $p; to = (Resolve-RelativePath $graph[$p].dir $Matches[1]); line = $n } } } })
        $depth = Get-ProjectDepth $graph @($newEdges | ForEach-Object { "$($_.from)|$($_.to)" })   # the direction before these references
        foreach ($e in $newEdges) {
            if ($depth.ContainsKey($e.to) -and $depth[$e.to] -gt $depth[$e.from]) { & $add 'architecture:dependency' 'warning' $e.from $e.line "$($e.from) now references $($e.to), which sits above it in the existing dependency direction (depth $($depth[$e.to]) over $($depth[$e.from])). Keep references pointing down, or justify the new direction." '' }
        }
    }
    [pscustomobject]@{ files = $changed.Count; reviewed = $cs.Count; findings = $out.ToArray(); changed = $changed; changedCs = @($changed.Keys | Where-Object { $_ -match '(?i)\.cs$' -and (Test-Path -LiteralPath (Join-Path $root $_)) } | Sort-Object) }
}

# pick: choose a requirement document (file dialog unless -Source), convert it, and drop it in the inbox as
# <inbox>\<name>\refined-pbi.md with the original under source\. The selected file itself is never changed.
function Out-PickFailed([string]$why) {
    [pscustomobject][ordered]@{ status = 'PICK_FAILED'; error = $why; inbox = $InboxDir
        alternatives = @('give me the full path of the refined PBI file and I will run: pick -Source "<path>" [-Supporting "<path>;<path>"]', 'double-click Start-Development.cmd in the Akzo Master Agent folder (same two dialogs)', "drop the file in $InboxDir and say start") } | ConvertTo-Json -Depth 3
    exit 0
}
function Invoke-PickCommand {
    if (-not $Source) {
      try {
        if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') { throw 'The file dialog needs an STA thread: run with Windows PowerShell (powershell.exe) or pass -Source.' }
        Add-Type -AssemblyName System.Windows.Forms
        $dlg = New-Object Windows.Forms.OpenFileDialog
        $dlg.Title = 'Akzo Master SDD - select the refined PBI or requirement document'
        $dlg.Filter = 'Requirement documents (*.md;*.txt;*.docx;*.pdf)|*.md;*.markdown;*.txt;*.docx;*.pdf|All files (*.*)|*.*'
        $owner = New-Object Windows.Forms.Form -Property @{ TopMost = $true; ShowInTaskbar = $false; Width = 1; Height = 1; StartPosition = 'CenterScreen' }   # keeps the dialog in front of the IDE
        try {
            $ok = $dlg.ShowDialog($owner) -eq [Windows.Forms.DialogResult]::OK
            if ($ok -and -not $Supporting) {   # second, optional dialog: any number of supporting documents (Cancel = none)
                $more = New-Object Windows.Forms.OpenFileDialog
                $more.Title = 'Akzo Master SDD - optional: select supporting documents (Cancel = none)'
                $more.Multiselect = $true
                $more.InitialDirectory = Split-Path $dlg.FileName
                $more.Filter = 'All files (*.*)|*.*'
                if ($more.ShowDialog($owner) -eq [Windows.Forms.DialogResult]::OK) { $Supporting = $more.FileNames -join ';' }
            }
        } finally { $owner.Dispose() }
        if (-not $ok) { [pscustomobject]@{ status = 'CANCELLED'; inbox = $InboxDir; next = 'Nothing was selected and nothing was created. Respect the cancellation; use a later supplied file path without repeating intake questions.' } | ConvertTo-Json; exit 0 }
        $Source = $dlg.FileName
      } catch { Out-PickFailed "$($_.Exception.Message)" }
    }
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) { Out-PickFailed "File not found: $Source" }
    $pbiItem = (Get-Item -LiteralPath $Source)
    $text = (ConvertTo-PbiText $pbiItem.FullName).Trim()
    if (($text -replace '\s', '').Length -lt 40) { throw "'$($pbiItem.Name)' holds almost no text ($($text.Length) characters); choose the refined PBI document." }
    $name = ($pbiItem.BaseName -replace '[^A-Za-z0-9._ -]', '').Trim()
    if (-not $name) { $name = 'pbi' }
    $dest = Join-Path $InboxDir $name
    for ($n = 2; Test-Path -LiteralPath $dest; $n++) { $dest = Join-Path $InboxDir "$name-$n" }   # a new folder per pick
    New-Item -ItemType Directory -Force -Path (Join-Path $dest 'source') | Out-Null
    [IO.File]::WriteAllText((Join-Path $dest 'refined-pbi.md'), $text + "`n", (New-Object Text.UTF8Encoding($false)))
    Copy-Item -LiteralPath $pbiItem.FullName (Join-Path $dest "source\$($pbiItem.Name)")
    Add-Content -LiteralPath (Join-Path $dest '.origins.tsv') -Value "source\$($pbiItem.Name)`t$($pbiItem.FullName)" -Encoding UTF8
    $added = @(foreach ($s in @($Supporting -split ';' | Where-Object { $_.Trim() })) { Copy-Managed $s.Trim() $dest })
    [pscustomobject]@{ status = 'PICKED'; selected = $pbiItem.FullName; supporting = $added; item = (Get-InboxItem (Get-Item -LiteralPath $dest)); registeredRepos = @(Get-Registry | ForEach-Object { $_.id }) } | ConvertTo-Json -Depth 3
    exit 0
}

# intake: copy a refined PBI (file, or folder with notes) into <tasks>\<repo>\<id>\, then continue as 'task'.
function Invoke-IntakeCommand {
    if (-not $Source -or -not $Id -or -not $Repo) { throw 'intake needs -Source <file or folder>, -Id <PBI number>, -Repo <repo id>, and -Title "<PBI title>".' }
    if ($Id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') { throw "Work-item id '$Id' must be a folder name such as PBI-12345 (letters, digits, '.', '_', '-')." }
    if (-not (Get-Registry | Where-Object { $_.id -eq $Repo })) { throw "Repository '$Repo' is not in $Registry. Registered: $((Get-Registry | ForEach-Object { $_.id }) -join ', ')" }
    $auth = Get-Authorization (Resolve-Repo $Repo)   # preflight before any document is copied for this repository
    if (Get-PreflightRefusal $auth) { Out-Task (Get-PreflightRefusal $auth) ([ordered]@{ repo = $Repo; id = $Id; authorization = $auth }); exit 0 }
    if (-not (Test-Path -LiteralPath $Source)) { throw "Source not found: $Source" }
    $src = Get-Item -LiteralPath $Source
    $pbiSrc = if ($src.PSIsContainer) { Find-PbiFile $src.FullName } else { $src.FullName }
    if (-not $pbiSrc) { throw "Cannot tell which file in '$Source' is the refined PBI. Name it refined-pbi.md." }
    $dest = Join-Path $TasksDir "$Repo\$Id"
    $destPbi = Join-Path $dest 'refined-pbi.md'
    if ((Test-Path -LiteralPath $destPbi) -and -not $Resume) {   # new development never silently resumes an existing task
        $sum = Get-TaskSummary ([pscustomobject]@{ id = $Id; dir = $dest; json = $(try { Get-Content -LiteralPath (Join-Path $dest 'task.json') -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $null }); modified = (Get-Item -LiteralPath $dest).LastWriteTime })
        $next = 2; while (Test-Path -LiteralPath (Join-Path $TasksDir "$Repo\$Id-$next")) { $next++ }
        Out-Task 'TASK_EXISTS' ([ordered]@{ repo = $Repo; id = $Id; existing = $sum; suggestedNewId = "$Id-$next"
                choices = @('resume this task (rerun intake with -Resume)', "modify it (snapshot first, then intake with -Resume)", "separate task (rerun intake with -Id $Id-$next)") }); exit 0
    }
    if ((Test-Path -LiteralPath $destPbi) -and (Get-FileHash -LiteralPath $destPbi).Hash -ne (Get-FileHash -LiteralPath $pbiSrc).Hash) {
        throw "Task $Repo\$Id already has a different refined-pbi.md ($destPbi). Edit that file and resume, or use another PBI number."
    }
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Copy-Item -LiteralPath $pbiSrc $destPbi -Force
    $copied = @()
    if ($src.PSIsContainer) {   # supporting notes come along; existing files in the task are never overwritten
        foreach ($f in Get-ChildItem -LiteralPath $src.FullName -Recurse -File -Force | Where-Object { $_.FullName -ne $pbiSrc }) {
            $rel = $f.FullName.Substring($src.FullName.Length + 1)
            $to = Join-Path $dest $rel
            if ($rel -eq '.origins.tsv') { Add-Content -LiteralPath $to -Value (Get-Content -LiteralPath $f.FullName -Encoding UTF8) -Encoding UTF8; continue }
            if (Test-Path -LiteralPath $to) {
                if ((Get-FileHash -LiteralPath $to).Hash -eq (Get-FileHash -LiteralPath $f.FullName).Hash) { $copied += [pscustomobject]@{ file = $rel; status = 'duplicate' }; continue }
                $n = 2; do { $to = Join-Path (Split-Path $to) ("{0}-{1}{2}" -f $f.BaseName, $n++, $f.Extension) } while (Test-Path -LiteralPath $to)
                $copied += [pscustomobject]@{ file = $to.Substring($dest.Length + 1); status = 'renamed' }
            }
            New-Item -ItemType Directory -Force -Path (Split-Path $to) | Out-Null; Copy-Item -LiteralPath $f.FullName $to
        }
    }
    if (-not $Feature) { $Feature = Get-SpecFolderName $Id $Title }   # <id>-<title>: unique per work item
    $Command = 'task'
    Invoke-OtherCommand   # continue as 'task'; it sees this function's variables
}

# attach: add supporting documents to an existing task (managed copies), then report as 'task'.
$attached = $null
function Invoke-AttachCommand {
    if (-not $Id -or -not $Source) { throw 'attach needs -Id <PBI number> and -Source "<file>[;<file>...]".' }
    $dir = Find-TaskDir $Id $Repo
    $auth = Get-Authorization (Resolve-Repo (Split-Path (Split-Path $dir) -Leaf))   # preflight before documents are copied
    if (Get-PreflightRefusal $auth) { Out-Task (Get-PreflightRefusal $auth) ([ordered]@{ repo = $auth.repo; id = $Id; authorization = $auth }); exit 0 }
    $attached = @(foreach ($s in @($Source -split ';' | Where-Object { $_.Trim() })) { Copy-Managed $s.Trim() $dir })
    $Repo = Split-Path (Split-Path $dir) -Leaf
    $Command = 'task'
    Invoke-OtherCommand   # continue as 'task'; it sees this function's variables
}

# role: the developer corrects the role guessed for one input; kept on later runs.
function Invoke-RoleCommand {
    if (-not $Id -or -not $File -or -not $Role) { throw "role needs -Id <PBI>, -File <input path as listed>, and -Role <$($InputRoles -join '|')>." }
    if ($Role -notin $InputRoles) { throw "Unknown role '$Role'. Use one of: $($InputRoles -join ', ')." }
    $dir = Find-TaskDir $Id $Repo
    $m = Sync-InputManifest $dir
    $hit = @($m.entries | Where-Object { $_.file -eq $File -or $_.originalName -eq $File })
    if ($hit.Count -ne 1) { throw "Input '$File' matches $($hit.Count) entries in $($m.path); use the path shown in the input index." }
    $hit[0].role = $Role; $hit[0].roleSetBy = 'user'
    [IO.File]::WriteAllText($m.path, ([pscustomobject]@{ workItem = $Id; files = @($m.entries) } | ConvertTo-Json -Depth 4), $Utf8NoBom)
    $hit[0] | Select-Object file, role, roleSetBy | ConvertTo-Json
    exit 0
}

# discover: rebuild a repository's architecture index now (normally refreshed automatically when HEAD moves).
function Invoke-DiscoverCommand {
    $rr = Resolve-Repo $Repo
    $null = Assert-Preflight $rr
    Sync-Architecture $rr -Force | ConvertTo-Json
    exit 0
}

# policy: the preflight for one repository (no repository content is read).
function Invoke-PolicyCommand {
    $r = Resolve-Repo $Repo
    $a = Get-Authorization $r
    $a | Add-Member -NotePropertyName preflight -NotePropertyValue $(if (Get-PreflightRefusal $a) { Get-PreflightRefusal $a } else { 'OK' })
    $a | Add-Member -NotePropertyName note -NotePropertyValue 'AUTHORIZED comes from a policy file; ATTESTED is the developer''s recorded statement. Neither is verified corporate approval unless the policy is administrator-managed (managed: true).'
    $a | ConvertTo-Json -Depth 3
    exit 0
}

# authorize: record the developer's statement that processing this repository is authorized (with the reference they hold).
function Invoke-AuthorizeCommand {
    $r = Resolve-Repo $Repo
    $ref = ("$Reference" -replace '\s+', ' ').Trim()
    if ($ref.Length -lt 3 -or $ref.Length -gt 200) { throw '-Reference must name the authorization you hold (3 to 200 characters), e.g. a ticket, policy, or approver.' }
    if (Find-Secret $ref) { throw 'Refused: the reference looks like it contains a secret.' }
    if ($Classification -notin $Classifications) { throw "-Classification must be one of: $($Classifications -join ', ')." }
    $hostList = @("$Hosts" -split ';' | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ })
    foreach ($h in $hostList) { if ($h -notmatch '^[a-z0-9]([a-z0-9.-]{0,251}[a-z0-9])?$') { throw "Host '$h' must be a host name such as sonarqube.example.com." } }
    New-Item -ItemType Directory -Force -Path $AkzoHome | Out-Null
    Use-FileLock $AuthFile {   # another repository's concurrent authorization is kept
        $all = Read-Authorizations
        $entry = [pscustomobject][ordered]@{ reference = $ref; classification = $Classification; model = "$Model"; allowedHosts = $hostList; recordedBy = "$env:USERDOMAIN\$env:USERNAME"; recordedAt = (Get-Date).ToString('s'); kind = 'developer statement' }
        $all.repos | Add-Member -NotePropertyName $r.id -NotePropertyValue $entry -Force
        Write-TextAtomic $AuthFile ($all | ConvertTo-Json -Depth 5)
    }
    $a = Get-Authorization $r
    [pscustomobject][ordered]@{ status = $a.status; repo = $r.id; reference = $ref; classification = $Classification; reason = $a.reason
        note = 'Recorded as your statement with your user name. It lets the agent work on this repository; it is not corporate approval (G8 reports it as NOT VERIFIED).' } | ConvertTo-Json -Depth 3
    exit 0
}

# guard: classify a terminal command before the agent runs it; logged to the task's evidence when -Id is given.
function Invoke-GuardCommand {
    $cmdText = (@($Line) + @($Rest) | Where-Object { $_ }) -join ' '
    if (-not $cmdText) { throw 'guard needs -Line "<command line>" (use single quotes inside the command, not double quotes).' }
    $Line = $cmdText
    $g = Test-CommandLine $Line
    if ($Repo -and $g.decision -eq 'ALLOW' -and $Line -match '(?i)\bdotnet(\.exe)?\s+(build|test|restore|run|msbuild|pack|publish|clean)\b') {
        $gr = Resolve-Repo $Repo; $null = Assert-Preflight $gr
        $sol = Test-SolutionUse $gr $Line; if ($sol) { $g = $sol }
    }
    if ($g.decision -eq 'NEEDS_APPROVAL' -and $ApprovedBy) { $g.decision = 'APPROVED'; $g.reason += "; approved by $ApprovedBy" }
    if ($g.decision -eq 'BLOCK' -and $ApprovedBy -and $g.category -ne 'wrong-solution') { $g.reason += '; an approval cannot release a blocked command (it needs a policy change through the authorized process)' }
    if ($Id) {
        $td = Find-TaskDir $Id $Repo
        $log = Join-Path $td 'evidence\commands.tsv'
        New-Item -ItemType Directory -Force -Path (Split-Path $log) | Out-Null
        Add-LineLocked $log "$((Get-Date).ToString('s'))`t$($g.decision)`t$($g.category)`t$ApprovedBy`t$(Protect-Text ($Line -replace '[\t\r\n]+', ' '))`r`n"
    }
    [pscustomobject][ordered]@{ decision = $g.decision; category = $g.category; reason = (Protect-Text $g.reason) } | ConvertTo-Json
    exit 0
}

# scan: secrets and added suppressions on changed lines, and dependency changes (values are never shown).
function Invoke-ScanCommand {
    $r = Resolve-Repo $Repo
    $null = Assert-Preflight $r
    $f = Get-ChangeFindings $r.path
    [pscustomobject][ordered]@{ repo = $r.id; changedFiles = $f.files; changedLines = $f.lines; secrets = $f.secrets; suppressions = $f.suppressions; dependencyChanges = @(Get-DependencyChanges $r.path)
        note = 'Pattern scan of changed lines: it cannot find every secret; review findings marked review, and use an approved dedicated scanner where the organization provides one.' } | ConvertTo-Json -Depth 4
    exit 0
}

# purge: delete a repository's memory (index, symbols, facts, notes, graph); -IncludeTasks also deletes its task folders.
function Invoke-PurgeCommand {
    if (-not $Repo) { throw 'purge needs -Repo <id>.' }
    if (-not $Confirmed) { throw "purge deletes the memory of '$Repo' and cannot be undone: ask the developer, then rerun with -Confirmed." }
    if ($Repo -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$') { throw "Repository id '$Repo' is not a valid id." }
    $gone = @()
    foreach ($p in @((Join-Path $AkzoHome "maps\$Repo"), (Join-Path $AkzoHome "maps\$Repo.md"), (Join-Path $AkzoHome "graphs\$Repo")) + @(if ($IncludeTasks) { Join-Path $TasksDir $Repo })) {
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force; $gone += $p }
    }
    [pscustomobject]@{ status = 'PURGED'; repo = $Repo; removed = $gone } | ConvertTo-Json
    exit 0
}

# security: the G8 corporate security gate for one task. Deterministic evidence only; writes
# <task>\evidence\corporate-security-report.html (never into the repository). PASS only when every control has evidence.
function Invoke-SecurityCommand {
    if (-not $Id) { throw 'security needs -Id <PBI> (add -Repo when the PBI exists under several repositories).' }
    $td = Find-TaskDir $Id $Repo
    $r = Resolve-Repo (Split-Path (Split-Path $td) -Leaf)
    $auth = Get-Authorization $r
    $st = try { Get-Content -LiteralPath (Join-Path $td 'task.json') -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $null }
    $head = "$(Invoke-Quiet git -C $r.path rev-parse HEAD)"
    $mapsDir = Join-Path $AkzoHome "maps\$($r.id)"
    $controls = New-Object Collections.Generic.List[object]
    $add = { param($name, $status, $evidence) $controls.Add([pscustomobject][ordered]@{ control = $name; status = $status; evidence = (Protect-Text "$evidence") }) }
    $cmdLog = Join-Path $td 'evidence\commands.tsv'
    $cmds = @(if (Test-Path -LiteralPath $cmdLog) { Get-Content -LiteralPath $cmdLog -Encoding UTF8 | ForEach-Object { $c = $_.Split("`t"); [pscustomobject]@{ at = $c[0]; decision = $c[1]; category = $c[2]; approvedBy = $c[3]; command = $c[4] } } })
    $netLog = @(if (Test-Path -LiteralPath (Join-Path $mapsDir 'memory-log.tsv')) { Get-Content -LiteralPath (Join-Path $mapsDir 'memory-log.tsv') -Encoding UTF8 | Where-Object { $_ -match "`tnetwork`t" } | ForEach-Object { ($_ -split "`t")[2] } })
    $netHosts = @($netLog | ForEach-Object { ($_ -split ' ')[1] } | Where-Object { $_ } | Select-Object -Unique)

    # 1. Approved repository and model
    $who = if ($auth.status -eq 'ATTESTED') { "developer statement '$($auth.reference)' by $($auth.recordedBy) on $($auth.recordedAt)" } else { "policy $($auth.source) (reference '$($auth.policyReference)', repository '$($auth.reference)')" }
    if ($auth.status -notin 'AUTHORIZED', 'ATTESTED') { & $add 'Approved repository and model' 'FAIL' "processing is not authorized: $($auth.reason)" }
    elseif ($auth.status -eq 'ATTESTED') { & $add 'Approved repository and model' 'NOT VERIFIED' "$who; a developer statement is not corporate approval$(if ($auth.model) { "; model stated: $($auth.model)" })" }
    elseif (-not $auth.managed) { & $add 'Approved repository and model' 'NOT VERIFIED' "$who; the policy file is writable by the current user, so it cannot show administrator approval" }
    elseif (-not $auth.approvedModels.Count) { & $add 'Approved repository and model' 'NOT VERIFIED' "$who; the policy names no approved models" }
    elseif (-not $auth.model) { & $add 'Approved repository and model' 'NOT VERIFIED' "$who; the model in use was not confirmed (authorize -Model)" }
    else { & $add 'Approved repository and model' 'PASS' "$who; model '$($auth.model)' confirmed by the developer is in approvedModels" }

    # 2. Source-code handling
    $inRepo = Get-GitTop $td
    $factsFile = Join-Path $mapsDir 'facts.json'
    $hasFacts = (Test-Path -LiteralPath $factsFile) -and @((Get-Content -LiteralPath $factsFile -Raw | ConvertFrom-Json).facts).Count
    $flow = "PBI and documents in $td$(if ($inRepo) { ' (INSIDE a Git repository)' } else { ' (outside the repository)' }); memory in $mapsDir; classification: $($auth.classification); content reaches the model only through Copilot in the IDE"
    if ($inRepo -or ($auth.memory -eq 'disabled' -and $hasFacts)) { & $add 'Source-code handling' 'FAIL' "$flow$(if ($auth.memory -eq 'disabled' -and $hasFacts) { '; facts stored although the policy disables memory' })" }
    elseif ($auth.classification -eq 'unclassified') { & $add 'Source-code handling' 'NOT VERIFIED' "$flow; no data classification recorded, so the permitted boundaries are unknown" }
    else { & $add 'Source-code handling' 'PASS' $flow }

    # 3. DLP compliance (recorded commands and the helper's own network calls)
    $badHosts = @($netHosts | Where-Object { $auth.allowedHosts -notcontains $_ })
    $transfer = @($cmds | Where-Object { $_.category -in 'external-transfer', 'remote-code-execution', 'credential-access' })
    if ($transfer.Count -or $badHosts.Count) { & $add 'DLP compliance' 'FAIL' "$(if ($transfer.Count) { "$($transfer.Count) transfer/execution/credential command(s) requested: $(@($transfer | ForEach-Object { $_.command }) -join ' | ')" }) $(if ($badHosts.Count) { "helper called hosts outside the allowlist: $($badHosts -join ', ')" })" }
    elseif (-not $cmds.Count) { & $add 'DLP compliance' 'NOT VERIFIED' "no command log ($cmdLog): the agent recorded no guard checks; helper network calls: $(if ($netHosts.Count) { $netHosts -join ', ' } else { 'none' })" }
    else { & $add 'DLP compliance' 'PASS' "$($cmds.Count) command(s) checked by the guard, none transfers data; helper network calls only to allowed hosts: $(if ($netHosts.Count) { $netHosts -join ', ' } else { 'none' })" }

    # 4. Secret scanning and 13. suppressions (changed lines)
    $find = Get-ChangeFindings $r.path
    $high = @($find.secrets | Where-Object { $_.confidence -eq 'high' }); $review = @($find.secrets | Where-Object { $_.confidence -eq 'review' })
    $where = { param($list) @($list | ForEach-Object { "$($_.file):$($_.line) ($($_.kind))" }) -join ', ' }
    if ($high.Count) { & $add 'Secret scanning' 'FAIL' "built-in pattern scan of $($find.lines) changed line(s): $($high.Count) likely secret(s) at $(& $where $high)" }
    elseif ($review.Count) { & $add 'Secret scanning' 'NOT VERIFIED' "built-in pattern scan: $($review.Count) finding(s) to review at $(& $where $review)" }
    else { & $add 'Secret scanning' 'PASS' "built-in pattern scan of $($find.lines) changed line(s) in $($find.files) file(s): 0 findings (pattern scanning cannot prove that no secret exists)" }

    # 5. Dependency security
    $deps = @(Get-DependencyChanges $r.path)
    if (-not $deps.Count) { & $add 'Dependency security' 'NOT APPLICABLE' 'no dependency added or changed in any manifest against HEAD' }
    else { & $add 'Dependency security' 'NOT VERIFIED' "dependency changes need approval and an approved vulnerability and licence check: $($deps -join '; ')" }

    # 6. SonarQube (read-only; only to an allowed host)
    $s = Get-SonarSetup $r
    $sonar = ''
    if (-not $s.serverQueries) { & $add 'SonarQube' 'NOT VERIFIED' "not configured (project key '$($s.projectKey)', server '$($s.host)', token set: $($s.tokenSet))" }
    elseif ($auth.allowedHosts -notcontains (Get-HostName $s.host)) { & $add 'SonarQube' 'NOT VERIFIED' "server $(Get-HostName $s.host) is not an allowed host for this repository" }
    elseif (Get-HostIssue $s.host) { & $add 'SonarQube' 'NOT VERIFIED' "no request made: $(Get-HostIssue $s.host)" }
    else {
        try {
            $g = (Invoke-SonarApi $s.host "api/qualitygates/project_status?projectKey=$([Uri]::EscapeDataString($s.projectKey))").projectStatus
            $an = try { @((Invoke-SonarApi $s.host "api/project_analyses/search?project=$([Uri]::EscapeDataString($s.projectKey))&ps=1").analyses)[0] } catch { $null }
            Add-MemoryLog $r.id 'network' "GET $(Get-HostName $s.host) api/qualitygates/project_status (G8)"
            $dirty = @(Invoke-Quiet git -C $r.path status --porcelain).Count
            $sonar = "quality gate $($g.status); analysis $($an.key) at revision $($an.revision); failing: $(@($g.conditions | Where-Object { $_.status -eq 'ERROR' } | ForEach-Object { $_.metricKey }) -join ', ')"
            if ($g.status -eq 'ERROR') { & $add 'SonarQube' 'FAIL' $sonar }
            elseif ($an.revision -eq $head -and -not $dirty) { & $add 'SonarQube' 'PASS' $sonar }
            else { & $add 'SonarQube' 'NOT VERIFIED' "$sonar; the analysis does not contain this task's changes (HEAD $head, $dirty changed path(s))" }
        } catch { & $add 'SonarQube' 'NOT VERIFIED' "server query failed: $($_.Exception.Message)" }
    }

    # 7. Script safety
    $blocked = @($cmds | Where-Object { $_.decision -eq 'BLOCK' })
    if ($blocked.Count) { & $add 'Script safety' 'FAIL' "$($blocked.Count) prohibited command(s) were requested: $(@($blocked | ForEach-Object { "$($_.category): $($_.command)" }) -join ' | ')" }
    elseif (-not $cmds.Count) { & $add 'Script safety' 'NOT VERIFIED' 'no command log: commands were not checked by the guard' }
    else { & $add 'Script safety' 'PASS' "$(@($cmds | Group-Object decision | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ', '); approvals: $(@($cmds | Where-Object { $_.decision -eq 'APPROVED' } | ForEach-Object { "$($_.category) by $($_.approvedBy)" }) -join ', ')" }

    # 8. Repository isolation
    $foreign = @(if ($hasFacts) { (Get-Content -LiteralPath $factsFile -Raw | ConvertFrom-Json).facts | Where-Object { $_.repo -and $_.repo -ne $r.id } })
    if ($foreign.Count) { & $add 'Repository isolation' 'FAIL' "$($foreign.Count) fact(s) of another repository in $factsFile" }
    else { & $add 'Repository isolation' 'PASS' "memory for '$($r.id)' only in $mapsDir; facts carry this repository id; cross-repository isolation is covered by scripts\test.ps1 (memory isolation checks)" }

    # 9. Memory security
    $memSecrets = @(foreach ($f in @($factsFile, (Join-Path $mapsDir 'memory-log.tsv'), (Join-Path $AkzoHome "maps\$($r.id).md"))) { if ((Test-Path -LiteralPath $f) -and (Find-Secret ([IO.File]::ReadAllText($f)))) { $f } })
    $prot = @(@($mapsDir, (Join-Path $TasksDir $r.id)) | Where-Object { (Test-Path -LiteralPath $_) -and -not (Test-ProtectedDirectory $_) })
    $ret = if ($auth.retentionDays) { "retention $($auth.retentionDays) days (policy)" } else { 'no retention rule supplied by a policy' }
    if ($memSecrets.Count) { & $add 'Memory security' 'FAIL' "secret-looking values in: $($memSecrets -join ', ')" }
    elseif ($prot.Count) { & $add 'Memory security' 'NOT VERIFIED' "not restricted to the owner, SYSTEM, and Administrators: $($prot -join ', '); $ret" }
    else { & $add 'Memory security' 'PASS' "owner-only access on $mapsDir and the task folders; no secret-looking values in facts, log, or notes; facts hold statements and file references, no source bodies; $ret; purge: akzo.ps1 purge -Repo $($r.id) -Confirmed" }

    # 10. Installer integrity
    $ii = Test-InstalledIntegrity
    & $add 'Installer integrity' $ii.status $ii.detail

    # 11. Git operations
    if (-not $st.startHead) { & $add 'Git operations' 'NOT VERIFIED' 'task start HEAD not recorded (task created before 3.4.0); pushes cannot be detected locally' }
    elseif ($st.startHead -eq $head) { & $add 'Git operations' 'PASS' "HEAD unchanged since the task started ($head): no commit was made; changes stay uncommitted for review. Pushes cannot be detected locally; the agent never pushes (S18)." }
    else { $n = @(Invoke-Quiet git -C $r.path rev-list "$($st.startHead)..$head").Count; & $add 'Git operations' 'NOT VERIFIED' "HEAD moved from $($st.startHead) to $head ($n commit(s)); the agent does not commit, so confirm they were made by the developer" }

    # 12. Corporate policy approval
    if ($auth.status -eq 'AUTHORIZED' -and $auth.managed -and $auth.policyReference -and $auth.reference) { & $add 'Corporate policy approval' 'PASS' "administrator-managed policy $($auth.source) (reference '$($auth.policyReference)') authorizes '$($r.id)' (reference '$($auth.reference)'). Automated checks are not a substitute for this approval." }
    else { & $add 'Corporate policy approval' 'NOT VERIFIED' "no administrator-managed policy authorizes '$($r.id)' ($(if ($auth.status -eq 'ATTESTED') { 'developer statement only' } elseif ($auth.status -eq 'AUTHORIZED') { 'policy file is not administrator-managed, or lacks references' } else { $auth.reason })). Request approval through the authorized process." }

    # 13. Suppressions and skipped tests added by the change
    if ($find.suppressions.Count) { & $add 'Findings not suppressed' 'FAIL' "suppressions or skipped tests added: $(& $where $find.suppressions)" }
    else { & $add 'Findings not suppressed' 'PASS' "no suppression, analyzer exclusion, or skipped test added on $($find.lines) changed line(s)" }

    $all = $controls.ToArray()
    $outcome = if (@($all | Where-Object { $_.status -eq 'FAIL' }).Count) { 'FAIL' } elseif (@($all | Where-Object { $_.status -eq 'NOT VERIFIED' }).Count) { 'NOT VERIFIED' } else { 'PASS' }
    $report = Join-Path $td 'evidence\corporate-security-report.html'
    New-Item -ItemType Directory -Force -Path (Split-Path $report) | Out-Null
    $e = { param($v) [Net.WebUtility]::HtmlEncode((Protect-Text "$v")) }
    $cls = @{ 'PASS' = 'p'; 'FAIL' = 'f'; 'NOT VERIFIED' = 'n'; 'NOT APPLICABLE' = 'a' }
    $rows = ($all | ForEach-Object { "<tr><td>$(& $e $_.control)</td><td><span class=""s $($cls[$_.status])"">$(& $e $_.status)</span></td><td>$(& $e $_.evidence)</td></tr>" }) -join "`n"
    $cmdRows = if ($cmds.Count) { ($cmds | ForEach-Object { "<tr><td>$(& $e $_.at)</td><td>$(& $e $_.decision)</td><td>$(& $e $_.category)</td><td><code>$(& $e $_.command)</code></td></tr>" }) -join "`n" } else { '<tr><td colspan="4">No commands recorded by the guard.</td></tr>' }
    $list = { param($items) if (@($items).Count) { '<ul>' + ((@($items) | ForEach-Object { "<li>$(& $e $_)</li>" }) -join '') + '</ul>' } else { '<p>None.</p>' } }
    $nv = @($all | Where-Object { $_.status -eq 'NOT VERIFIED' }); $fails = @($all | Where-Object { $_.status -eq 'FAIL' })
    $remed = @(foreach ($c in $fails) { "$($c.control): fix the finding, then rerun the gate." }) + @(foreach ($c in $nv) {
            switch ($c.control) {
                'Approved repository and model' { 'Have an administrator list the repository and approved models in the machine policy, and confirm the model in use (authorize -Model).' }
                'Corporate policy approval' { 'Request authorization through the organization''s approval process; an administrator records it in the machine policy.' }
                'SonarQube' { 'Run the approved Sonar analysis for this change (with the developer''s approval), then rerun the gate.' }
                'Secret scanning' { 'Review each finding; run the organization''s approved secret scanner.' }
                'Dependency security' { 'Approve each dependency change and run the approved vulnerability and licence check.' }
                default { "$($c.control): provide the missing evidence, then rerun the gate." }
            } })
    $html = @"
<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Corporate security report</title>
<style>:root{--bg:#f6f7f9;--fg:#1c2430;--mut:#5a6473;--line:#d9dee6;--p:#1e7b46;--f:#b42318;--n:#9a5b00;--a:#5a6473}
@media(prefers-color-scheme:dark){:root{--bg:#12161c;--fg:#e5e9ef;--mut:#9aa4b2;--line:#2c3440;--p:#5cc28a;--f:#f07a6e;--n:#e0a84a;--a:#9aa4b2}}
body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.5 "Segoe UI",system-ui,sans-serif}main{max-width:1000px;margin:0 auto;padding:24px 16px}
h1{font-size:1.5rem;margin:0 0 4px}h2{font-size:1.1rem;margin:24px 0 8px}table{border-collapse:collapse;width:100%;font-size:.9rem}th,td{border-bottom:1px solid var(--line);padding:6px 8px;text-align:left;vertical-align:top}
.s{font-weight:700;white-space:nowrap}.p{color:var(--p)}.f{color:var(--f)}.n{color:var(--n)}.a{color:var(--a)}.mut{color:var(--mut)}code{font:.85em Consolas,monospace;word-break:break-all}.wrap{overflow-x:auto}</style></head><body><main>
<h1>Corporate security report (G8)</h1><p class="mut">Akzo SDD Agent — Developed and maintained by Arun RG</p>
<p><b>Outcome: <span class="s $($cls[$outcome])">$outcome</span></b>. Automated verification is not formal corporate approval. PASS means every control below had evidence; it does not certify compliance.</p>
<h2>1. Agent and repository</h2><p>Agent $(& $e $Version) · repository <code>$(& $e $r.id)</code> ($(& $e $r.path)) · work item <code>$(& $e $Id)</code> · HEAD <code>$(& $e $head)</code></p>
<h2>2. Date and environment</h2><p>$(& $e (Get-Date).ToString('yyyy-MM-dd HH:mm:ss zzz')) · $(& $e "$env:COMPUTERNAME / $env:USERDOMAIN\$env:USERNAME") · Windows PowerShell $(& $e $PSVersionTable.PSVersion) · $(& $e ((Invoke-Quiet git --version) -join ''))</p>
<h2>3. Policy sources and authorization</h2><p>Status <b>$(& $e $auth.status)</b> · source $(& $e $(if ($auth.source) { $auth.source } else { 'none' })) · administrator-managed: $(& $e $auth.managed) · policy reference $(& $e $auth.policyReference) · repository reference $(& $e $auth.reference) $(if ($auth.reason) { '· ' + (& $e $auth.reason) })</p>
<h2>4. Data classification and processing boundaries</h2><p>Classification <b>$(& $e $auth.classification)</b> · memory $(& $e $auth.memory) · retention $(& $e $(if ($auth.retentionDays) { "$($auth.retentionDays) days" } else { 'not set' })) · allowed hosts $(& $e $(if ($auth.allowedHosts.Count) { $auth.allowedHosts -join ', ' } else { 'none' })) · approved models $(& $e $(if ($auth.approvedModels.Count) { $auth.approvedModels -join ', ' } else { 'not set' })) · model stated $(& $e $(if ($auth.model) { $auth.model } else { 'not confirmed' }))</p>
<h2>5. Commands and external tools</h2><div class="wrap"><table><thead><tr><th>Time</th><th>Decision</th><th>Category</th><th>Command (redacted)</th></tr></thead><tbody>$cmdRows</tbody></table></div><p>Helper network calls: $(& $e $(if ($netLog.Count) { $netLog -join '; ' } else { 'none' }))</p>
<h2>6. Dependency changes</h2>$(& $list $deps)
<h2>7. Secret scanning</h2><p>Changed lines scanned: $($find.lines) in $($find.files) file(s). Values are never shown.</p>$(& $list @($find.secrets | ForEach-Object { "$($_.file):$($_.line) - $($_.kind) ($($_.confidence))" }))
<h2>8. Static analysis and SonarQube</h2><p>$(& $e $(if ($sonar) { $sonar } else { ($all | Where-Object { $_.control -eq 'SonarQube' }).evidence }))</p><p class="mut">Build, analyzer, and coverage results of this task are in the plan (sections 4 and 6): $(& $e $(if ($st.specDir) { Join-Path $st.specDir 'plan.md' } else { 'plan.md' })).</p>
<h2>9. Memory storage and isolation</h2><p>$(& $e (($all | Where-Object { $_.control -in 'Repository isolation', 'Memory security' } | ForEach-Object { "$($_.control): $($_.evidence)" }) -join ' · '))</p>
<h2>10. Detected violations and unresolved risks</h2>$(& $list @($fails | ForEach-Object { "$($_.control): $($_.evidence)" }))
<h2>11. Controls not verified</h2>$(& $list @($nv | ForEach-Object { "$($_.control): $($_.evidence)" }))
<h2>12. Remediation</h2>$(& $list $remed)
<h2>13. G8 controls and outcome</h2><div class="wrap"><table><thead><tr><th>Control</th><th>Status</th><th>Evidence</th></tr></thead><tbody>$rows</tbody></table></div>
<p><b>Final G8 outcome: <span class="s $($cls[$outcome])">$outcome</span></b></p></main></body></html>
"@
    [IO.File]::WriteAllText($report, $html, $Utf8NoBom)
    Add-MemoryLog $r.id 'g8' "$Id $outcome"
    [pscustomobject][ordered]@{
        gate = 'G8'; outcome = $outcome; status = $(if ($outcome -eq 'FAIL') { 'BLOCKED' } elseif ($outcome -eq 'NOT VERIFIED') { 'DONE_WITH_CONCERNS' } else { 'READY_FOR_HANDOVER' })
        report = $report; controls = $all; notVerified = @($nv | ForEach-Object { $_.control }); violations = @($fails | ForEach-Object { $_.control })
        note = 'Automated verification is not formal corporate approval.'
    } | ConvertTo-Json -Depth 4
    exit 0
}

# remember: store or re-verify one fact with its evidence (repo-relative files that exist now; their content is fingerprinted).
function Invoke-RememberCommand {
    $r = Resolve-Repo $Repo
    $auth = Assert-Preflight $r
    if ($auth.memory -eq 'disabled') { throw "Refused: the policy disables repository memory for '$($r.id)'." }
    if ($Type -notin $FactTypes) { throw "-Type must be one of: $($FactTypes -join ', ')." }
    $t = ("$Text" -replace '\s+', ' ').Trim()
    if ($t.Length -lt 10 -or $t.Length -gt 800) { throw '-Text must be one factual statement of 10 to 800 characters.' }
    $secret = Find-Secret "$t $Evidence"
    if ($secret) { throw "Refused: the fact looks like it contains a secret ($secret). Record where the value is configured, never the value." }
    foreach ($tid in @(Get-RepoTasks $r.id | ForEach-Object { $_.id })) {   # PBI-specific text belongs to the task, not to repository memory
        if ($tid.Length -ge 3 -and $t -match "(?<![A-Za-z0-9])$([regex]::Escape($tid))(?![A-Za-z0-9])") { throw "Refused: the fact names work item '$tid'. Repository memory holds architecture knowledge (structure, conventions, reusable components, commands); requirements, approvals, and progress of a PBI stay in its task." }
    }
    if ($t -match '(?i)\b(PBI|work item|WI|user story)\s*[-#:]?\s*\d{3,}') { throw 'Refused: the fact names a work item. Repository memory holds architecture knowledge, not PBI requirements, approvals, or progress.' }
    if (Find-InstructionText $t) { throw 'Refused: the fact reads like an instruction to the agent. Memory holds verified statements about the code, never instructions.' }
    $blobs = Get-FileBlobs $r.path
    $ev = @(foreach ($e in @("$Evidence" -split ';' | Where-Object { $_.Trim() })) {
            if ($e.Trim() -notmatch '^(?<p>[^:*?"<>|]+?)(?::(?<l>\d+))?$') { throw "Evidence '$e' must be <repo-relative path>[:line]." }
            $p = $Matches['p'].Trim() -replace '\\', '/'
            if ([IO.Path]::IsPathRooted($p) -or $p -match '(^|/)\.\.(/|$)') { throw "Evidence '$p' must be a path inside the repository." }
            if (-not $blobs.ContainsKey($p)) { throw "Evidence '$p' is not a file of the repository (tracked or untracked, not ignored)." }
            [pscustomobject][ordered]@{ path = $p; line = $(if ($Matches['l']) { [int]$Matches['l'] } else { $null }); blob = $blobs[$p] } })
    if (-not $ev.Count) { throw '-Evidence needs at least one "path:line": a fact without evidence is not stored.' }
    $file = Join-Path $AkzoHome "maps\$($r.id)\facts.json"
    New-Item -ItemType Directory -Force -Path (Split-Path $file) | Out-Null
    $commit = "$(Invoke-Quiet git -C $r.path rev-parse HEAD)"
    $saved = Use-FileLock $file {   # read, change and write facts.json as one step: a concurrent remember is never lost
        $load = Read-JsonOrRecover $file
        $facts = New-Object Collections.Generic.List[object]; foreach ($f in @($load.data.facts | Where-Object { $_ })) { $facts.Add($f) }
        $deps = @("$DependsOn" -split ';' | Where-Object { $_.Trim() } | ForEach-Object { $_.Trim() })
        foreach ($d in $deps) { if (-not ($facts | Where-Object { $_.id -eq $d })) { throw "Unknown fact '$d' in -DependsOn." } }
        $fid = if ($Id) { $Id } else { 'F-' + (Get-TextHash "$Type|$($t.ToLowerInvariant())").Substring(0, 8) }   # same statement -> same id (no duplicates)
        if ($fid -notmatch '^F-[0-9a-f]{8}$') { throw "Fact id '$fid' must look like F-1a2b3c4d." }
        $hit = $facts | Where-Object { $_.id -eq $fid } | Select-Object -First 1
        if ($Id -and -not $hit) { throw "Unknown fact '$Id'." }
        $now = (Get-Date).ToString('s')
        $fact = [pscustomobject][ordered]@{
            id = $fid; type = $Type; repo = $r.id; text = $t; evidence = $ev; dependsOn = $deps; status = 'verified'; reason = ''
            createdAt = $(if ($hit) { $hit.createdAt } else { $now }); verifiedAt = $now; verifiedCommit = $commit; source = "$Pbi"; checkedAt = $now
            invalidatedBy = 'a change to or removal of any evidence file, or an unverified fact in dependsOn'
        }
        if ($hit) { $facts.Remove($hit) | Out-Null }
        $facts.Add($fact)
        Write-TextAtomic $file ([pscustomobject]@{ schemaVersion = 1; repo = $r.id; facts = $facts.ToArray() } | ConvertTo-Json -Depth 5)   # 5.1: @(List) breaks ConvertTo-Json
        [pscustomobject]@{ id = $fid; updated = [bool]$hit; recovered = $load.recovered }
    }
    Add-MemoryLog $r.id $(if ($saved.updated) { 'reverify' } else { 'store' }) "$($saved.id) $Type"
    [pscustomobject][ordered]@{ status = $(if ($saved.updated) { 'UPDATED' } else { 'STORED' }); id = $saved.id; type = $Type; evidence = @($ev | ForEach-Object { "$($_.path):$($_.line)" }); recovered = $saved.recovered } | ConvertTo-Json -Depth 3
    exit 0
}

# forget: retire a fact that is no longer true (kept in facts-expired.json with the reason).
function Invoke-ForgetCommand {
    $r = Resolve-Repo $Repo
    $file = Join-Path $AkzoHome "maps\$($r.id)\facts.json"
    Use-FileLock $file {   # the same lock as remember and the fact sync
        $facts = @((Read-JsonOrRecover $file).data.facts | Where-Object { $_ })
        $hit = $facts | Where-Object { $_.id -eq $Id } | Select-Object -First 1
        if (-not $hit) { throw "Unknown fact '$Id'." }
        $hit | Add-Member -NotePropertyName expiredAt -NotePropertyValue (Get-Date).ToString('s') -Force
        $hit | Add-Member -NotePropertyName reason -NotePropertyValue $(if ($Text) { "forgotten: $Text" } else { 'forgotten' }) -Force
        $ef = Join-Path (Split-Path $file) 'facts-expired.json'
        $old = @((Read-JsonOrRecover $ef).data.facts | Where-Object { $_ })
        Write-TextAtomic $ef ([pscustomobject]@{ schemaVersion = 1; repo = $r.id; facts = @($old + $hit) } | ConvertTo-Json -Depth 5)
        Write-TextAtomic $file ([pscustomobject]@{ schemaVersion = 1; repo = $r.id; facts = @($facts | Where-Object { $_.id -ne $Id }) } | ConvertTo-Json -Depth 5)
    }
    Add-MemoryLog $r.id 'forget' "$Id $Text"
    [pscustomobject]@{ status = 'FORGOTTEN'; id = $Id } | ConvertTo-Json
    exit 0
}

# context: deterministic, budgeted retrieval for a requirement: verified facts, then ranked files with their symbols,
# tests, references, and siblings. Ranking: term matches in file name (3), folder (1), symbols (1.5 each, max 3 per term),
# scaled by term coverage; core component roles +1; references from other files +0.4 each (max 10); tests ranked lower
# and listed under their subject. Paths beyond the budget are still named in 'more', so nothing is hidden silently.
function Get-RepoContext([string]$ctxRepo = $Repo, [string]$ctxQuery = $Query, [string]$ctxMode = $Mode) {   # context, issue -Query, impact: ranked files, symbols, tests, and facts
    $r = Resolve-Repo $ctxRepo
    if (-not $ctxQuery) { throw 'context needs -Query "<requirement terms>".' }
    $auth = Assert-Preflight $r
    $sync = Sync-Architecture $r
    $facts = Sync-Facts $r $script:LastBlobs $auth.retentionDays
    $cfgR = if ($r.cfg.retrieval) { $r.cfg.retrieval } else { $Config.retrieval }
    $m = if ($ctxMode) { $ctxMode } elseif ($cfgR.mode -in 'compact', 'balanced', 'deep') { $cfgR.mode } else { 'balanced' }
    $budget = if ($cfgR.budgets.$m -as [int]) { [int]$cfgR.budgets.$m } else { @{ compact = 2500; balanced = 7000; deep = 20000 }[$m] }
    $perFile = @{ compact = 6; balanced = 12; deep = 40 }[$m]
    $refChecks = @{ compact = 6; balanced = 12; deep = 25 }[$m]
    $terms = @(Get-Tokens $ctxQuery)
    if (-not $terms.Count) { throw "No usable search terms in '$ctxQuery'." }
    $roles = @{}; foreach ($l in [IO.File]::ReadAllLines($sync.componentIndex)) { $c = $l.Split("`t"); if ($c.Count -eq 2) { $roles[$c[1]] = $c[0] } }
    $syms = @{}
    foreach ($l in [IO.File]::ReadAllLines($sync.symbols)) {
        $c = $l.Split("`t"); if ($c.Count -lt 5) { continue }
        if (-not $syms.ContainsKey($c[0])) { $syms[$c[0]] = New-Object Collections.Generic.List[object] }
        if ($c[2] -ne '0') { $syms[$c[0]].Add([pscustomobject]@{ line = [int]$c[2]; kind = $c[3]; name = $c[4]; lname = $c[4].ToLowerInvariant() }) }
    }
    $tokMemo = @{}
    $symHas = { param($sy, $t) if (-not $sy.lname.Contains($t)) { return $false }; if (-not $tokMemo.ContainsKey($sy.name)) { $tokMemo[$sy.name] = @(Get-Tokens $sy.name) }; $tokMemo[$sy.name] -contains $t }
    $subjectOf = { param($p) $leaf = $p.Substring($p.LastIndexOf('/') + 1).ToLowerInvariant(); $leaf = $leaf -replace '\.(spec|test)\.[a-z]+$', '' -replace '\.[a-z0-9]+$', ''; ($leaf -replace '^test_', '' -replace '_test$', '' -replace '(tests?|spec|it)$', '') }
    $testsBySubject = @{}
    foreach ($p in $roles.Keys) { if ($roles[$p] -eq 'test') { $k = & $subjectOf $p; if (-not $testsBySubject.ContainsKey($k)) { $testsBySubject[$k] = New-Object Collections.Generic.List[string] }; $testsBySubject[$k].Add($p) } }
    $core = 'endpoint', 'command', 'query', 'handler', 'validator', 'service', 'repository', 'model', 'mapping', 'ui', 'ui-service', 'graphql', 'contract', 'schema'
    $scored = New-Object Collections.Generic.List[object]
    $allPaths = @(@($syms.Keys) + @($roles.Keys) | Select-Object -Unique)
    # Exact symbol or file name first: one identifier that names a type, member, or file is answered without ranking.
    $exact = $null
    if ($ctxQuery.Trim() -match '^[A-Za-z_][\w.]*$' -and $ctxQuery.Trim() -cmatch '[a-z0-9][A-Z]|\.[A-Za-z]|_') {   # code-shaped (CreateOrderValidator, order.service.ts, get_order); a plain word is free text
        $q = $ctxQuery.Trim(); $qBase = $q -replace '\.[A-Za-z0-9]+$', ''
        $exact = @(foreach ($p in $allPaths) {
                $leaf = $p.Substring($p.LastIndexOf('/') + 1)
                $hit = ($leaf -ieq $q) -or (($leaf -replace '\.[A-Za-z0-9]+$', '') -ieq $qBase)
                if (-not $hit -and $syms.ContainsKey($p)) { foreach ($sy in $syms[$p]) { if ($sy.kind -ne 'import' -and $sy.name -ieq $q) { $hit = $true; break } } }
                if ($hit) { [pscustomobject]@{ path = $p; role = $roles[$p]; score = 100.0; matched = @($terms); refs = $null } }
            })
    }
    # A file none of whose path or symbol text contains a term (stem, minus a trailing y for 'ies' stems) cannot match: skip tokenizing it.
    $needles = @($terms | ForEach-Object { $_.TrimEnd('y') } | Where-Object { $_ })
    foreach ($p in $(if ($exact) { @() } else { $allPaths })) {
        $hay = $p.ToLowerInvariant(); if ($syms.ContainsKey($p)) { foreach ($sy in $syms[$p]) { $hay += "|" + $sy.lname } }
        $any = $false; foreach ($t in $needles) { if ($hay.Contains($t)) { $any = $true; break } }
        if (-not $any) { continue }
        $slash = $p.LastIndexOf('/')
        $fileTok = @(Get-Tokens $p.Substring($slash + 1)); $dirTok = if ($slash -gt 0) { @(Get-Tokens $p.Substring(0, $slash)) } else { @() }
        $s = 0.0; $matched = New-Object Collections.Generic.List[string]
        $fs = if ($syms.ContainsKey($p)) { $syms[$p] } else { @() }
        foreach ($t in $terms) {
            $hit = $false
            if ($fileTok -contains $t) { $s += 3; $hit = $true } elseif ($dirTok -contains $t) { $s += 1; $hit = $true }
            $n = 0; foreach ($sy in $fs) { if ($sy.kind -ne 'import' -and (& $symHas $sy $t)) { $n++; if ($n -ge 3) { break } } }
            if ($n) { $s += 1.5 * $n; $hit = $true }
            if ($hit) { $matched.Add($t) }
        }
        if (-not $matched.Count) { continue }
        $s *= 1 + $matched.Count / $terms.Count
        $role = $roles[$p]
        if ($role -in $core) { $s += 1 }
        if ($role -eq 'test') { $s *= 0.6 }
        $scored.Add([pscustomobject]@{ path = $p; role = $role; score = $s; matched = @($matched); refs = $null })
    }
    if ($exact) { foreach ($c in $exact) { $scored.Add($c) } }
    # References: how many other files name the file's main type (one git grep for all top candidates).
    $top = @($scored | Sort-Object @{ e = { $_.score }; Descending = $true }, path | Select-Object -First $refChecks)
    $mainOf = @{}
    foreach ($c in $top) {
        if ($c.role -eq 'test') { continue }
        $main = @($syms[$c.path] | Where-Object { $_.kind -eq 'type' } | Select-Object -First 1).name
        if (-not $main) { $leaf = $c.path.Substring($c.path.LastIndexOf('/') + 1); $main = $leaf.Split('.')[0] }
        if ($main.Length -ge 4) { $mainOf[$c.path] = $main }
    }
    $usedIn = @{}   # name -> files that contain it as a word
    if ($mainOf.Count) {
        $gargs = @('-C', $r.path, '-c', 'core.quotepath=off', 'grep', '-o', '-w', '-F'); foreach ($name in @($mainOf.Values | Select-Object -Unique)) { $gargs += '-e', $name }
        foreach ($l in @(Invoke-Quiet git @gargs -- .)) { $i = $l.LastIndexOf(':'); if ($i -gt 0) { $k = $l.Substring($i + 1); if (-not $usedIn.ContainsKey($k)) { $usedIn[$k] = New-Object 'Collections.Generic.HashSet[string]' }; [void]$usedIn[$k].Add($l.Substring(0, $i)) } }
    }
    foreach ($c in $top) {
        if (-not $mainOf.ContainsKey($c.path)) { continue }
        $files = if ($usedIn.ContainsKey($mainOf[$c.path])) { @($usedIn[$mainOf[$c.path]] | Where-Object { $_ -ne $c.path }) } else { @() }
        $c.refs = $files.Count; $c.score += [math]::Min($files.Count, 10) * 0.4
        if ($exact) { $c | Add-Member -NotePropertyName callers -NotePropertyValue @($files | Sort-Object | Select-Object -First 10) }
    }
    $ranked = @($scored | Sort-Object @{ e = { $_.score }; Descending = $true }, path)
    $out = [ordered]@{ repo = $r.id; mode = $m; budgetChars = $budget; terms = $terms; exact = [bool]$exact; memory = $sync.memory; facts = @(); files = @(); more = @(); usedChars = 0
        note = 'Ranked by deterministic matching, not proof: read the cited lines before classifying a requirement; use -Mode deep or targeted search when nothing fits.' }
    $used = 0
    foreach ($f in @($facts.all | Where-Object { $_.status -ne 'invalid' })) {   # facts first: they carry verified knowledge
        $ft = @(Get-Tokens $f.text); $paths = @($f.evidence | ForEach-Object { $_.path })
        $hitT = @($terms | Where-Object { $ft -contains $_ }).Count
        if ($hitT -lt [math]::Min(2, $terms.Count) -and -not @($ranked | Select-Object -First 5 | Where-Object { $paths -contains $_.path }).Count) { continue }
        $row = [pscustomobject][ordered]@{ id = $f.id; type = $f.type; status = $f.status; text = $f.text; evidence = (@($f.evidence | ForEach-Object { "$($_.path):$($_.line)" }) -join ', ') }
        $len = ($row | ConvertTo-Json -Compress).Length
        if ($used + $len -gt $budget * 0.4) { break }   # facts take at most 40% so files are always shown
        $out.facts += $row; $used += $len
    }
    $i = 0
    foreach ($c in $ranked) {
        $i++
        if ($c.role -eq 'test' -and @($ranked | Select-Object -First 10 | Where-Object { (& $subjectOf $_.path) -eq (& $subjectOf $c.path) -and $_.role -ne 'test' }).Count) { continue }   # shown under its subject
        $fs = if ($syms.ContainsKey($c.path)) { @($syms[$c.path] | Where-Object { $_.kind -ne 'import' }) } else { @() }
        $seen = @{}; $pick = New-Object Collections.Generic.List[object]   # matching symbols first, then types and routes, then the rest
        foreach ($sy in @(@($fs | Where-Object { $sy2 = $_; @($terms | Where-Object { & $symHas $sy2 $_ }).Count }) + @($fs | Where-Object { $_.kind -in 'type', 'route' }) + $fs)) {
            $k = "$($sy.line)|$($sy.name)"
            if (-not $seen.ContainsKey($k)) { $seen[$k] = 1; $pick.Add($sy); if ($pick.Count -ge $perFile) { break } }
        }
        $dir = if ($c.path.LastIndexOf('/') -gt 0) { $c.path.Substring(0, $c.path.LastIndexOf('/')) } else { '' }
        $sib = @(if ($i -le 3) { $roles.Keys | Where-Object { $_ -ne $c.path -and $_.StartsWith("$dir/") -and $_.Substring($dir.Length + 1) -notmatch '/' } | Sort-Object | Select-Object -First 6 })
        $row = [pscustomobject][ordered]@{
            path = $c.path; role = $c.role; score = [math]::Round($c.score, 1); matched = ($c.matched -join ',')
            symbols = @($pick | Sort-Object line | ForEach-Object { "L$($_.line) $($_.kind) $($_.name)" })
            tests = @($testsBySubject[(& $subjectOf $c.path)] | Where-Object { $_ -and $_ -ne $c.path })
            refs = $c.refs
            siblings = $sib
        }
        if ($c.PSObject.Properties['callers']) { $row | Add-Member -NotePropertyName callers -NotePropertyValue $c.callers }
        $len = ($row | ConvertTo-Json -Compress).Length
        if ($used + $len -gt $budget -and $out.files.Count) { $out.more += $c.path; if ($out.more.Count -ge 20) { break }; continue }
        $out.files += $row; $used += $len
    }
    $out.usedChars = $used
    Add-MemoryLog $r.id 'context' "$m '$($terms -join ' ')' files $($out.files.Count) facts $($out.facts.Count)"
    [pscustomobject]$out
}
function Invoke-ContextCommand { Get-RepoContext | ConvertTo-Json -Depth 4 -Compress; exit 0 }

# issue: the start of Fix Issue and Refactor in one call (one process instead of branchinfo, profile, and context):
# the branch and uncommitted changes, the profile files for the work, the located code (-Query), and how Sonar can be
# checked here. Read-only, like the commands it replaces.
function Invoke-IssueCommand {
    $r = Resolve-Repo $Repo; $null = Assert-Preflight $r
    $work = if ($Task -eq 'refactor') { 'refactor' } else { 'fix' }
    $o = [ordered]@{ status = 'READY'; mode = $work; repo = $r.id; path = $r.path
        git = Get-BranchInfo $r '' '' -Brief
        profile = Get-RepoProfile $r $Key "$(if ($Text) { $Text } else { $Query })" $work
        located = $(if ($Query) { Get-RepoContext } else { $null }) }
    $s = Get-SonarSetup $r -Brief -Binding
    $o.sonar = [pscustomobject][ordered]@{ projectKey = $s.projectKey; serverQueries = $s.serverQueries; analyzers = $s.analyzers; ideExtension = @(Get-SonarIdeExtension -CachedOnly); connectedMode = $s.connectedMode }
    $o.conventions = Get-ArchitectureConventions $r.path @($(if ($script:LastBlobs -and $script:LastBlobs.Count) { $script:LastBlobs.Keys } else { Invoke-Quiet git -C $r.path -c core.quotepath=off ls-files -co --exclude-standard }))
    $o.next = if (-not $Query) { 'Locate the code: the path in the issue, or run issue again with -Query "<ExactName>".' }
        elseif (-not $o.located.exact) { "No file or symbol is named exactly '$Query': 'located' holds ranked candidates only. Report it as not found with the nearest candidates unless one of them is the code in the issue; never guess a path." }
        else { "Read every 'profile.load' file and the located symbol ranges, then the closest existing implementation; the fix follows it." }
    [pscustomobject]$o | ConvertTo-Json -Depth 6 -Compress
    exit 0
}

# impact: one business operation across the registered repositories (API, UI, legacy platform). For each authorized
# repository its best-matching components (the context ranking, compact); then the names those components expose
# (function names and route segments, GraphQL operations, Dataverse logical names, plugin classes) are searched exactly in
# the other repositories, and plugin classes in registration files. Read-only evidence for the agent to read and classify;
# a repository without a link is not shown to be unaffected.
# shortcut: links are exact-name matches, not a call graph; a snake_case literal outside Dataverse can link by accident, so every link is read before it counts.
function Invoke-ImpactCommand {
    if (-not $Query) { throw 'impact needs -Query "<business operation or exact names>".' }
    $ids = @(@("$Repo" -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) | Select-Object -Unique)
    if (-not $ids.Count) { $ids = @(Get-Registry | ForEach-Object { $_.id }) }
    if (-not $ids.Count) { throw "impact needs registered repositories ($Registry) or -Repo ""<id>;<id>""." }
    $expose = [ordered]@{ function = '\[Function\(\s*"(?<v>[A-Za-z_]\w{3,})"'; route = '(?:\[(?:Route|Http(?:Get|Post|Put|Delete|Patch))\(\s*|\bRoute\s*=\s*)"(?<v>[^"]+)"'
        graphql = '^\s*(?:query|mutation|subscription)\s+(?<v>[A-Za-z_]\w{3,})'; logicalName = '["''](?<v>[a-z][a-z0-9]{1,7}_[a-z][a-z0-9_]{2,})["'']'
        plugin = '\bclass\s+(?<v>\w+)\s*:[^{]*\bIPlugin\b|\bclass\s+(?<v>\w+Plugin)\b'; interface = '\binterface\s+(?<v>I[A-Z]\w{3,})' }
    # A link is CONFIRMED when the matching line shows the structural use of its kind, otherwise a CANDIDATE (a name match only).
    $usage = @{ route = '(?i)\bhttp|fetch\(|/api/|[`''"][^`''"]*/'; function = '(?i)\bhttp|/api/|fetch\('; graphql = '(?i)\b(gql|graphql|query|mutation)\b'
        logicalName = '(?i)Xrm\.|getAttribute|getControl|LogicalName|\bEntity(Reference)?\b|ColumnSet|Attributes\[|WebApi|SdkMessage|PluginTypeName|PrimaryEntity|\.Retrieve|IOrganizationService'
        interface = '(:|,|\(|<)\s*I[A-Z]\w+|\bI[A-Z]\w+\s+_?[a-z]\w*\s*[;,)=]' }
    # snake_case words common outside Dataverse never become logical-name links
    $commonPrefix = '^(created|updated|modified|deleted|user|first|last|is|has|can|max|min|get|set|api|app|my|the|on|at|by|to|of|no|en|de|fr|es|utf|iso|http|https|data|file|page|item|sort|start|end|date|time|type|status|error|test|tmp|temp|default|primary|foreign)_'
    $kindOf = { param($p) if ($p -match '(?i)(^|/)SdkMessageProcessingSteps/|\.crmregister$|(^|/)spkl\.json$') { 'plugin registration' } elseif ($p -match '(?i)(^|/)Workflows?/') { 'workflow' } elseif ($p -match '(?i)(^|/)WebResources?/') { 'web resource' } else { '' } }
    $rows = New-Object Collections.Generic.List[object]; $done = New-Object Collections.Generic.List[object]; $keys = [ordered]@{}   # name -> kind and where it is exposed
    foreach ($id in $ids) {
        $one = try { Resolve-Repo $id } catch { $rows.Add([pscustomobject][ordered]@{ repo = $id; status = 'NOT_FOUND'; detail = $_.Exception.Message }); continue }
        $refusal = Get-PreflightRefusal (Get-Authorization $one)
        if ($refusal) { $rows.Add([pscustomobject][ordered]@{ repo = $one.id; status = $refusal; detail = "not read: authorize -Repo $($one.id) first" }); continue }
        $top = @((Get-RepoContext $one.id $Query 'compact').files | Select-Object -First 5)
        $exposed = New-Object Collections.Generic.List[string]; $plugins = @{}
        foreach ($f in $top) {
            $n = 0
            foreach ($line in @(try { [IO.File]::ReadAllLines((Join-Path $one.path $f.path)) } catch { })) {
                $n++
                foreach ($k in $expose.Keys) {
                    foreach ($m in [regex]::Matches($line, $expose[$k])) {
                        $vals = if ($k -eq 'route') { @($m.Groups['v'].Value -split '/' | Where-Object { $_.Length -ge 4 -and $_ -notmatch '[{}:$]' -and $_ -ne 'api' }) } else { @($m.Groups['v'].Value) }
                        foreach ($v in @($vals | Where-Object { -not ($k -eq 'logicalName' -and $_ -match $commonPrefix) })) {
                            if (-not $keys.Contains($v)) { $keys[$v] = [pscustomobject]@{ kind = $k; from = New-Object Collections.Generic.List[string]; line = $line } }
                            if ($keys[$v].from.Count -lt 3) { $keys[$v].from.Add("$($one.id):$($f.path):$n") }
                            if (-not $exposed.Contains("$k $v")) { $exposed.Add("$k $v") }
                            if ($k -eq 'plugin') { $plugins[$f.path] = 1 }
                        }
                    }
                }
            }
        }
        $done.Add($one)
        $rows.Add([pscustomobject][ordered]@{ repo = $one.id; status = $(if ($top.Count) { 'MATCHED' } else { 'NO_MATCH' })
            components = @($top | ForEach-Object { $kinds = (@($_.role, (& $kindOf $_.path), $(if ($plugins[$_.path]) { 'plugin' })) | Where-Object { $_ }) -join ', '
                "$($_.path)$(if ($kinds) { " ($kinds)" })$(if ($_.matched) { " matched $($_.matched)" })" })
            exposes = @($exposed | Select-Object -First 12) })
    }
    $links = New-Object Collections.Generic.List[string]; $regs = New-Object Collections.Generic.List[string]
    if ($keys.Count) {
        foreach ($one in $done) {   # one exact search per repository for every exposed name; whole lines, to classify each link
            $gargs = @('-C', $one.path, '-c', 'core.quotepath=off', 'grep', '-n', '-I', '-w', '-F'); foreach ($k in $keys.Keys) { $gargs += '-e', $k }
            $seen = @{}
            foreach ($l in @(Invoke-Quiet git @gargs -- .)) {
                if ($l -notmatch '^(.+?):(\d+):(.*)$') { continue }
                $p = $Matches[1]; $ln = $Matches[2]; $content = $Matches[3]
                foreach ($k in @($keys.Keys | Where-Object { $content.Contains($_) })) {
                    $src = @($keys[$k].from | Where-Object { $_ -notlike "$($one.id):*" })[0]   # a link leads from another repository
                    if (-not $src -or $seen["$k"] -ge 5) { continue }
                    $seen["$k"] = 1 + $seen["$k"]; $lk = & $kindOf $p; $kind = $keys[$k].kind
                    $status = if ($lk -or ($kind -eq 'graphql' -and $p -match '(?i)\.(graphql|gql)$') -or ($usage[$kind] -and $content -match $usage[$kind])) { 'CONFIRMED' } else { 'CANDIDATE' }
                    $links.Add("$status $k ($kind): $src -> $($one.id):${p}:$ln$(if ($lk) { " ($lk)" })")
                }
            }
        }
        foreach ($pk in @($keys.Keys | Where-Object { $keys[$_].kind -eq 'plugin' })) {   # a step registration only from a registration file
            $hits = @(foreach ($one in $done) { foreach ($l in @(Invoke-Quiet git -C $one.path -c core.quotepath=off grep -n -I -w -F -e $pk -- . ':!*.cs' | Select-Object -First 3)) { if ($l -match '^(.+?):(\d+):') { "$($one.id):$($Matches[1]):$($Matches[2])" } } })
            $regs.Add($(if ($hits.Count) { "${pk}: registered in $($hits -join ', ')" } else { "${pk}: NOT VERIFIED - no registration file (solution export, spkl.json, .crmregister) in these repositories names it; read its steps with approved tooling, never from the class name" }))
        }
    }
    [pscustomobject][ordered]@{ status = $(if (@($rows | Where-Object { $_.status -eq 'MATCHED' }).Count) { 'MAPPED' } else { 'NO_EVIDENCE' }); query = $Query
        repositories = $rows.ToArray(); links = @($links | Sort-Object { $_ -notlike 'CONFIRMED *' } | Select-Object -First 40); pluginRegistrations = $regs.ToArray()
        linkCounts = [pscustomobject][ordered]@{ confirmed = @($links | Where-Object { $_ -like 'CONFIRMED *' }).Count; candidate = @($links | Where-Object { $_ -like 'CANDIDATE *' }).Count; notVerified = @($regs | Where-Object { $_ -match 'NOT VERIFIED' }).Count + @($rows | Where-Object { $_.status -in 'NEEDS_AUTHORIZATION', 'BLOCKED_BY_POLICY', 'NOT_FOUND' }).Count }
        next = 'CONFIRMED links show the structural use on the matching line; CANDIDATE links are name matches to read before relying on them. Read the linked lines and classify each repository: affected (name the files) or not shown affected. A repository without a link is not proven unaffected: search the business words there before ruling it out. A plugin step counts as registered only when a registration file or approved tooling shows it. Plan one scope per affected repository and one requirement-to-repository table.' } | ConvertTo-Json -Depth 4 -Compress
    exit 0
}

# arch: the repository's architecture from the Roslyn analyzer the package ships (modules\analyzers\architecture, run
# with dotnet): projects with their declared and resolved target frameworks and references; types and methods with
# path:line, calls, DI registrations, and tests; the patterns and conventions the source shows. Cached per repository
# under maps\<repo>\roslyn and refreshed incrementally (document and project-file hashes); a project MSBuild cannot load is
# parsed only, and the coverage says so. -Query "<words>": the existing implementations, reusable components, impact,
# conventions, confidence, and unresolved words. -Update: rescan everything. Without the analyzer or a .NET runtime 8 or
# later it is UNAVAILABLE, with the source-level index (context) as the evidence.
function Get-ArchCache([string]$repoId) {
    $resolved = @($ResolvedRepos.Values | Where-Object { $_.id -eq $repoId }) | Select-Object -First 1
    $identity = if ($resolved) { "$($resolved.path)|$($resolved.workspace)" } else { $repoId }
    Join-Path $AkzoHome "maps\$repoId\roslyn\v2-$((Get-TextHash $identity.ToLowerInvariant()).Substring(0, 16))"
}
function Invoke-ArchAnalyzer([string[]]$arguments) {   # the analyzer's answer, or the reason it could not run (a string)
    $dll = Join-Path $ModulesDir 'analyzers\architecture\Akzo.ArchitectureAnalyzer.dll'
    $exe = Join-Path $ModulesDir 'analyzers\architecture\net472\Akzo.ArchitectureAnalyzer.exe'
    $framework = @(Get-VisualStudioInstance | Where-Object { [version]$_.version -ge [version]'18.0' -and (Test-Path -LiteralPath (Join-Path $_.path 'MSBuild\Current\Bin\MSBuild.exe')) })
    if ((Test-Path -LiteralPath $exe) -and $framework.Count) {
        $text = (Invoke-Quiet $exe @arguments) -join "`n"
    } else {
        if (-not (Test-Path -LiteralPath $dll)) { return "the analyzer is not installed ($dll): install a release package (Install / Upgrade)" }
        $dotnet = Get-Command dotnet -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $dotnet) { return 'dotnet is not on PATH: the analyzer needs the .NET runtime 8 or later (and the .NET SDK for semantic analysis)' }
        $text = (Invoke-Quiet $dotnet.Source $dll @arguments) -join "`n"
    }
    $res = try { $text | ConvertFrom-Json } catch { $null }
    if (-not $res) { return "the analyzer did not answer: $(if ($text) { $text.Substring(0, [math]::Min(300, $text.Length)) } else { 'no output (dotnet --list-runtimes shows whether a .NET runtime 8 or later is installed)' })" }
    if ($res.status -eq 'ERROR') { return "the analyzer failed: $($res.error)" }
    $res
}
# graphql: mechanical GraphQL validation (schema, operations, fragments, variables, nullability, generated-client names),
# cached per scope by content. -Query limits the returned schema context to the types and operations it names.
function Get-GraphQLValidation($r, [string]$terms) {   # the analyzer's answer, or the reason it could not run (a string)
    $arguments = @('graphql', '--root', $r.path, '--out', (Join-Path (Get-ArchCache $r.id) 'graphql'))
    if ($terms) { $arguments += @('--terms', ($terms -replace '"', ' ')) }
    Invoke-ArchAnalyzer $arguments
}
function Invoke-GraphqlCommand {
    $r = Resolve-Repo $Repo; $null = Assert-Preflight $r
    $res = Get-GraphQLValidation $r $Query
    if ($res -is [string]) {
        [pscustomobject][ordered]@{ status = 'UNAVAILABLE'; repo = $r.id; reason = $res
            next = 'GraphQL was not validated mechanically: do not mark the GraphQL schema readiness row VERIFIED; say the validator did not run.' } | ConvertTo-Json -Compress
        exit 0
    }
    $res | Add-Member -NotePropertyName repo -NotePropertyValue $r.id -Force
    $res | ConvertTo-Json -Depth 8 -Compress
    exit 0
}
function Invoke-ArchCommand {
    $batch = @()
    if ($script:PSBoundParameters.ContainsKey('Queries') -or $Queries) {
        if ($Query) { throw 'Use -Query or -Queries, not both.' }
        $batch = @($Queries -split ';' | ForEach-Object { $_.Trim() })
        if ($batch.Count -gt 8 -or @($batch | Where-Object { -not $_ }).Count) { throw '-Queries requires one to eight nonempty queries separated by semicolons.' }
    }
    $r = Resolve-Repo $Repo; $null = Assert-Preflight $r
    $language = Get-WorkspaceArchitecture $r -RoutingOnly
    if ($language.typescriptWorkspaces.Count -and -not $language.projects.Count) {
        if ($batch.Count) { throw '-Queries is supported by the Roslyn analyzer only; use -Query for the selected TypeScript workspace.' }
        if ($language.typescriptWorkspaces.Count -ne 1) { throw 'Multiple TypeScript workspaces found. Register/select the specific workspace through setup; nothing was changed.' }
        $cache = Join-Path (Get-ArchCache $r.id) 'typescript'
        $analyzer = Join-Path $ModulesDir 'analyzers\typescript\analyze.cjs'
        if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
            [pscustomobject]@{ status = 'UNAVAILABLE'; repo = $r.id; reason = 'Node.js is required for TypeScript semantic analysis.' } | ConvertTo-Json -Compress
            return
        }
        if ($Update -and (Test-Path -LiteralPath "$cache\index.json")) { Remove-Item -LiteralPath "$cache\index.json" -Force }
        $arguments = @($(if ($Query) { 'query' } else { 'scan' }), '--root', $language.typescriptWorkspaces[0], '--out', $cache)
        if ($Query) { $arguments += @('--terms', ($Query -replace '"', ' ')) }
        $raw = & node $analyzer @arguments
        $exit = $LASTEXITCODE
        $result = ($raw -join "`n") | ConvertFrom-Json
        $result | Add-Member -NotePropertyName repo -NotePropertyValue $r.id -Force
        $result | ConvertTo-Json -Depth 12 -Compress
        if ($exit -ne 0) { exit $exit }
        return
    }
    $cache = Get-ArchCache $r.id
    if ($Update -and (Test-Path -LiteralPath "$cache\index.json")) { Remove-Item -LiteralPath "$cache\index.json" -Force }
    $res = Invoke-ArchAnalyzer $(if ($batch.Count) { @('queries', '--root', $r.path, '--out', $cache, '--terms', (($batch -join ';') -replace '"', ' ')) } elseif ($Query) { @('query', '--root', $r.path, '--out', $cache, '--terms', ($Query -replace '"', ' ')) } else { @('scan', '--root', $r.path, '--out', $cache) })
    if ($res -is [string]) {
        [pscustomobject][ordered]@{ status = 'UNAVAILABLE'; repo = $r.id; reason = $res; fallback = $(if ($Query) { Get-RepoContext $Repo $Query 'compact' } else { $null })   # -Repo as given: a path-resolved repository has no registry id
            next = 'The Roslyn analysis did not run: use the source-level index (context, the located files) as the evidence, say that semantic analysis was not available, and never claim the callers, DI registrations, or tests it would have resolved.' } | ConvertTo-Json -Depth 6 -Compress
        exit 0
    }
    $res | Add-Member -NotePropertyName repo -NotePropertyValue $r.id -Force
    $res | ConvertTo-Json -Depth 12 -Compress
    exit 0
}
function Get-RuleHelp([string]$rule) {   # the rule's public documentation page (a link only; nothing is fetched)
    if ($rule -match '^(?:(csharpsquid|vbnet):)?S(\d+)$') { return "https://rules.sonarsource.com/$(if ($Matches[1] -eq 'vbnet') { 'vbnet' } else { 'csharp' })/RSPEC-$($Matches[2])/" }
    if ($rule -match '^CA(\d{4})$') { return "https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca$($Matches[1])" }
    if ($rule -match '^IDE(\d{4})$') { return "https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide$($Matches[1])" }
    ''
}

# sonar -Check issues (get_sonar_issues): the findings in scope from each source asked for (-Source, default all three):
# the IDE's Error List (live, unsaved edits included, no rule ids; -Update opens and saves the files first), the analyzers of
# the last logged build (rule ids; a file counts only when compiled after its last change, as in review), and the server's
# last analysis (rule ids; not local changes). A finding several sources report is one row: same file, line, and text, or
# the only row without a rule at that line and column; a rule id from the build or the server goes to the IDE row it
# matches. Each source reports its own status; none is assumed. With -Key or -Text each file gets a validation.
function Get-SonarIssues($r, $s, $out, $refusal) {
    $root = [IO.Path]::GetFullPath($r.path).TrimEnd('\')   # the IDE reports full Windows paths
    $want = if ($Source) { @("$Source" -split ';' | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ }) } else { @('ide', 'build', 'server') }
    $bad = @($want | Where-Object { $_ -notin 'ide', 'build', 'server' }); if ($bad.Count) { throw "sonar -Check issues: -Source takes ide, build, or server, joined with ';' (not '$($bad -join ';')')." }
    $paths = @(foreach ($f in @("$File" -split ';' | ForEach-Object { $_.Trim().Trim('"') } | Where-Object { $_ })) {
            $full = [IO.Path]::GetFullPath($(if ([IO.Path]::IsPathRooted($f)) { $f } else { Join-Path $root $f }))
            if (-not $full.StartsWith("$root\", [StringComparison]::OrdinalIgnoreCase)) { throw "File '$f' is not inside the repository ($root)." }
            $full.Substring($root.Length + 1).Replace('\', '/') })
    $inScope = if ($paths.Count) { 'files' } elseif ($Scope) { $Scope } else { 'changed' }
    if ($inScope -eq 'changed') { $paths = @((Get-ChangedLines $root).Keys | Where-Object { Test-Path -LiteralPath (Join-Path $root $_) -PathType Leaf } | Sort-Object) }
    $issues = New-Object Collections.Generic.List[object]; $src = [ordered]@{}; $fs = @{}
    $norm = { param($t) ("$t" -replace '\s+', ' ').Trim() }
    $tail = { param($k) ("$k" -split ':')[-1] }   # csharpsquid:S4055 and S4055 name one rule
    $state = { param($p) if (-not $fs.ContainsKey($p)) { $fs[$p] = [ordered]@{} }; $fs[$p] }
    $add = { param($row)
        $same = @($issues | Where-Object { $_.file -eq $row.file -and $_.line -eq $row.line -and ($_.source -split '\+') -notcontains $row.source })
        $hit = @($same | Where-Object { (& $norm $_.message) -eq (& $norm $row.message) })[0]
        if (-not $hit -and $row.column) { $one = @($same | Where-Object { $_.column -eq $row.column -and -not $_.rule }); if ($one.Count -eq 1) { $hit = $one[0] } }
        if (-not $hit -and $row.source -eq 'server') { $one = @($issues | Where-Object { $_.file -eq $row.file -and ($_.source -split '\+') -notcontains 'server' -and (& $norm $_.message) -eq (& $norm $row.message) }); if ($one.Count -eq 1) { $hit = $one[0] } }   # its line moved with local edits
        if ($hit) { if (-not $hit.rule) { $hit.rule = $row.rule }; $hit.source = "$($hit.source)+$($row.source)" } else { $issues.Add($row) }
    }
    if ('ide' -in $want) {
        $ide = try { Get-IdeDiagnostics $r.id $root @($paths | ForEach-Object { Join-Path $root ($_ -replace '/', '\') }) -Open:$Update -Active:($inScope -eq 'active') }
        catch { [pscustomobject]@{ status = 'UNAVAILABLE'; detail = "the IDE's automation interface failed: $($_.Exception.Message)"; active = ''; files = @{}; rows = @() } }
        if ($inScope -eq 'active') { $paths = @(if ($ide.active.StartsWith("$root\", [StringComparison]::OrdinalIgnoreCase)) { $ide.active.Substring($root.Length + 1).Replace('\', '/') }) }
        foreach ($f in @($ide.files.Keys)) { $st = & $state $f.Substring($root.Length + 1).Replace('\', '/'); foreach ($k in $ide.files[$f].Keys) { $st[$k] = $ide.files[$f][$k] } }
        foreach ($x in $ide.rows) { & $add ([pscustomobject][ordered]@{ rule = ''; message = $x.text; file = $x.file.Substring($root.Length + 1).Replace('\', '/'); line = $x.line; column = $x.column; severity = $x.severity; source = 'ide' }) }
        $vsx = if ($ide.status -eq 'OK') { @(Get-SonarIdeExtension -CachedOnly | Where-Object { $_ -notmatch 'VS Code' }) } else { @() }
        $src.ide = [pscustomobject][ordered]@{ status = $ide.status; detail = $ide.detail; connectedMode = "$($s.connectedMode.status)"
            sonarForIde = $(if ($ide.status -ne 'OK') { '' } elseif ($vsx.Count) { $vsx -join '; ' } else { 'not found in the Visual Studio extension folders: only compiler and analyzer findings can appear' }) }
    }
    if ('build' -in $want) {
        $cs = @($paths | Where-Object { $_ -match '\.cs$' })
        if (-not $cs.Count) { $src.build = [pscustomobject][ordered]@{ status = 'NOT_APPLICABLE'; detail = $(if ($inScope -eq 'solution') { 'build diagnostics are read per file: give -File or -Scope changed' } else { 'no C# file in scope' }) } }
        else {
            $logs = @("$Report" -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            foreach ($l in $logs) { if (-not (Test-Path -LiteralPath $l -PathType Leaf)) { throw "Build log not found: $l." } }
            if (-not $logs.Count) { $logs = @(Get-ChildItem -LiteralPath (Get-BuildLogDir $r.id) -Filter *.log -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }) }   # the logs of affected's stage A builds
            $an = @(Get-AnalysisStatus $root $cs $null $logs -Rows)
            foreach ($a in $an) {
                $st = & $state $a.file; $st.build = $a.status; if ($a.status -ne 'ANALYZED') { $st.buildReason = $a.reason }
                foreach ($d in @($a.rows | Where-Object { $_ })) {
                    $rule = if ($d.id -match '^S\d+$' -and $a.file -match '\.cs$') { "csharpsquid:$($d.id)" } else { $d.id }   # SonarAnalyzer ids as the server names them
                    & $add ([pscustomobject][ordered]@{ rule = $rule; message = $d.message; file = $a.file; line = $d.line; column = $d.column; severity = $d.severity; source = 'build' })
                }
            }
            $ok = @($an | Where-Object { $_.status -eq 'ANALYZED' }).Count
            $src.build = [pscustomobject][ordered]@{ status = $(if ($ok) { 'OK' } else { 'NOT VERIFIED' }); detail = "$ok of $($cs.Count) C# file(s) compiled after their last change in a logged build$(if (-not $logs.Count) { '; no build log: run the affected stage A build' })" }
        }
    }
    if ('server' -in $want) {
        if ($refusal) { $src.server = [pscustomobject]$refusal }   # no request made
        elseif ($inScope -ne 'solution' -and -not $paths.Count) { $src.server = [pscustomobject][ordered]@{ status = 'NOT_APPLICABLE'; detail = 'no file in scope' } }
        else {
            $k = $s.projectKey; if ($k -notmatch '^[\w.:-]+$') { throw "Project key '$k' has unexpected characters." }
            Add-MemoryLog $r.id 'network' "GET $(Get-HostName $s.host) issues"
            $comp = if ($paths.Count) { @($paths | ForEach-Object { "${k}:$_" }) -join ',' } else { $k }
            try {
                $res = Invoke-SonarApi $s.host "api/issues/search?componentKeys=$(& $esc $comp)&resolved=false&ps=100$(if ($NewCode) { '&inNewCodePeriod=true' })$(if ($Key -match ':') { "&rules=$(& $esc $Key)" })$ctx"
                foreach ($i in @($res.issues | Where-Object { $_ })) {
                    & $add ([pscustomobject][ordered]@{ rule = "$($i.rule)"; message = "$($i.message)"; file = $(if ($i.component -like "${k}:*") { $i.component.Substring($k.Length + 1) } else { "$($i.component)" }); line = $i.line
                            column = $(if ($i.textRange) { [int]$i.textRange.startOffset + 1 } else { $null }); severity = "$($i.severity)"; impacts = (@($i.impacts | ForEach-Object { "$($_.softwareQuality):$($_.severity)" }) -join ' '); source = 'server' })
                }
                $src.server = [pscustomobject][ordered]@{ status = 'OK'; total = $res.total; detail = 'the last analysis uploaded for this branch or pull request, not local changes' }
            } catch {
                $code = try { [int]$_.Exception.Response.StatusCode } catch { 0 }
                $src.server = [pscustomobject][ordered]@{ status = 'SONAR_ERROR'; httpStatus = $code; error = $_.Exception.Message }
            }
        }
    }
    $kept = @($issues | Where-Object { -not $Key -or -not $_.rule -or (& $tail $_.rule) -eq (& $tail $Key) })   # a row without a rule may be the one asked for
    if ($Key -or $Text) {   # the finding is gone only when an analysis ran after the change and nothing with that rule or text is left
        foreach ($p in $paths) {
            $st = & $state $p
            $local = @($issues | Where-Object { $_.file -eq $p -and ($_.source -split '\+' | Where-Object { $_ -ne 'server' }) })
            $left = @($local | Where-Object { ($Key -and $_.rule -and (& $tail $_.rule) -eq (& $tail $Key)) -or ($Text -and (& $norm $_.message) -eq (& $norm $Text)) })
            $st.validation = if ($left.Count) { 'FAILED' } elseif ($st.analysis -ne 'ANALYZED') { 'NOT VERIFIED' } elseif (-not $Text -and @($local | Where-Object { -not $_.rule }).Count) { 'NOT VERIFIED' } else { 'PASSED' }
            $st.validationDetail = switch ($st.validation) {
                'FAILED' { "still reported at line $(@($left | ForEach-Object { $_.line }) -join ', ')" }
                'PASSED' { 'analyzed after the change; nothing with that rule or text is left' }
                default { if ($st.analysis -ne 'ANALYZED') { "no analysis was observed after the change (IDE: $(if ($st.analysis) { $st.analysis } elseif ($src.ide) { $src.ide.status } else { 'not read' }))" } else { 'IDE rows have no rule id: give the finding''s text with -Text' } } }
        }
    }
    # Each finding's enclosing method or type from the architecture index (arch; stale when the file changed since), and its rule's documentation.
    $archDir = Get-ArchCache $r.id
    $locs = @($kept | Where-Object { $_.file -match '\.cs$' -and $_.line } | ForEach-Object { "$($_.file):$($_.line)" } | Select-Object -Unique)
    $out.symbols = if (-not $locs.Count) { 'no C# finding to map' } elseif (-not (Test-Path -LiteralPath (Join-Path $archDir 'index.json'))) { "not mapped: run arch -Repo $($r.id) once to build the architecture index" } else {
        $m = Invoke-ArchAnalyzer @('locate', '--out', $archDir, '--at', ($locs -join ';'))
        if ($m -is [string]) { "not mapped: $m" } else {
            $hit = @{}; foreach ($x in @($m.locations)) { if ($x.symbol) { $hit[$x.at] = $x } }
            foreach ($i in $kept) {
                $x = $hit["$($i.file):$($i.line)"]; if (-not $x) { continue }
                $i | Add-Member -NotePropertyName symbol -NotePropertyValue "$($x.kind) $($x.name)$(if ($x.container) { ' in ' + (($x.container -split '@', 2)[0] -split '[.:]')[-1] })"
                if ($x.stale) { $i | Add-Member -NotePropertyName symbolStale -NotePropertyValue $true }
            }
            "mapped from the architecture index of $($m.scannedAt)"
        }
    }
    foreach ($i in $kept) { $h = Get-RuleHelp $i.rule; if ($h) { $i | Add-Member -NotePropertyName help -NotePropertyValue $h } }
    $out.status = if (@($src.Values | Where-Object { $_.status -eq 'OK' }).Count) { 'OK' } elseif ($inScope -ne 'solution' -and -not $paths.Count) { 'NO_FILES' } else { 'NOT VERIFIED' }
    $out.verifiedAt = (Get-Date).ToString('s'); $out.scope = $inScope; $out.sources = [pscustomobject]$src
    $out.files = @($paths | Select-Object -First 50 | ForEach-Object { $o = [ordered]@{ file = $_ }; if ($fs.ContainsKey($_)) { foreach ($k in $fs[$_].Keys) { $o[$k] = $fs[$_][$k] } }; [pscustomobject]$o })
    $out.total = $kept.Count; $out.issues = @($kept | Sort-Object file, line | Select-Object -First 200)
    $out.next = if ($out.status -eq 'NO_FILES') { "No file in scope ($inScope): name the files with -File, or use -Scope solution." } else {
        'source says who reported each finding: ide (the live Error List), build (the last logged build), server (the last uploaded analysis, not local changes). A finding without rule came from the IDE, whose interface has no rule ids: identify it by its text. A file is Sonar-checked only when its analysis is ANALYZED; OPENED, READ, NOT_OPEN, or an IDE source that is not OK is NOT VERIFIED.' }
    [pscustomobject]$out
}

# sonar: the repository's Sonar setup, or one read-only server query (-Check); -Check issues also reads the IDE and the build. Never uploads an analysis.
function Invoke-SonarCommand {
    $r = Resolve-Repo $Repo
    $auth = Assert-Preflight $r
    $s = if ($Check -eq 'issues') { Get-SonarSetup $r -Brief -Binding } elseif ($Check) { Get-SonarSetup $r -Brief } else { Get-SonarSetup $r }   # a query needs only the project key, server, and token (issues: the binding too): no machine scan
    if (-not $Check) { $s | ConvertTo-Json -Depth 3; exit 0 }
    # Values go into a URL: validate them first.
    if ($Branch -and $PullRequest) { throw 'Give -Branch or -PullRequest, not both.' }
    if ($Branch -and $Branch -notmatch '^[A-Za-z0-9_./-]{1,200}$') { throw "Branch '$Branch' has characters a Sonar branch name cannot have." }
    if ($PullRequest -and $PullRequest -notmatch '^\d{1,10}$') { throw "Pull request '$PullRequest' must be a number." }
    if ($Key -and $Key -notmatch $(if ($Check -eq 'issues') { '^([\w.-]+:)?[\w.-]+$' } else { '^[\w.-]+:[\w.-]+$' })) { throw "Rule key '$Key' must look like csharpsquid:S3776$(if ($Check -eq 'issues') { ' or S3776' })." }
    $out = [ordered]@{ check = $Check; repo = $r.id; projectKey = $s.projectKey; host = $s.host; branch = $Branch; pullRequest = $PullRequest }
    $hostName = Get-HostName $s.host; $hostIssue = Get-HostIssue $s.host
    $refusal = if (-not $s.serverQueries) {
        $missing = @(); if (-not $s.projectKey) { $missing += 'project key (sonar-project.properties or pipeline)' }
        if (-not $s.host) { $missing += 'server URL (SONAR_HOST_URL or sonar.host.url)' }; if (-not $s.tokenSet) { $missing += 'token in the SONAR_TOKEN environment variable' }
        [ordered]@{ status = 'NO_SERVER'; missing = $missing }
    } elseif ($auth.allowedHosts -notcontains $hostName) {   # no network call to a host the policy or authorization does not allow
        [ordered]@{ status = 'HOST_NOT_ALLOWED'; reason = "'$hostName' is not an allowed host for '$($r.id)'. An administrator lists it in the policy (allowedHosts), or the developer records it: authorize -Repo $($r.id) -Reference ""<approval>"" -Classification <c> -Hosts ""$hostName""." }
    } elseif ($hostIssue) { [ordered]@{ status = 'INSECURE_HOST'; reason = "No request was made: $hostIssue." } }
    $esc = { param($v) [Uri]::EscapeDataString($v) }
    $ctx = if ($Branch) { "&branch=$(& $esc $Branch)" } elseif ($PullRequest) { "&pullRequest=$PullRequest" } else { '' }
    if ($Check -eq 'issues') { Get-SonarIssues $r $s $out $refusal | ConvertTo-Json -Depth 5 -Compress; exit 0 }
    if ($refusal) { foreach ($n in $refusal.Keys) { $out[$n] = $refusal[$n] }; [pscustomobject]$out | ConvertTo-Json -Depth 3; exit 0 }
    Add-MemoryLog $r.id 'network' "GET $hostName $Check"
    $k = $s.projectKey
    if ($k -notmatch '^[\w.:-]+$') { throw "Project key '$k' has unexpected characters." }
    $paths = @("$File" -split ';' | Where-Object { $_.Trim() } | ForEach-Object { $_.Trim() -replace '\\', '/' })
    $rel = { param($component) if ($component -like "${k}:*") { $component.Substring($k.Length + 1) } else { $component } }
    try {
        switch ($Check) {
            'gate' {
                $g = (Invoke-SonarApi $s.host "api/qualitygates/project_status?projectKey=$(& $esc $k)$ctx").projectStatus
                $out.gate = $g.status
                $out.conditions = @($g.conditions | Sort-Object { $_.status -ne 'ERROR' } | ForEach-Object { [pscustomobject][ordered]@{ metric = $_.metricKey; status = $_.status; comparator = $_.comparator; threshold = $_.errorThreshold; actual = $_.actualValue } })
                # Which commit the gate describes: older than HEAD means local changes are not in it.
                try {
                    $a = @((Invoke-SonarApi $s.host "api/project_analyses/search?project=$(& $esc $k)&ps=1$ctx").analyses)[0]
                    if ($a) {
                        $headSha = "$(Invoke-Quiet git -C $r.path rev-parse HEAD)"
                        $out.analysis = [pscustomobject][ordered]@{ key = $a.key; date = $a.date; revision = $a.revision; behindHead = [bool]($a.revision -and $a.revision -ne $headSha) }
                    }
                } catch { $out.analysis = 'not available' }
            }
            'hotspots' {
                $res = Invoke-SonarApi $s.host "api/hotspots/search?projectKey=$(& $esc $k)&status=TO_REVIEW&ps=100$(if ($NewCode) { '&inNewCodePeriod=true' })$(if ($paths) { '&files=' + (& $esc ($paths -join ',')) })$ctx"
                $out.total = $res.paging.total
                $out.hotspots = @($res.hotspots | ForEach-Object { [pscustomobject][ordered]@{ file = (& $rel $_.component); line = $_.line; probability = $_.vulnerabilityProbability; category = $_.securityCategory; rule = $_.ruleKey; message = $_.message } })
            }
            'coverage' {
                if ($paths) {
                    $out.files = @(foreach ($p in $paths) {
                            $fk = & $esc "${k}:$p"
                            $m = (Invoke-SonarApi $s.host "api/measures/component?component=$fk&metricKeys=coverage,line_coverage,branch_coverage,new_coverage$ctx").component.measures
                            $lines = @((Invoke-SonarApi $s.host "api/sources/lines?key=$fk$ctx").sources)
                            [pscustomobject][ordered]@{
                                file = $p; measures = (@($m | ForEach-Object { "$($_.metric)=$(if ($null -ne $_.value) { $_.value } else { $_.period.value })" }) -join ' ')
                                uncovered = (Join-Ranges @($lines | Where-Object { $null -ne $_.lineHits -and $_.lineHits -eq 0 } | ForEach-Object { $_.line }))
                                partialBranches = (Join-Ranges @($lines | Where-Object { $_.conditions -and $_.coveredConditions -lt $_.conditions } | ForEach-Object { $_.line }))
                            } })
                } else {
                    $res = Invoke-SonarApi $s.host "api/measures/component_tree?component=$(& $esc $k)&metricKeys=coverage,uncovered_lines&qualifiers=FIL&strategy=leaves&s=metric&metricSort=coverage&asc=true&ps=20$ctx"
                    $out.worstFiles = @($res.components | ForEach-Object { [pscustomobject][ordered]@{ file = (& $rel $_.key); measures = (@($_.measures | ForEach-Object { "$($_.metric)=$($_.value)" }) -join ' ') } })
                }
            }
            'duplication' {
                if ($paths) {
                    $out.files = @(foreach ($p in $paths) {
                            $d = Invoke-SonarApi $s.host "api/duplications/show?key=$(& $esc "${k}:$p")$ctx"
                            $names = @{}; foreach ($f in $d.files.PSObject.Properties) { $names[$f.Name] = (& $rel $f.Value.key) }
                            [pscustomobject][ordered]@{ file = $p; blocks = @($d.duplications | ForEach-Object { (@($_.blocks | ForEach-Object { "$($names[$_._ref]):$($_.from)-$($_.from + $_.size - 1)" }) -join ' = ') }) } })
                } else {
                    $res = Invoke-SonarApi $s.host "api/measures/component_tree?component=$(& $esc $k)&metricKeys=duplicated_lines_density,duplicated_lines,duplicated_blocks&qualifiers=FIL&strategy=leaves&s=metric&metricSort=duplicated_lines&asc=false&ps=20$ctx"
                    $out.worstFiles = @($res.components | Where-Object { @($_.measures | Where-Object { [double]$_.value -gt 0 }).Count } | ForEach-Object { [pscustomobject][ordered]@{ file = (& $rel $_.key); measures = (@($_.measures | ForEach-Object { "$($_.metric)=$($_.value)" }) -join ' ') } })
                }
            }
            'rule' {
                if (-not $Key) { throw 'sonar -Check rule needs -Key <rule key>, e.g. csharpsquid:S3776.' }
                $shown = Invoke-SonarApi $s.host "api/rules/show?key=$(& $esc $Key)&actives=true"; $rule = $shown.rule
                $html = if ($rule.htmlDesc) { $rule.htmlDesc } else { (@($rule.descriptionSections | ForEach-Object { $_.content }) -join "`n") }
                $desc = [Net.WebUtility]::HtmlDecode(($html -replace '<[^>]+>', ' ' -replace '\s+', ' ')).Trim()
                $out.rule = [pscustomobject][ordered]@{ key = $rule.key; name = $rule.name; severity = $rule.severity; type = $rule.type; language = $rule.langName; description = $(if ($desc.Length -gt 2000) { $desc.Substring(0, 2000) + '...' } else { $desc }) }
                # Whether the rule applies here: active in this project's quality profile, with its parameters (such as S1541's maximum).
                try {
                    $qp = @((Invoke-SonarApi $s.host "api/qualityprofiles/search?project=$(& $esc $k)").profiles | Where-Object { $_.language -eq $rule.lang })
                    $act = @($shown.actives | Where-Object { @($qp | ForEach-Object { $_.key }) -contains $_.qProfile })[0]
                    $out.activeInProject = [pscustomobject][ordered]@{ active = [bool]$act; profile = (@($qp | ForEach-Object { $_.name }) -join ', '); severity = "$($act.severity)"; params = (@($act.params | ForEach-Object { "$($_.key)=$($_.value)" }) -join ' ') }
                } catch { $out.activeInProject = "not verified: the project's quality profile could not be read ($($_.Exception.Message))" }
            }
        }
        $out.status = 'OK'
        $out.note = 'Server data is the last analysis uploaded for this branch or pull request, not uncommitted local changes.'
    } catch {
        $code = try { [int]$_.Exception.Response.StatusCode } catch { 0 }
        $out.status = 'SONAR_ERROR'; $out.httpStatus = $code; $out.error = $_.Exception.Message
    }
    [pscustomobject]$out | ConvertTo-Json -Depth 4
    exit 0
}

# coverage: coverage of the lines changed against HEAD, from Cobertura or LCOV reports (the repo's own coverage tool).
function Invoke-CoverageCommand {
    $r = Resolve-Repo $Repo
    $null = Assert-Preflight $r
    $reports = @("$Report" -split ';' | Where-Object { $_.Trim() } | ForEach-Object { $_.Trim() })
    if (-not $reports) { throw 'coverage needs -Report "<cobertura.xml or lcov.info>[;<more>]".' }
    foreach ($f in $reports) { if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { throw "Coverage report not found: $f" } }
    $data = @{}
    foreach ($f in $reports) { $one = Read-CoverageReport $f $r.path; foreach ($k in $one.Keys) { $data[$k] = $one[$k] } }
    $changed = Get-ChangedLines $r.path
    $rootN = ($r.path -replace '\\', '/').ToLowerInvariant().TrimEnd('/')
    $rows = @(); $notInReport = @(); $totCov = 0; $totHit = 0
    foreach ($p in ($changed.Keys | Sort-Object)) {
        $pn = $p.ToLowerInvariant()
        $hit = $data.Keys | Where-Object { $_ -eq "$rootN/$pn" -or $_.EndsWith("/$pn") -or $_ -eq $pn } | Select-Object -First 1
        if (-not $hit) { $notInReport += $p; continue }
        $e = $data[$hit]
        $coverable = @($changed[$p] | Where-Object { $e.hits.ContainsKey($_) })
        $uncovered = @($coverable | Where-Object { $e.hits[$_] -eq 0 })
        $totCov += $coverable.Count; $totHit += $coverable.Count - $uncovered.Count
        $rows += [pscustomobject][ordered]@{
            file = $p; changedLines = $changed[$p].Count; coverable = $coverable.Count; covered = $coverable.Count - $uncovered.Count
            percent = $(if ($coverable.Count) { [math]::Round(100 * ($coverable.Count - $uncovered.Count) / $coverable.Count, 1) } else { $null })
            uncovered = (Join-Ranges $uncovered); partialBranches = (Join-Ranges @($changed[$p] | Where-Object { $e.partial.ContainsKey($_) }))
        }
    }
    $pct = if ($totCov) { [math]::Round(100 * $totHit / $totCov, 1) } else { $null }
    $rq = $r.cfg.quality.coverage; $rqn = 0.0
    $own = $null -ne $rq -and [double]::TryParse("$rq", [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$rqn) -and $rqn -gt 0 -and $rqn -le 100
    $limit = if ($own) { $rqn } else { 85 }   # provisional objective until the gate or the registry gives one; not an organizational requirement
    [pscustomobject][ordered]@{
        repo = $r.id; reports = $reports; changedFiles = $changed.Count
        coverableChangedLines = $totCov; coveredChangedLines = $totHit
        percent = $pct
        threshold = [ordered]@{ percent = $limit; source = $(if ($own) { 'repository (quality.coverage in the registry)' } elseif ($null -ne $rq) { "provisional default (quality.coverage '$rq' is not a percent from 1 to 100)" } else { 'provisional default: no server gate or repository threshold; not an organizational requirement' }); note = 'A coverage condition of the server quality gate (sonar -Check gate) replaces this threshold.' }
        meetsThreshold = $(if ($null -eq $pct) { $null } else { $pct -ge $limit })
        files = $rows; notInReport = $notInReport
    } | ConvertTo-Json -Depth 3
    exit 0
}

# branchinfo: read-only. Repository, branch, HEAD, uncommitted changes, recorded relationship to PBIs, and the options.
function Invoke-BranchinfoCommand {
    $r = Resolve-Repo $Repo; $null = Assert-Preflight $r
    $ttl = if ($Title) { $Title } elseif ($Id) { $td = Get-RepoTasks $r.id | Where-Object { $_.id -eq $Id } | Select-Object -First 1; if ($td.json.title) { "$($td.json.title)" } elseif ($td) { Get-PbiTitle (Join-Path $td.dir 'refined-pbi.md') } else { '' } } else { '' }
    Get-BranchInfo $r $Id $ttl | ConvertTo-Json -Depth 4
    exit 0
}

# branchcreate / branchuse: act only after the developer chose (-Confirmed). git switch never discards uncommitted
# changes (it refuses when they would be overwritten); nothing is stashed, reset, or cleaned.
function Invoke-BranchChangeCommand {   # branchcreate and branchuse
    if (-not $Confirmed) { throw "$Command changes the working tree's branch: show branchinfo, let the developer choose, then rerun with -Confirmed." }
    if (-not $Id) { throw "$Command needs -Id <PBI> (the task must exist: run intake first)." }
    $r = Resolve-Repo $Repo; $null = Assert-Preflight $r
    $dir = Find-TaskDir $Id $r.id
    $dirty = @(Invoke-Quiet git -C $r.path -c core.quotepath=off status --porcelain=v1)
    $refs = @(Invoke-Quiet git -C $r.path for-each-ref '--format=%(refname)' refs/heads refs/remotes)
    $local = @($refs | Where-Object { $_ -like 'refs/heads/*' } | ForEach-Object { $_.Substring(11) })
    $remote = @($refs | Where-Object { $_ -like 'refs/remotes/*' -and $_ -notlike '*/HEAD' } | ForEach-Object { $_.Substring(13) })
    $before = "$(Invoke-Quiet git -C $r.path symbolic-ref --short -q HEAD)"
    $baseHead = ''; $baseName = ''
    if ($Command -eq 'branchcreate') {
        if (-not $Name -or -not $Base) { throw 'branchcreate needs -Name <new branch> and -Base <the base branch the developer confirmed>.' }
        if (-not (Test-BranchName $Name)) { throw "Branch name '$Name' must be lowercase, Git-safe, with hyphens, e.g. feature/300186-create-paint-system." }
        if ($local -contains $Name -or ($remote | Where-Object { $_ -like "*/$Name" })) { throw "Branch '$Name' already exists. Choose another name (branchinfo suggests an alternative) or use branchuse." }
        $start = if ($local -contains $Base) { $Base } elseif ($remote -contains "origin/$Base") { "origin/$Base" } else { throw "Base branch '$Base' was not found locally or on origin." }
        if ($dirty.Count -and -not $AllowDirty) { throw "$($dirty.Count) uncommitted change(s) are present. Nothing was switched. Ask the developer; with their agreement rerun with -AllowDirty (git carries the changes along and refuses if they would be overwritten)." }
        $baseName = $Base; $baseHead = "$(Invoke-Quiet git -C $r.path rev-parse --short $start)"
        $msg = Invoke-GitSwitch $r.path @('-c', $Name, $start)
        if ($LASTEXITCODE -ne 0) { throw "git could not create '$Name' from '$start' (nothing was changed): $($msg.Trim())" }
        $decision = 'created'
    } else {
        if ($Name -and $Name -ne $before) {
            if (-not ($local -contains $Name -or ($remote | Where-Object { $_ -like "*/$Name" }))) { throw "Branch '$Name' does not exist locally or on origin." }
            if ($dirty.Count -and -not $AllowDirty) { throw "$($dirty.Count) uncommitted change(s) are present. Nothing was switched. Ask the developer; with their agreement rerun with -AllowDirty." }
            $msg = Invoke-GitSwitch $r.path @($Name)
            if ($LASTEXITCODE -ne 0) { throw "git could not switch to '$Name' (nothing was changed): $($msg.Trim())" }
            $decision = 'selected'
        } else { $decision = 'continued' }
    }
    $nowBranch = "$(Invoke-Quiet git -C $r.path symbolic-ref --short -q HEAD)"
    Update-TaskJson $dir @{ branch = $nowBranch; branchDecision = $decision; baseBranch = $baseName; baseHead = $baseHead; branchFrom = $before; branchDecidedAt = (Get-Date).ToString('s'); branchHead = "$(Invoke-Quiet git -C $r.path rev-parse --short HEAD)" }
    [pscustomobject][ordered]@{ status = 'BRANCH_READY'; decision = $decision; id = $Id; branch = $nowBranch; previousBranch = $before; base = $baseName; uncommittedKept = $dirty.Count; stashed = $false } | ConvertTo-Json
    exit 0
}

# tasks: the tasks of a repository, with their own statuses (each PBI has its own; nothing is shared).
function Invoke-TasksCommand {
    $rid = if ($Repo) { (Resolve-Repo $Repo).id } else { $w = Get-WorkspaceRepo; if ($w) { $w } else { throw 'tasks needs -Repo <id> (no registered repository is the open workspace).' } }
    $rows = @(Get-RepoTasks $rid | Where-Object { $_.hasPbi } | Sort-Object modified -Descending | Select-Object -First 40 | ForEach-Object { Get-TaskSummary $_ })
    [pscustomobject][ordered]@{ repo = $rid; count = $rows.Count; inProgress = @($rows | Where-Object { -not $_.completed } | ForEach-Object { $_.id }); completed = @($rows | Where-Object { $_.completed } | ForEach-Object { $_.id }); tasks = $rows } | ConvertTo-Json -Depth 4
    exit 0
}

# snapshot: copy a task's spec, plan, PBI, inputs, and state into history\ before they are modified.
function Invoke-SnapshotCommand {
    if (-not $Id) { throw 'snapshot needs -Id <PBI>.' }
    $dir = Find-TaskDir $Id $Repo
    $j = try { Get-Content -LiteralPath (Join-Path $dir 'task.json') -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $null }
    $sd = if ($j.specDir) { "$($j.specDir)" } else { $dir }
    $why = ConvertTo-Slug $(if ($Text) { $Text } else { 'before-change' }) 40
    $snap = Join-Path $dir ("history\{0}-{1}" -f (Get-Date).ToString('yyyyMMdd-HHmmss'), $why)
    New-Item -ItemType Directory -Force -Path $snap | Out-Null
    $copied = @(foreach ($f in @((Join-Path $sd 'spec.md'), (Join-Path $sd 'plan.md'), (Join-Path $dir 'refined-pbi.md'), (Join-Path $dir 'inputs.json'), (Join-Path $dir 'task.json'))) {
            if (Test-Path -LiteralPath $f) { Copy-Item -LiteralPath $f (Join-Path $snap ([IO.Path]::GetFileName($f))) -Force; [IO.Path]::GetFileName($f) } })
    $sum = Get-TaskSummary ([pscustomobject]@{ id = $Id; dir = $dir; json = $j; modified = (Get-Item -LiteralPath $dir).LastWriteTime })
    [pscustomobject]@{ reason = $Text; at = (Get-Date).ToString('s'); statuses = $sum; files = $copied } | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $snap 'snapshot.json') -Encoding UTF8
    [pscustomobject][ordered]@{ status = 'SNAPSHOT_SAVED'; id = $Id; folder = $snap; files = $copied; statuses = $sum } | ConvertTo-Json -Depth 4
    exit 0
}
# profile: which repository development profile applies (Modern, Framework, or none), with the evidence and the files to load.
function Invoke-ProfileCommand {
    $r = Resolve-Repo $Repo; $null = Assert-Preflight $r
    $p = Get-RepoProfile $r $Key $Query $Task
    $p | Add-Member -NotePropertyName conventions -NotePropertyValue (Get-ArchitectureConventions $r.path @(Invoke-Quiet git -C $r.path -c core.quotepath=off ls-files -co --exclude-standard))   # here, not in Get-RepoProfile: affected and review do not need them
    $p | ConvertTo-Json -Depth 5
    exit 0
}
function Invoke-GuidanceCommand {   # read-only audit of the repository's instruction files
    $r = Resolve-Repo $Repo; $null = Assert-Preflight $r
    Get-GuidanceAudit $r | ConvertTo-Json -Depth 4
    exit 0
}

# affected: staged test selection for the current change (read-only). A: build, B: focused tests, C: affected regression, D: full suite once.
function Invoke-AffectedCommand {
    $r = Resolve-Repo $Repo; $null = Assert-Preflight $r
    $against, $scope = Get-ChangeBase $r $Base
    $architecture = Get-WorkspaceArchitecture $r -RoutingOnly
    if ($architecture.typescriptWorkspaces.Count -and -not $architecture.projects.Count) {
        Get-TypeScriptAffected $r $architecture $against | ConvertTo-Json -Depth 8 -Compress
        return
    }
    $a = Get-AffectedTests $r $against
    $prof = Get-RepoProfile $r $Key
    $full = if ($prof.commands) { $prof.commands.test } else { "the repository's full test command (section 2, Commands)" }
    $wide = [bool]$a.buildWide.Count
    $status = if (-not $a.changed) { 'NO_CHANGES' } elseif (-not $a.projects) { 'NO_PROJECTS' } elseif ($wide) { 'BUILD_WIDE' } else { 'SELECTED' }
    [pscustomobject][ordered]@{ status = $status; repo = $r.id; scope = $scope; profile = $(if ($prof.profile) { $prof.profile } else { "none ($($prof.status))" })
        changed = $a.changed; changedFiles = $a.changedFiles; projects = $a.projects; testProjects = $a.testProjects; buildWide = $a.buildWide
        directProjects = $a.directProjects; affectedProjects = $a.affectedProjects; untestedChanges = $a.untestedChanges
        stages = [ordered]@{
            A_build = @(if ($wide -or -not $a.projects) { @(if ($prof.commands) { "$($prof.commands.build)$(if ($prof.commands.build -match '^dotnet build ') { Get-BuildLogArg $r.id 'solution' })" } else { "the repository's build command" }) } else { $a.build })
            B_focused = @($a.focused)
            C_regression = @(if ($wide -or -not $a.projects) { $full } else { $a.regression })
            D_full = [ordered]@{ command = $full; workingDirectory = $(if ($prof.commands) { $prof.commands.workingDirectory } else { $r.path }); when = 'required for build-wide changes, demonstrated integration risk or repository policy; report blockers, never skip required verification' } }
        next = $(if ($wide) { "Build-wide files changed ($($a.buildWide -join ', ')): build the solution and run the full suite; the change cannot be narrowed to projects." } elseif ($a.changed) { 'Run A after edits, B for changed code and C for dependent regressions. D only for demonstrated integration risk or repository policy. Check commands with guard -Repo. untestedChanges need focused tests (S8).' } else { 'Nothing changed against the base.' }) } | ConvertTo-Json -Depth 5
    exit 0
}

# review: pre-PR review of the change (recorded PR regression scenarios, profile rules, git diff --check). Read-only.
function Invoke-ReviewCommand {
    $r = Resolve-Repo $Repo; $null = Assert-Preflight $r
    $architecture = Get-WorkspaceArchitecture $r -RoutingOnly
    if ($architecture.typescriptWorkspaces.Count -and -not $architecture.projects.Count) {
        $against, $scope = Get-ChangeBase $r $Base
        Invoke-TypeScriptReview $r $architecture $against
        return
    }
    $logs = @("$Report" -split ';' | Where-Object { $_.Trim() } | ForEach-Object { $_.Trim() })
    $logs = @(foreach ($l in $logs) { if (-not (Test-Path -LiteralPath $l -PathType Leaf)) { throw "Build log not found: $l (write it with dotnet build ... ""-flp:LogFile=<path>;Verbosity=normal"")." }; (Resolve-Path -LiteralPath $l).Path })
    if (-not $logs.Count) { $logs = @(Get-ChildItem -LiteralPath (Get-BuildLogDir $r.id) -Filter *.log -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }) }   # the logs of affected's stage A builds
    $against, $scope = Get-ChangeBase $r $Base
    $prof = Get-RepoProfile $r $Key
    $def = if ($prof.profile) { @((Read-Profiles).profiles) | Where-Object { $_.id -eq $prof.profile } | Select-Object -First 1 } else { $null }
    $res = Get-ReviewFindings $r $def $against
    $err = @($res.findings | Where-Object { $_.severity -eq 'error' }).Count; $warn = @($res.findings | Where-Object { $_.severity -eq 'warning' }).Count
    $dr = Get-DiffRisk $r $def $against; $high = @($dr.risk | Where-Object { $_.level -eq 'high' }).Count
    $analysis = @(Get-AnalysisStatus $r.path $res.changedCs $res.changed $logs); $unverified = @($analysis | Where-Object { $_.status -eq 'NOT VERIFIED' }).Count
    if (@((Read-Lessons $r.id).lessons | Where-Object { $_.status -eq 'approved' }).Count) {   # history for lesson -Action report: what was caught, and later fixed
        $ev = [pscustomobject][ordered]@{ at = (Get-Date).ToString('s'); branch = "$(Invoke-Quiet git -C $r.path rev-parse --abbrev-ref HEAD)"; head = "$(Invoke-Quiet git -C $r.path rev-parse --short HEAD)"
            findings = @($res.findings | Where-Object { $_.rule -like 'lesson:*' -or $_.rule -like 'custom:*' } | ForEach-Object { "$($_.rule)|$($_.file)" } | Sort-Object -Unique) }
        New-Item -ItemType Directory -Force $LearningDir | Out-Null
        Add-LineLocked ((Get-LessonFile $r.id) -replace '\.json$', '.events.jsonl') (($ev | ConvertTo-Json -Compress) + "`n")
    }
    [pscustomobject][ordered]@{ status = $(if ($err) { 'FINDINGS' } elseif ($warn) { 'WARNINGS' } else { 'PASSED' }); repo = $r.id
        profile = $(if ($prof.profile) { $prof.profile } else { "none ($($prof.status))" }); scope = $scope; changedFiles = $res.files; csharpFilesReviewed = $res.reviewed; errors = $err; warnings = $warn
        findings = @($res.findings)
        analysis = $analysis; analysisNext = $(if ($unverified) { "$unverified changed C# file(s) NOT VERIFIED: run the affected stage A builds as printed (they write the build logs review reads), then review again." } elseif (@($analysis | Where-Object { $_.onChangedLines }).Count) { 'Analyzer warnings or errors on changed lines: fix those in scope, build again with the log, and rerun review.' } else { '' })
        highRisk = $high; risk = @($dr.risk)
        riskNext = $(@(if ($high) { 'High-risk files changed: verify affected dependents/integration; stage D only for demonstrated risk, build-wide changes or repository policy. List the risk in the handover.' }; if ($dr.note) { $dr.note }) -join ' ')
        scenarios = @('1 PUT function converts the validation exception the middleware handles', '2 POST function converts it', '3 duplicate changes', '4 validator not following sibling FluentValidation pattern', '5 command/query dependencies misplaced', '6 missing or outdated XML documentation')
        notChecked = @('build, tests, and analyzers (run them)', 'SonarCloud (sonar -Check gate/issues, or "not verified")', 'business behavior and API consumers (read them)', 'review comment threads, including duplicate comments (read the PR)') } | ConvertTo-Json -Depth 4
    exit 0
}

# decide: the developer's choice at a gate (Approve, Request changes, Custom response). Appends to the task's
# approvals.jsonl and, for approve and changes, rewrites the gate's status line. Never infers a decision.
function Invoke-DecideCommand {
    if (-not $Id -or -not $Gate -or -not $GateDecision) { throw 'decide needs -Id <PBI> -Gate G2|G3|G4 -Decision approve|changes|custom (and -Text for changes and custom).' }
    if ($GateDecision -ne 'approve' -and -not $Text) { throw "decide -Decision $GateDecision needs -Text with the developer's words." }
    $dir = Find-TaskDir $Id $Repo
    $j = try { Get-Content -LiteralPath (Join-Path $dir 'task.json') -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $null }
    $sd = if ($j.specDir) { "$($j.specDir)" } else { $dir }
    $wf = Read-Workflow
    $g = @($wf.gates) | Where-Object { $_.id -eq $Gate } | Select-Object -First 1
    $doc = Join-Path $sd $g.document
    $now = Get-StatusLine $doc $g.key
    $out = [ordered]@{ id = $Id; gate = $Gate; title = $g.title; decision = $GateDecision; previousStatus = $now }
    $order = @($wf.gates | Where-Object { $_.document })
    $prev = $order | Select-Object -Index ([math]::Max(0, [array]::IndexOf(@($order | ForEach-Object { $_.id }), $Gate) - 1))
    $prevStatus = if ($prev.id -ne $Gate) { Get-StatusLine (Join-Path $sd $prev.document) $prev.key } else { '' }
    $refuse = if ($now -in 'no file', 'not started') { 'NOTHING_TO_DECIDE', "$($g.title) has no deliverable yet ($($g.document): $now)." }
        elseif ($GateDecision -eq 'approve' -and $now -match '(?i)^changes requested') { 'NEEDS_REVISION', "Changes were requested for $($g.title); revise $($g.document), set its $($g.key) back to Draft, and present it again before approval." }
        elseif ($GateDecision -eq 'approve' -and $now -match '(?i)^(approved|waived)') { 'ALREADY_APPROVED', "$($g.title) is already $now; nothing was recorded twice." }
        elseif ($GateDecision -eq 'approve' -and $prevStatus -match '(?i)^(draft|changes requested)') { 'OUT_OF_ORDER', "$($prev.title) ($prevStatus) must be approved before $($g.title)." }
        else { $null }
    if ($refuse) { $out.status = $refuse[0]; $out.message = $refuse[1]; [pscustomobject]$out | ConvertTo-Json -Depth 3; exit 0 }
    if ($Gate -eq 'G4' -and $GateDecision -eq 'approve') {
        $readiness = Get-ImplementationReadiness $doc
        if ($readiness.status -ne 'READY_FOR_APPROVAL') {
            $out.status = 'READINESS_BLOCKED'; $out.readiness = $readiness
            [pscustomobject]$out | ConvertTo-Json -Depth 6
            exit 0
        }
        # A plan that relies on a GraphQL schema is checked mechanically before approval: material incompatibilities block it.
        $readinessRows = @{}; foreach ($check in @($readiness.checks)) { $readinessRows[$check.check] = $check.status }
        if ($readinessRows['GraphQL schema'] -eq 'VERIFIED') {
            $gqlRepo = if ($Repo) { Resolve-Repo $Repo } elseif ($j.repo) { Resolve-Repo "$($j.repo)" } else { $null }
            $gql = if ($gqlRepo) { Get-GraphQLValidation $gqlRepo '' } else { 'the task records no repository' }
            $gqlBlockers = @(
                if ($gql -is [string]) { "GraphQL could not be validated mechanically: $gql" }
                else {
                    foreach ($gqlScope in @($gql.scopes)) {
                        foreach ($gqlError in @($gqlScope.errors)) { "$($gqlError.at): $($gqlError.message)" }
                        if ($readinessRows['Generated client'] -eq 'COMPATIBLE' -and $gqlScope.client.status -eq 'REGENERATION_NEEDED') {
                            "Generated client in $($gqlScope.scope) needs regeneration (missing: $(@($gqlScope.client.missing) -join ', '); stale: $(@($gqlScope.client.stale) -join ', ')), but the plan marks it COMPATIBLE."
                        }
                    }
                })
            if ($gqlBlockers.Count) {
                $out.status = 'GRAPHQL_BLOCKED'; $out.blockerCount = $gqlBlockers.Count; $out.blockers = @($gqlBlockers | Select-Object -First 20)
                $out.next = 'Resolve the listed schema/operation incompatibilities, or plan their fix and the client regeneration, then present the plan again. Nothing was approved.'
                [pscustomobject]$out | ConvertTo-Json -Depth 4
                exit 0
            }
            $out.graphql = [pscustomobject][ordered]@{ status = $gql.status; errors = 0; warnings = $gql.warningCount
                note = $(if ($gql.status -in 'NO_GRAPHQL', 'NO_SCHEMA') { 'no SDL schema in the repository (code-first or remote): the schema evidence is the plan''s, not mechanically verified' } else { 'operations and fragments validated against the repository schema' }) }
        }
    }
    $who = $env:USERNAME; $day = (Get-Date).ToString('yyyy-MM-dd')
    $sha = (Get-FileHash -LiteralPath $doc -Algorithm SHA256).Hash.ToLowerInvariant()   # the version the developer decided on
    $new = switch ($GateDecision) { 'approve' { "Approved (by $who, $day)" } 'changes' { "Changes requested (by $who, $day)" } default { $now } }
    if ($new -ne $now) {
        $text = [IO.File]::ReadAllText($doc)
        $text = ([regex]"(?m)^$([regex]::Escape($g.key)):[^\r\n]*").Replace($text, "$($g.key): $new", 1)
        Write-TextAtomic $doc $text
    }
    $rec = [pscustomobject][ordered]@{ at = (Get-Date).ToString('s'); pbi = $Id; gate = $Gate; title = $g.title; decision = $GateDecision; by = $who
        feedback = $(if ($Text) { Protect-Text $Text } else { '' }); document = $g.document; sha256 = $sha; status = $new }
    Add-LineLocked (Join-Path $dir 'approvals.jsonl') (($rec | ConvertTo-Json -Compress) + "`n")
    $after = Get-GateView $sd $wf
    $out.status = 'RECORDED'; $out.newStatus = $new; $out.record = $rec
    $out.next = switch ($GateDecision) {
        'approve' { $n = @($wf.gates) | Select-Object -Index ([array]::IndexOf(@($wf.gates | ForEach-Object { $_.id }), $Gate) + 1); "Continue with the work that leads to $($n.title)." }
        'changes' { "Revise $($g.document) as asked, set its $($g.key) to Draft, and present $($g.title) again." }
        default { 'Act on the instruction; the gate status is unchanged and nothing was approved.' } }
    $out.gates = $after.gates
    [pscustomobject]$out | ConvertTo-Json -Depth 4
    exit 0
}

# trace: acceptance criteria -> the tests plan.md section 6 lists for them -> their latest TRX outcome. Read-only.
function Invoke-TraceCommand {
    if (-not $Id) { throw 'trace needs -Id <PBI> (and -Path <.trx file or folder> when the results are not under TestResults or the task evidence folder).' }
    Get-TraceReport (Find-TaskDir $Id $Repo) $Path | ConvertTo-Json -Depth 6
    exit 0
}

# prtext: a pull request description in SDD format from spec, plan, trace, review risk, the Sonar table, and the approval
# times. Writes <task>\evidence\pr-description.md; never creates a pull request, commits, or pushes.
function Invoke-PrtextCommand {
    if (-not $Id) { throw 'prtext needs -Id <PBI> (and -Path <.trx file or folder> when the test results are elsewhere).' }
    $dir = Find-TaskDir $Id $Repo
    $j = try { Get-Content -LiteralPath (Join-Path $dir 'task.json') -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $null }
    $sd = if ($j.specDir) { "$($j.specDir)" } else { $dir }
    $specT = @(if (Test-Path -LiteralPath (Join-Path $sd 'spec.md')) { [IO.File]::ReadAllLines((Join-Path $sd 'spec.md')) })
    $planT = @(if (Test-Path -LiteralPath (Join-Path $sd 'plan.md')) { [IO.File]::ReadAllLines((Join-Path $sd 'plan.md')) })
    $field = { param($lines, $rx) $hit = @($lines | Where-Object { $_ -match $rx } | Select-Object -First 1); if ($hit.Count -and ($v = ($hit[0] -replace $rx, '').Trim())) { $v } else { '(not written)' } }
    $md = New-Object Collections.Generic.List[string]
    $md.Add("## $Id $(if ($j.title) { $j.title } else { & $field $specT '^#\s*Spec:\s*\S+\s*' })"); $md.Add('')
    $md.Add('### Summary'); $md.Add("- Problem: $(& $field $specT '^\s*-\s*Problem:')"); $md.Add("- Objective: $(& $field $specT '^\s*-\s*Objective:')"); $md.Add("- Gap map: $(& $field $specT '^Counts:')"); $md.Add('')
    $md.Add('### Tasks'); $md.Add('| Task | Status |'); $md.Add('|------|--------|')
    foreach ($t in @(Get-PlanTasks (Join-Path $sd 'plan.md') (Read-Workflow))) { $md.Add("| $($t.title) | $($t.status)$(if ($t.detail) { ": $($t.detail)" }) |") }
    $tr = Get-TraceReport $dir $Path
    $md.Add(''); $md.Add("### Acceptance criteria (trace: $($tr.status))"); $md.Add('| AC | REQ | Status | Tests | Readiness |'); $md.Add('|----|-----|--------|-------|-----------|')
    foreach ($a in @($tr.acs)) { $md.Add("| $($a.ac) | $($a.req) | $($a.status) | $(@($a.tests | ForEach-Object { "$($_.test) ($($_.outcome))" }) -join '<br>') | $($a.readiness) |") }
    if ($tr.evidence.stale) { $md.Add("Test results are older than the latest code change ($($tr.evidence.latestSourceChange)); they do not verify this code.") }
    $md.Add("Test results: $(if (@($tr.results).Count) { @($tr.results | ForEach-Object { "$(Split-Path $_.file -Leaf) ($($_.written))" }) -join ', ' } else { 'none found' })")
    $rid = if ($j.repo) { "$($j.repo)" } else { Split-Path (Split-Path $dir) -Leaf }
    $md.Add(''); $md.Add('### Change risk')
    try {
        $r = Resolve-Repo $rid; $null = Assert-Preflight $r
        $against, $scope = Get-ChangeBase $r "$($j.baseBranch)"
        $prof = Get-RepoProfile $r $Key
        $def = if ($prof.profile) { @((Read-Profiles).profiles) | Where-Object { $_.id -eq $prof.profile } | Select-Object -First 1 } else { $null }
        $dr = Get-DiffRisk $r $def $against
        $shown = @($dr.risk | Where-Object { $_.level -ne 'low' })
        $md.Add("Scope: $scope"); $md.Add('| File | Level | Reasons |'); $md.Add('|------|-------|---------|')
        foreach ($x in $shown) { $md.Add("| ``$($x.file)`` | $($x.level) | $(@($x.reasons) -join '; ') |") }
        $md.Add("Low-risk files: $(@($dr.risk).Count - $shown.Count)$(if ($dr.note) { ". $($dr.note)" })")
    } catch { $md.Add("Not available: $($_.Exception.Message)") }
    # Sonar: the plan's own table; only sources (a) and (b) are SonarCloud results.
    $src = & $field $planT '^Source:'; $gateLine = & $field $planT '^Gate:'   # not $gate: -Gate has a ValidateSet
    $ti = [array]::FindIndex([string[]]$planT, [Predicate[string]] { param($l) $l -match '^\|\s*Item\s*\|\s*Baseline\s*\|' })
    $rows = @(if ($ti -ge 0) { for ($i = $ti; $i -lt $planT.Count -and $planT[$i] -match '^\|'; $i++) { $planT[$i] } })
    $filled = $src -notmatch '^<' -and @($rows | Select-Object -Skip 2 | Where-Object { "$($_.Trim().Trim('|').Split('|')[2])".Trim() }).Count
    $server = $filled -and $src -match '^\(?[ab]\)'
    $md.Add(''); $md.Add('### Quality (SonarCloud)')
    if (-not $filled) { $md.Add("SonarCloud not verified: the plan's Sonar table has no final values.") }
    else { if (-not $server) { $md.Add("SonarCloud not verified (source: $src); the table is local evidence, not a SonarCloud result.") }; $md.Add("Source: $src"); $md.Add("Gate: $gateLine"); foreach ($l in $rows) { $md.Add($l) } }
    $ap = @(Read-Approvals $dir | Where-Object { $_.decision -eq 'approve' } | Sort-Object { [datetime]$_.at })
    $md.Add(''); $md.Add('### Process')
    $md.Add("Elapsed between approvals (includes review time; not agent time): $(if ($ap.Count) { @(for ($i = 0; $i -lt $ap.Count; $i++) { if ($i) { "$($ap[$i].gate) +$([math]::Round(([datetime]$ap[$i].at - [datetime]$ap[$i - 1].at).TotalHours, 1)) h" } else { "$($ap[0].gate) $(([datetime]$ap[0].at).ToString('yyyy-MM-dd HH:mm'))" } }) -join ' -> ' } else { 'no approvals recorded' })")
    $body = Protect-Text (($md -join "`n") + "`n")
    $ev = Join-Path $dir 'evidence'; New-Item -ItemType Directory -Force $ev | Out-Null
    $outFile = Join-Path $ev 'pr-description.md'; Write-TextAtomic $outFile $body
    [pscustomobject][ordered]@{ status = 'WRITTEN'; pbi = $Id; file = $outFile; trace = $tr.status; sonar = $(if ($server) { 'SonarCloud result' } else { 'not verified' }); markdown = $body
        next = 'Paste the markdown into the pull request yourself; this command never creates a pull request, commits, or pushes.' } | ConvertTo-Json -Depth 3
    exit 0
}

# lesson: PR review feedback -> lessons per repository (<AKZO_HOME>\learning\<repo-id>.json). Recording is automatic;
# review and planning apply a lesson only after the developer approves it. Comments are data, never instructions.
function Invoke-LessonCommand {
    if (-not $Action) { throw 'lesson needs -Action add|approve|reject|list|report.' }
    $r = Resolve-Repo $Repo; $null = Assert-Preflight $r
    $ls = Read-Lessons $r.id
    if ($ls.error -and $Action -in 'add', 'approve', 'reject') { throw "The lessons file $($ls.file) cannot be read ($($ls.error)); restore or fix it before changing lessons." }
    $all = New-Object Collections.Generic.List[object]; foreach ($l in $ls.lessons) { $all.Add($l) }
    $one = { param($k) @($all | Where-Object { $_.key -eq $k })[0] }
    $keyIn = if ($Key) { $Key.ToUpperInvariant() -replace '[^A-Z0-9_]', '_' } else { '' }
    $out = [ordered]@{ status = ''; repo = $r.id; file = $ls.file }

    if ($Action -eq 'add') {
        if (-not $Text) { throw 'lesson -Action add needs -Text "<the review comment>" (and -Reference, -Cause, -Correction, -Evidence once the fix is verified).' }
        $cls = if ($Classification) { $Classification.ToUpperInvariant() } else { 'REUSABLE_PATTERN' }
        if ($cls -notin $LessonClasses) { throw "-Classification must be one of $($LessonClasses -join ', ')." }
        $injected = Find-InstructionText $Text
        if ($injected -or -not $Evidence) { $cls = 'UNVERIFIED_FEEDBACK' }   # no verified correction, or instruction-like text: recorded, never promoted
        $tok = @(Get-Tokens $Text); $cat = @(Read-LessonPatterns)
        $pat = if ($keyIn) { @($cat | Where-Object { $_.key -eq $keyIn })[0] } else { @($cat | Where-Object { (Test-AnyToken $tok $_.topic) -and (Test-AnyToken $tok $_.signal) })[0] }
        $k = if ($keyIn) { $keyIn } elseif ($pat) { $pat.key } else { '' }
        if (-not $k) {   # same wording as an earlier lesson of this repository groups with it
            $bestScore = 0.0
            foreach ($l in $all) {
                $lt = @(Get-Tokens (@($l.occurrences | ForEach-Object { $_.comment }) -join ' '))
                $both = @($tok | Where-Object { $lt -contains $_ }).Count; $union = @(@($tok) + $lt | Sort-Object -Unique).Count
                if ($union -and ($both / $union) -gt $bestScore) { $bestScore = $both / $union; if ($bestScore -ge 0.3) { $k = $l.key } }
            }
        }
        if (-not $k) {
            $out.status = 'NEEDS_KEY'; $out.known = @($cat | ForEach-Object { "$($_.key): $($_.title)" }) + @($all | ForEach-Object { "$($_.key): $($_.title)" })
            $out.next = 'No known pattern or earlier lesson matches. Pass -Key <SHORT_UPPER_CASE_NAME> for a new pattern (with -Title, and -Type reuse-before-new|regex -Query <pattern> when a check can catch it), or the key of the matching lesson.'
            [pscustomobject]$out | ConvertTo-Json -Depth 4; exit 0
        }
        $lchk = if ($Type) { [pscustomobject][ordered]@{ kind = $Type; typePattern = $(if ($Type -eq 'reuse-before-new') { $Query } else { '' }); regex = $(if ($Type -eq 'regex') { $Query } else { '' }); pathGlob = $(if ($Path) { $Path } else { '*' }) } } elseif ($pat) { $pat.check } else { $null }
        if ($lchk -and ($why = Test-LessonCheck $lchk)) { throw "The check cannot be used: $why." }
        $comment = Protect-Text $Text; if ($comment.Length -gt 1000) { $comment = $comment.Substring(0, 1000) }
        $occ = [pscustomobject][ordered]@{ at = (Get-Date).ToString('s'); pbi = $Id; reference = (Protect-Text $Reference); comment = $comment; classification = $cls
            cause = (Protect-Text $Cause); correction = (Protect-Text $Correction); evidence = $Evidence; instructionLike = $injected }
        $ex = & $one $k
        if ($ex) {
            if (@($ex.occurrences | Where-Object { $_.comment -eq $comment -and $_.reference -eq $occ.reference }).Count) { $out.status = 'DUPLICATE'; $out.lesson = $ex; $out.next = 'This comment is already recorded for this lesson; nothing changed.'; [pscustomobject]$out | ConvertTo-Json -Depth 6; exit 0 }
            $ex.occurrences = @(@($ex.occurrences) + $occ)
            $promotable = { param($c) $c -in 'REUSABLE_PATTERN', 'PROJECT_SPECIFIC_RULE' }
            $clash = @(if ($cls -ne 'UNVERIFIED_FEEDBACK' -and $ex.classification -ne 'UNVERIFIED_FEEDBACK' -and (& $promotable $cls) -ne (& $promotable $ex.classification)) { "classified $($ex.classification) before and $cls now" }
                if ($lchk -and $ex.check -and (Get-CheckId $lchk) -ne (Get-CheckId $ex.check)) { 'a different check was proposed' })
            if ($clash.Count) { $ex | Add-Member -Force NoteProperty conflict ($clash -join '; ') }
            elseif ($ex.classification -eq 'UNVERIFIED_FEEDBACK' -and $cls -ne 'UNVERIFIED_FEEDBACK') {   # the first verified correction completes the lesson
                foreach ($f in 'classification', 'cause', 'correction', 'evidence') { $ex | Add-Member -Force NoteProperty $f $(if ($f -eq 'classification') { $cls } else { $occ.$f }) }
                if (-not $ex.check -and $lchk) { $ex | Add-Member -Force NoteProperty check $lchk }
                if ($ex.status -eq 'unverified') { $ex.status = $(if (& $promotable $cls) { 'proposed' } else { 'recorded' }) }
            }
            $out.status = $(if ($clash.Count) { 'CONFLICT' } else { 'GROUPED' }); $lesson = $ex
        } else {
            $lesson = [pscustomobject][ordered]@{ key = $k; title = $(if ($Title) { $Title } elseif ($pat) { $pat.title } else { '(no title: pass -Title)' })
                profile = $(if ($pat -and $pat.profile) { "$($pat.profile)" } elseif ($cls -eq 'PROJECT_SPECIFIC_RULE') { "$((Get-RepoProfile $r '').profile)" } else { 'shared' })
                classification = $cls; status = $(if ($cls -eq 'UNVERIFIED_FEEDBACK') { 'unverified' } elseif ($cls -in 'REUSABLE_PATTERN', 'PROJECT_SPECIFIC_RULE') { 'proposed' } else { 'recorded' })
                cause = $occ.cause; correction = $occ.correction; evidence = $Evidence; check = $lchk; createdAt = $occ.at; occurrences = @($occ) }
            $all.Add($lesson); $out.status = 'RECORDED'
        }
        Save-Lessons $ls.file $all
        $out.lesson = $lesson
        $out.next = switch ($out.status) {
            'CONFLICT' { "This feedback conflicts with the lesson ($($lesson.conflict)). Ask the developer which applies; the lesson cannot be approved until it is resolved (reject it, or record the deciding feedback)." }
            default { if ($lesson.status -eq 'proposed') { "Show the developer the lesson ($($lesson.key): $($lesson.title)), its evidence, and its check; approve it only on their word (lesson -Action approve -Key $($lesson.key))." } else { "Recorded as $($lesson.status) ($($lesson.classification)); it is not proposed as a rule." } } }
        [pscustomobject]$out | ConvertTo-Json -Depth 6; exit 0
    }

    if ($Action -in 'approve', 'reject') {
        if (-not $keyIn) { throw "lesson -Action $Action needs -Key <lesson key>." }
        $l = & $one $keyIn; if (-not $l) { throw "No lesson '$keyIn' in $($ls.file)." }
        $out.lesson = $l
        if ($Action -eq 'reject') {
            $l.status = 'rejected'; $l | Add-Member -Force NoteProperty decided ([pscustomobject]@{ by = $env:USERNAME; at = (Get-Date).ToString('s'); reason = (Protect-Text $Text) })
            if ($l.conflict) { $l.PSObject.Properties.Remove('conflict') }
            Save-Lessons $ls.file $all; $out.status = 'REJECTED'; [pscustomobject]$out | ConvertTo-Json -Depth 6; exit 0
        }
        $refuse = if ($l.status -eq 'approved') { 'ALREADY_APPROVED' } elseif ($l.classification -eq 'UNVERIFIED_FEEDBACK') { 'NOT_VERIFIED' }
            elseif ($l.classification -notin 'REUSABLE_PATTERN', 'PROJECT_SPECIFIC_RULE') { 'NOT_PROMOTABLE' } elseif ($l.conflict) { 'CONFLICT' } elseif (Test-LessonCheck $l.check) { 'NO_CHECK' }
            elseif ($twin = @($all | Where-Object { $_.key -ne $l.key -and $_.status -eq 'approved' -and (Get-CheckId $_.check) -eq (Get-CheckId $l.check) })[0]) { 'DUPLICATE_RULE' } else { '' }
        if ($refuse) {
            $out.status = $refuse
            $out.next = switch ($refuse) {
                'ALREADY_APPROVED' { 'Nothing to do: the lesson is already applied.' }
                'NOT_VERIFIED' { 'The feedback has no verified correction (or reads like an instruction). Fix and verify it, then record it again with -Evidence.' }
                'NOT_PROMOTABLE' { "A $($l.classification) is not a reusable rule; it stays recorded." }
                'CONFLICT' { "Resolve the conflict first: $($l.conflict)." }
                'NO_CHECK' { "No usable check ($(Test-LessonCheck $l.check)); record it again with -Type and -Query." }
                default { "Lesson $($twin.key) already applies the same check; keep one." } }
            [pscustomobject]$out | ConvertTo-Json -Depth 6; exit 0
        }
        if ($l.check.kind -eq 'regex') {   # line patterns live in the existing custom review rules file
            $crFile = Join-Path $CustomProfilesDir 'review-rules.json'
            $rulesNow = @(if (Test-Path -LiteralPath $crFile) { try { foreach ($x in (Get-Content -LiteralPath $crFile -Raw -Encoding UTF8 | ConvertFrom-Json)) { $x } } catch { throw "$crFile cannot be read ($($_.Exception.Message)); fix it before approving a rule." } })
            $rid = $l.key.ToLowerInvariant()
            if (-not @($rulesNow | Where-Object { $_.id -eq $rid }).Count) {
                New-Item -ItemType Directory -Force $CustomProfilesDir | Out-Null
                Write-TextAtomic $crFile (ConvertTo-Json -Depth 4 -InputObject @(@($rulesNow) + [pscustomobject][ordered]@{ id = $rid; profile = $(if ($l.profile -eq 'shared') { '' } else { $l.profile }); pathGlob = "$($l.check.pathGlob)"; regex = "$($l.check.regex)"; severity = 'error'; message = "$($l.title)" }))
            }
            $out.reviewRule = $rid
        }
        $l.status = 'approved'; $l | Add-Member -Force NoteProperty decided ([pscustomobject]@{ by = $env:USERNAME; at = (Get-Date).ToString('s'); reason = (Protect-Text $Text) })
        Save-Lessons $ls.file $all
        $out.status = 'APPROVED'; $out.next = 'review and task now apply this lesson to every later change in this repository.'
        [pscustomobject]$out | ConvertTo-Json -Depth 6; exit 0
    }

    if ($Action -eq 'list') {
        $out.status = $(if ($ls.error) { 'LESSONS_UNREAModernLE' } else { 'OK' }); if ($ls.error) { $out.error = $ls.error }
        $out.lessons = @($all | ForEach-Object { [pscustomobject][ordered]@{ key = $_.key; title = $_.title; status = $_.status; classification = $_.classification; profile = $_.profile; occurrences = @($_.occurrences).Count; conflict = "$($_.conflict)" } })
        [pscustomobject]$out | ConvertTo-Json -Depth 4; exit 0
    }

    # report: learning effectiveness from the lessons and the review history; nothing is estimated.
    $evFile = (Get-LessonFile $r.id) -replace '\.json$', '.events.jsonl'
    $events = @(if (Test-Path -LiteralPath $evFile) { foreach ($x in [IO.File]::ReadAllLines($evFile)) { if ($x.Trim()) { try { $x | ConvertFrom-Json } catch { } } } })
    $detected = @($events | ForEach-Object { @($_.findings) } | Sort-Object -Unique)
    $prevented = @(foreach ($b in @($events | Group-Object branch)) {   # caught by review, then gone in the branch's latest review: fixed before the PR
            $last = @($b.Group)[-1]; foreach ($x in @($b.Group | Select-Object -SkipLast 1 | ForEach-Object { @($_.findings) } | Sort-Object -Unique)) { if (@($last.findings) -notcontains $x) { "$($b.Name): $x" } } })
    $approved = @($all | Where-Object { $_.status -eq 'approved' })
    $out.status = $(if (-not $approved.Count -or -not $events.Count) { 'NOT_YET_MEASURABLE' } else { 'MEASURED' })
    $out.report = [ordered]@{
        commentsAnalyzed = @($all | ForEach-Object { @($_.occurrences) }).Count
        verifiedPatterns = @($all | Where-Object { $_.classification -in 'REUSABLE_PATTERN', 'PROJECT_SPECIFIC_RULE' }).Count
        rulesProposed = @($all | Where-Object { $_.status -eq 'proposed' }).Count; rulesApproved = $approved.Count
        rulesRejectedOrBlocked = @($all | Where-Object { $_.status -eq 'rejected' -or $_.conflict }).Count
        existingRulesReused = @($approved | Where-Object { $k2 = $_.key; @($detected | Where-Object { $_ -like "lesson:$k2|*" -or $_ -like "custom:$($k2.ToLowerInvariant())|*" }).Count }).Count
        reviewsRecorded = $events.Count; violationsDetected = $detected.Count; violationsFixedBeforePr = $prevented.Count; fixed = $prevented
        remainingRecurring = @($all | Where-Object { $_.status -ne 'approved' -and @($_.occurrences).Count -ge 2 } | ForEach-Object { "$($_.key) ($(@($_.occurrences).Count) comments, $($_.status))" }) }
    $out.next = $(if ($out.status -eq 'NOT_YET_MEASURABLE') { 'LEARNING EFFECTIVENESS: NOT YET MEASURABLE (no approved lesson, or no review run since one was approved).' } else { 'Counts come from the lessons file and the recorded review runs only.' })
    [pscustomobject]$out | ConvertTo-Json -Depth 5; exit 0
}

function Invoke-OtherCommand {   # inbox, home, registry, state, task, graph
switch ($Command) {
    'inbox' {
        New-Item -ItemType Directory -Force -Path $InboxDir | Out-Null
        $items = foreach ($i in Get-ChildItem -LiteralPath $InboxDir | Sort-Object LastWriteTime -Descending) { Get-InboxItem $i }
        [pscustomobject]@{ inbox = $InboxDir; items = @($items); registeredRepos = @(Get-Registry | ForEach-Object { $_.id }) } | ConvertTo-Json -Depth 3
    }
    'home' {
        [pscustomobject]@{
            version = $Version; inbox = $InboxDir
            home = $AkzoHome; registry = $Registry; registryExists = (Test-Path $Registry); modules = $ModulesDir
            tasks = $TasksDir; maps = Join-Path $AkzoHome 'maps'; graphs = Join-Path $AkzoHome 'graphs'
            sonarIde = @(Get-SonarIdeExtension)
            visualStudio = @(Get-VisualStudioInstance | ForEach-Object { "$($_.name) $($_.version)$(if (-not $_.customAgents) { ' (no user-level custom agents: they need 18.5 or later)' })" })
        } | ConvertTo-Json
    }
    'registry' {
        if (-not (Test-Path $Registry)) { throw "No registry at $Registry. Run the Akzo-Agent installer or copy config\repos.example.json there." }
        Get-Registry | ForEach-Object {
            $exists = Test-Dir $_.path
            [pscustomobject]@{
                id = $_.id; path = $_.path; exists = $exists
                git = [bool]($exists -and (Test-Path (Join-Path $_.path '.git')))
                purpose = $_.purpose; commands = $_.commands; verified = $_.verified.date
            }
        } | ConvertTo-Json -Depth 4
    }
    'state' {
        $r = Resolve-Repo $Repo
        [pscustomobject]@{
            id = $r.id; path = $r.path; registered = $r.registered
            branch = (Invoke-Quiet git -C $r.path rev-parse --abbrev-ref HEAD)
            head = (Invoke-Quiet git -C $r.path rev-parse HEAD)
            changes = @(git -C $r.path status --porcelain=v1)
        } | ConvertTo-Json
    }
    'task' {
        $ids = @(Get-Registry | ForEach-Object { $_.id })
        $info = [ordered]@{ tasksDir = $TasksDir; registeredRepos = $ids }
        $dir = $null
        if ($Path) {
            if ((Split-Path $Path -Leaf) -ne 'refined-pbi.md') { throw "The requirement file must be named refined-pbi.md (got '$Path')." }
            if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "File not found: $Path" }
            $dir = Split-Path (Resolve-Path -LiteralPath $Path).Path
            if (-not $Id) { $Id = Split-Path $dir -Leaf }
            if (-not $Repo -and (Split-Path (Split-Path $dir)) -eq $TasksDir) { $Repo = Split-Path (Split-Path $dir) -Leaf }
        }
        if ($Id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') { throw "Work-item id '$Id' must be a folder name such as PBI-12345 (letters, digits, '.', '_', '-')." }
        $info.id = $Id
        if (-not $dir) {
            $hits = @(Get-ChildItem -LiteralPath $TasksDir -Directory -ErrorAction SilentlyContinue |
                Where-Object { -not $Repo -or $_.Name -eq $Repo } | ForEach-Object { Join-Path $_.FullName $Id } |
                Where-Object { Test-Path -LiteralPath $_ -PathType Container })
            if ($hits.Count -gt 1) { $info.candidates = $hits; return Out-Task 'AMBIGUOUS' $info }
            if ($hits.Count) { $dir = $hits[0]; $Repo = Split-Path (Split-Path $dir) -Leaf }
            else {
                # "Implement PBI <id>": a PBI waiting in the inbox is offered for intake, with the open workspace as the repository.
                $queued = @(Get-ChildItem -LiteralPath $InboxDir -ErrorAction SilentlyContinue | ForEach-Object { Get-InboxItem $_ } |
                    Where-Object { $_.suggestedId -eq $Id -or $_.name -match "(^|[^0-9A-Za-z])$([regex]::Escape($Id))([^0-9A-Za-z]|$)" })
                $info.suggestedRepo = $(if ($Repo) { $Repo } else { Get-WorkspaceRepo })
                if ($queued.Count) { $info.items = $queued; return Out-Task 'IN_INBOX' $info }
                if (-not $Repo) { $info.expected = Join-Path $TasksDir "<repo-id>\$Id\refined-pbi.md"; return Out-Task 'NOT_FOUND' $info }
            }
        }
        if (-not $Repo) { $info.taskDir = $dir; $info.suggestedRepo = Get-WorkspaceRepo; return Out-Task 'NEEDS_REPO' $info }
        if ($Repo -notin $ids) { $info.repo = $Repo; return Out-Task 'UNKNOWN_REPO' $info }
        $r = Resolve-Repo $Repo
        # G8 preflight: no indexing, document extraction, or content output before processing is authorized.
        $auth = Get-Authorization $r
        $info.authorization = [pscustomobject][ordered]@{ status = $auth.status; source = $auth.source; managed = $auth.managed; reference = $auth.reference; classification = $auth.classification; memory = $auth.memory; allowedHosts = $auth.allowedHosts; reason = $auth.reason }
        if (Get-PreflightRefusal $auth) {
            $info.repo = $r.id
            return Out-Task (Get-PreflightRefusal $auth) $info
        }
        if (-not $dir) { $dir = Join-Path $TasksDir "$($r.id)\$Id" }
        $top = Get-GitTop $dir
        if ($top) { throw "Task folder '$dir' is inside the Git repository '$top' and would show in Git Changes. Use $TasksDir\<repo-id>\$Id\ instead." }
        $info.repo = $r.id; $info.repoPath = $r.path; $info.taskDir = $dir
        $pbi = Join-Path $dir 'refined-pbi.md'
        $info.refinedPbi = $pbi

        # Spec location: remembered in task.json once chosen, so resume never needs the original flags.
        $stateFile = Join-Path $dir 'task.json'
        $saved = if (Test-Path -LiteralPath $stateFile) { Get-Content -LiteralPath $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
        if ($saved.specDir) { $artifacts = $saved.specDir }
        else {
            $specsDir = if ($r.cfg.specsDir) { $r.cfg.specsDir -replace '/', '\' } elseif ($RepoMode) { 'specs' } else { '' }
            if ($r.cfg.specsDir) { $info.specsDir = Join-Path $r.path $specsDir }
            if ($r.cfg.specsDir -and -not $Feature) { $Feature = Get-SpecFolderName $Id $(if ($Title) { $Title } else { Get-PbiTitle $pbi }) }   # unique per work item
            if ($Feature -and $Feature -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$') { throw "Feature folder '$Feature' must be a folder name (letters, digits, '.', '_', '-')." }
            $artifacts = if ($specsDir) { Join-Path $r.path (Join-Path $specsDir $(if ($Feature) { $Feature } else { Get-SpecFolderName $Id $(if ($Title) { $Title } else { Get-PbiTitle $pbi }) })) } else { $dir }
            if ($specsDir) {   # one folder, one work item: never inherit another PBI's spec, plan, or approvals
                $owner = Find-SpecOwner $artifacts $r.id $Id
                if ($owner) {
                    $info.specFolder = $artifacts; $info.owner = $owner
                    $info.suggestedFeature = Get-SpecFolderName $Id $(if ($Title) { $Title } else { Get-PbiTitle $pbi })
                    return Out-Task 'SPEC_LOCATION_TAKEN' $info
                }
            }
        }
        $evidence = Join-Path $dir 'evidence'
        New-Item -ItemType Directory -Force -Path $dir, $evidence | Out-Null
        $created = @()
        # A PBI whose spec lives on its recorded branch is never restarted from templates on another branch.
        if ($saved.branch -and $artifacts -ne $dir -and (Test-Path -LiteralPath $pbi) -and -not (Test-Path -LiteralPath (Join-Path $artifacts 'spec.md'))) {
            $curBranch = "$(Invoke-Quiet git -C $r.path symbolic-ref --short -q HEAD)"
            if ($curBranch -ne "$($saved.branch)") {
                $info.recordedBranch = "$($saved.branch)"; $info.currentBranch = $curBranch; $info.specFolder = $artifacts
                $info.next = "This PBI's spec and plan are on '$($saved.branch)'. Ask, then switch with branchuse -Name $($saved.branch) -Confirmed, or record another branch decision. Nothing was created."
                return Out-Task 'WRONG_BRANCH' $info
            }
        }
        # Spec and plan inside the repository are created only after the branch decision is recorded (branchcreate /
        # branchuse), so nothing lands on a branch the developer did not choose. Existing tasks resume unchanged.
        if ($artifacts -ne $dir -and (Test-Path -LiteralPath $pbi) -and -not (Test-Path -LiteralPath (Join-Path $artifacts 'spec.md')) -and -not $saved.branchDecision) {
            $ttl = if ($Title) { $Title } elseif ($saved.title) { "$($saved.title)" } else { Get-PbiTitle $pbi }
            Update-TaskJson $dir @{ repo = $r.id; id = $Id; title = $ttl; specDir = $artifacts; agentVersion = $Version }   # remembers the chosen location
            $info.specFolder = $artifacts
            $info.branch = Get-BranchInfo $r $Id $ttl
            $info.next = 'Show repository, branch, HEAD, and uncommitted changes. Reuse an explicit branch decision from this task; otherwise ask one open-ended question for the required branch authorization, including the evidence-backed recommendation. Accept free text. Then run branchcreate or branchuse with -Confirmed, then task again.'
            return Out-Task 'BRANCH_DECISION_NEEDED' $info
        }
        if (Test-Path -LiteralPath $pbi) {   # spec/plan only once there is a requirement to work from
            New-Item -ItemType Directory -Force -Path $artifacts | Out-Null
            foreach ($t in 'spec', 'plan') {
                $dest = Join-Path $artifacts "$t.md"
                if (-not (Test-Path -LiteralPath $dest)) { Copy-Item (Join-Path $ModulesDir "$t\assets\$t.md") $dest; $created += $dest }   # never overwrite work
            }
            $need = @{}   # merge: keys a branch decision or an earlier run already wrote are kept
            foreach ($kv in @(@('repo', $r.id), @('id', $Id), @('title', $Title), @('specDir', $artifacts), @('agentVersion', $Version), @('startHead', "$(Invoke-Quiet git -C $r.path rev-parse HEAD)"), @('startedAt', (Get-Date).ToString('s')))) {
                if ($kv[1] -and (-not $saved -or -not $saved.($kv[0]))) { $need[$kv[0]] = $kv[1] }
            }
            if ($need.Count) { Update-TaskJson $dir $need }
        }
        $base = Join-Path $dir 'refined-pbi.baseline.md'
        if ($Baseline) {
            if (-not (Test-Path -LiteralPath $pbi)) { throw "No $pbi to record as baseline." }
            Copy-Item -LiteralPath $pbi $base -Force
        }
        $pbiState = if (-not (Test-Path -LiteralPath $pbi)) { 'missing' }
            elseif (-not (Test-Path -LiteralPath $base)) { 'new' }
            elseif ((Get-FileHash -LiteralPath $pbi).Hash -eq (Get-FileHash -LiteralPath $base).Hash) { 'unchanged' }
            else { 'changed' }
        if ($pbiState -eq 'missing') { return Out-Task 'NO_REFINED_PBI' $info }
        $plan = Join-Path $artifacts 'plan.md'
        $statusOf = { param($f) $l = (Select-String -LiteralPath $f -Pattern '^Status:' -ErrorAction SilentlyContinue | Select-Object -First 1).Line; if ($l -and $l -notmatch '\|') { ($l -replace '^Status:\s*').Trim() } else { 'not started' } }
        $manifest = Sync-InputManifest $dir
        $info.inputs = @($manifest.entries | ForEach-Object { Join-Path $dir $_.file })
        # Compact index only (no document text). 'read' (relative to taskDir) appears only when it is not the file
        # itself, i.e. the cached text of a converted document; headings are a short preview for choosing sections.
        $info.inputIndex = @($manifest.entries | ForEach-Object {
                $row = [ordered]@{ file = $_.file; role = $_.role; kind = $_.kind; kb = $_.kb; status = $_.status }
                if ($_.read -and $_.read -ne (Join-Path $dir $_.file)) { $row.read = $_.read.Substring($dir.Length + 1) }
                if ($_.headings) { $h = (@($_.headings -split '; ') | Select-Object -First 5) -join '; '; $row.headings = $(if ($h.Length -gt 120) { $h.Substring(0, 120) } else { $h }) }
                [pscustomobject]$row })
        $info.inputIssues = @($manifest.issues)
        $info.inputsChanged = @($manifest.changed)
        $info.inputManifest = $manifest.path
        if ($null -ne $copied) { $info.copied = @($copied) }
        if ($null -ne $attached) { $info.attached = @($attached) }
        $info.title = $(if ($saved.title) { $saved.title } else { $Title })
        $info.taskKind = $(if ($created.Count) { 'new' } else { 'existing' })
        $info.agentVersion = $Version
        $info.mode = $(if ($artifacts -eq $dir) { 'external' } else { 'repo' })
        $info.pbiState = $pbiState; $info.baseline = $base
        $info.spec = Join-Path $artifacts 'spec.md'; $info.plan = $plan
        $info.specStatus = & $statusOf $info.spec
        $info.planStatus = & $statusOf $plan
        $readiness = Get-ImplementationReadiness $plan
        $info.implementationReadiness = [pscustomobject]@{
            status = $readiness.status; approval = $readiness.approval
            checks = (@($readiness.checks | ForEach-Object { "$($_.check): $($_.status)" }) -join '; ')
            blockerCount = @($readiness.blockers).Count
        }
        $gapLine = (Select-String -LiteralPath $info.spec -Pattern '^Gap map:' -ErrorAction SilentlyContinue | Select-Object -First 1).Line
        $info.gapMapStatus = $(if ($gapLine -and $gapLine -notmatch '\|') { ($gapLine -replace '^Gap map:\s*').Trim() } else { 'not started' })
        $wf = Read-Workflow
        $gv = Get-GateView $artifacts $wf
        # Compact: titles only (the statuses are gapMapStatus, specStatus, planStatus); lists only when they have rows.
        $info.gates = (@($gv.gates | ForEach-Object { "$($_.id) $($_.title)" }) -join '; ')
        if ($gv.next) { $info.nextGate = $gv.next }
        $pt = @(Get-PlanTasks $plan $wf); if ($pt.Count) { $info.planTasks = $pt }
        $ap = @(Read-Approvals $dir | Select-Object -Last 5); if ($ap.Count) { $info.approvals = $ap }
        $lsn = @(Get-LessonSummary $r.id); if ($lsn.Count) { $info.lessons = $lsn }   # approved PR lessons the plan must apply
        $info.evidence = $evidence; $info.created = $created
        $info.git = [ordered]@{
            branch = (Invoke-Quiet git -C $r.path rev-parse --abbrev-ref HEAD); head = (Invoke-Quiet git -C $r.path rev-parse HEAD)
            changes = @(git -C $r.path status --porcelain=v1)
        }
        $info.repoGuidance = @(Get-RepoGuidance $r.path)
        $map = Join-Path $AkzoHome "maps\$($r.id).md"
        $info.mapPath = $map
        $info.map = $(if (Test-Path -LiteralPath $map) { Protect-Text (Get-Content -LiteralPath $map -Raw -Encoding UTF8) } else { '' })
        $info.architecture = Sync-Architecture $r -Head "$($info.git.head)"   # HEAD already read above: no extra git call
        $facts = Sync-Facts $r $script:LastBlobs $auth.retentionDays
        Protect-Directory (Join-Path $TasksDir $r.id) | Out-Null
        # Verified memory first (compact rows, ~4 KB); the rest is reachable through 'context'.
        $rows = New-Object Collections.Generic.List[string]; $size = 0
        foreach ($f in @($facts.all | Where-Object { $_.status -eq 'verified' } | Sort-Object { [array]::IndexOf($FactTypes, $_.type) }, id)) {
            $row = "$($f.id) [$($f.type)] $($f.text) ($(@($f.evidence | ForEach-Object { "$($_.path):$($_.line)" }) -join ', '))"
            if ($size + $row.Length -gt 4000) { break }
            $rows.Add($row); $size += $row.Length
        }
        $info.memory = [pscustomobject][ordered]@{
            facts = $facts.path; verified = $facts.verified; stale = $facts.stale; expired = $facts.expired; recovered = $facts.recovered
            staleFacts = $facts.staleFacts; verifiedFacts = @($rows); omitted = $facts.verified - $rows.Count
        }
        $info.pbiFlag = Find-InstructionText ([IO.File]::ReadAllText($pbi))
        $info.graph = $(if (Test-Path -LiteralPath (Join-Path $AkzoHome "graphs\$($r.id)\graph.json")) { 'available' } else { 'none' })
        $info.sonar = Get-SonarSetup $r -Brief
        $stateNow = [pscustomobject]@{ id = $Id; dir = $dir; json = $(try { Get-Content -LiteralPath $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $null }); modified = (Get-Item -LiteralPath $dir).LastWriteTime }
        $info.completed = (Get-TaskSummary $stateNow).completed
        $selfBranch = "$($stateNow.json.branch)"
        $others = @(Get-RepoTasks $r.id | Where-Object { $_.id -ne $Id -and "$($_.json.branch)" -and "$($_.json.branch)" -eq "$($info.git.branch)" } | ForEach-Object { $_.id })
        $info.branchState = [pscustomobject][ordered]@{
            current = "$($info.git.branch)"; head = "$($info.git.head)".Substring(0, [math]::Min(7, "$($info.git.head)".Length)); uncommitted = @($info.git.changes).Count
            recordedForThisPbi = $selfBranch; decision = "$($stateNow.json.branchDecision)"
            relation = $(if (-not $selfBranch) { 'no branch decision recorded for this PBI: run branchinfo and ask' } elseif ($selfBranch -ne "$($info.git.branch)") { "the PBI was recorded on '$selfBranch' but HEAD is on '$($info.git.branch)'" } else { 'matches the recorded branch' })
            sharedWithOtherPbis = $others
        }
        $info.overlap = @(Get-TaskOverlap $r.id $Id $pbi)
        Out-Task 'READY' $info
    }
    'graph' {
        if (-not $Update -and -not $Query) { throw 'graph needs -Update and/or -Query.' }
        $r = Resolve-Repo $Repo
        $out = Join-Path $AkzoHome "graphs\$($r.id)"
        $graph = Join-Path $out 'graph.json'
        $headFile = Join-Path $out 'akzo-head.txt'
        $head = Invoke-Quiet git -C $r.path rev-parse HEAD
        # A missing python leaves $LASTEXITCODE from the git call above, so check the command first.
        $hasPython = [bool](Get-Command python -ErrorAction SilentlyContinue)
        if ($hasPython) { Invoke-Quiet python -c "import graphify" | Out-Null }
        if (-not $hasPython -or $LASTEXITCODE -ne 0) { Write-Output 'GRAPHIFY_UNAVAILABLE: use targeted search instead.'; exit 0 }
        if ($Update) {
            New-Item -ItemType Directory -Force -Path $out | Out-Null
            $env:GRAPHIFY_OUT = $out   # absolute path: graphify writes here instead of <repo>\graphify-out
            python -m graphify update $r.path
            if ($LASTEXITCODE -ne 0) { throw "graphify update failed ($LASTEXITCODE)." }
            Set-Content -Path $headFile -Value $head -Encoding ascii
        }
        if ($Query) {
            if (-not (Test-Path $graph)) { Write-Output "NO_GRAPH: run 'graph -Repo $($r.id) -Update' or use targeted search."; exit 0 }
            $built = if (Test-Path $headFile) { (Get-Content $headFile -Raw).Trim() } else { '' }
            $dirty = @(git -C $r.path status --porcelain=v1 --untracked-files=no).Count
            if ($built -ne $head -or $dirty -gt 0) {
                Write-Output "STALE_GRAPH: built at '$built', HEAD '$head', $dirty modified files. Confirm in source or rebuild."
            }
            python -m graphify query $Query --graph $graph
        }
    }
}
}

# Every command body is a function, compiled only when it runs: Windows PowerShell compiles the whole top-level script
# on each call, so command bodies at top level made every call slower (measured: guard 684 -> 486 ms).
. (Join-Path $PSScriptRoot 'multi-repo.ps1')
if (Get-GitTop $AkzoHome) { throw 'Agent state/cache must be outside Git repositories; choose a separate AKZO_AGENT_HOME.' }
$handler = if ($Command -in 'branchcreate', 'branchuse') { 'Invoke-BranchChangeCommand' } elseif (Test-Path "function:Invoke-${Command}Command") { "Invoke-${Command}Command" } else { 'Invoke-OtherCommand' }
& $handler
