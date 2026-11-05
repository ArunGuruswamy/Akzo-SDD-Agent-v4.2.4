<#
.SYNOPSIS
  IDE integration self-test of sonar -Check issues (get_sonar_issues) against the installed Visual Studio. Starts an
  instance through its automation model with a temporary solution that has real diagnostics (compiler warning CS0219 and
  analyzer warning CA1303, the .NET counterpart of Sonar's S4055), then runs the helper the way the agent does:
  1. -Update opens the file; its Error List rows are read with every severity shown and get rule ids from the logged
     build, one row per finding; the developer's Error List filters and active document stay as they were.
  2. A second -Update does not reopen the open file.
  3. After a fix (the file closed, changed on disk, reopened by -Update) the fixed finding is in resolved and -Text
     validation passes; a finding still there fails; a rule the IDE rows cannot name stays NOT VERIFIED.
  Needs Visual Studio 2022 or 2026 and the .NET SDK, and no other Visual Studio running (the helper reaches the instance
  Windows registered first). Closes the instance it started. Exit code 0 = all assertions passed, 2 = skipped.
.NOTES
  Akzo SDD Agent — Developed and maintained by Arun RG
#>
param([switch]$KeepTemp)
$ErrorActionPreference = 'Stop'
$Source = Split-Path -Parent $PSScriptRoot
$helper = Join-Path $Source 'copilot\modules\investigate\scripts\akzo.ps1'
$script:fail = 0; $script:pass = 0
function Check([bool]$ok, [string]$what, [string]$detail = '') { if ($ok) { $script:pass++; Write-Output "PASS  $what" } else { $script:fail++; Write-Output "FAIL  $what"; if ($detail) { Write-Output "      $detail" } } }
$progId = @('VisualStudio.DTE.18.0', 'VisualStudio.DTE.17.0' | Where-Object { [type]::GetTypeFromProgID($_) })[0]
if (-not $progId) { Write-Output 'SKIP  no Visual Studio 2022 or 2026 automation registered'; exit 2 }
if (Get-Process devenv -ErrorAction SilentlyContinue) { Write-Output 'SKIP  Visual Studio is running: close it first (the helper reaches the instance Windows registered first)'; exit 2 }
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) { Write-Output 'SKIP  no .NET SDK on PATH'; exit 2 }

$tmp = Join-Path ([IO.Path]::GetTempPath()) "akzo-ide-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$keepEnv = $env:AKZO_AGENT_HOME, $env:SONAR_TOKEN, $env:SONAR_HOST_URL, $env:MSBUILDDISABLENODEREUSE, $env:UseSharedCompilation
$env:AKZO_AGENT_HOME = "$tmp\home"; $env:SONAR_TOKEN = ''; $env:SONAR_HOST_URL = ''
$env:MSBUILDDISABLENODEREUSE = '1'; $env:UseSharedCompilation = 'false'   # no build servers left holding the temp folder
$dte = $null
try {
    $repo = "$tmp\repo"; New-Item -ItemType Directory -Force "$repo\App" | Out-Null
    $utf8 = New-Object Text.UTF8Encoding($false)
    $tfm = "net$(([version]((& dotnet --version) -replace '-.*$')).Major).0"
    [IO.File]::WriteAllText("$repo\App\App.csproj", "<Project Sdk=`"Microsoft.NET.Sdk`"><PropertyGroup><OutputType>Exe</OutputType><TargetFramework>$tfm</TargetFramework></PropertyGroup></Project>", $utf8)
    [IO.File]::WriteAllText("$repo\.editorconfig", "root = true`r`n`r`n[*.cs]`r`ndotnet_diagnostic.CA1303.severity = warning`r`n", $utf8)
    $program = "namespace App;`r`n`r`ninternal static class Program`r`n{`r`n    private static void Main()`r`n    {`r`n        int unused = 1;`r`n        System.Console.WriteLine(`"Imported measurements`");`r`n    }`r`n}`r`n"
    [IO.File]::WriteAllText("$repo\App\Program.cs", $program, $utf8)
    [IO.File]::WriteAllText("$repo\App\Other.cs", "namespace App;`r`n`r`ninternal static class Other`r`n{`r`n}`r`n", $utf8)
    [IO.File]::WriteAllText("$repo\.gitignore", "bin/`r`nobj/`r`n.vs/`r`n", $utf8)
    Push-Location $repo
    try { $null = & dotnet new sln -n Poc --format sln 2>&1; $null = & dotnet sln Poc.sln add App\App.csproj 2>&1 } finally { Pop-Location }
    & git -C $repo init -q; & git -C $repo config user.email t@t; & git -C $repo config user.name t; & git -C $repo add -A; & git -C $repo commit -qm init
    $repo = (& git -C $repo rev-parse --show-toplevel) -replace '/', '\'   # the long path form the IDE reports (TEMP can be a short 8.3 path)
    [IO.File]::WriteAllText("$repo\App\Program.cs", $program + "// changed`r`n", $utf8)
    $h = { param([string[]]$a) $ErrorActionPreference = 'Continue'; $o = & powershell -NoProfile -File $helper @a 2>&1; [pscustomobject]@{ code = $LASTEXITCODE; out = ($o -join "`n") } }
    $J = { param($res) try { $res.out | ConvertFrom-Json } catch { [pscustomobject]@{ status = "ERROR($($res.code))"; text = $res.out } } }
    $null = & $h authorize, -Repo, $repo, -Reference, 'TEST-IDE fixture', -Classification, internal
    $build = @((& $J (& $h affected, -Repo, $repo)).stages.A_build)[0]
    Push-Location $repo; try { $null = & cmd /c "$build 2>&1" } finally { Pop-Location }   # stage A as printed: the log the build source reads

    $com = { param([scriptblock]$call) for ($i = 0; ; $i++) { try { return & $call } catch { if ($i -ge 60) { throw }; Start-Sleep -Milliseconds 500 } } }   # a busy IDE rejects calls
    $dte = New-Object -ComObject $progId
    for ($i = 0; $i -lt 60 -and -not "$(& $com { $dte.FullName })"; $i++) { Start-Sleep -Seconds 1 }   # a starting instance answers before it is ready
    & $com { $dte.MainWindow.Visible = $true }
    & $com { $dte.Solution.Open("$repo\Poc.sln") }
    Start-Sleep -Seconds 15   # the projects load in the background
    $null = & $com { $dte.ItemOperations.OpenFile("$repo\App\Other.cs") }   # the developer's active document
    $asm = [Reflection.Assembly]::LoadFrom((Join-Path (Split-Path (& $com { $dte.FullName })) 'PublicAssemblies\Microsoft.VisualStudio.Interop.dll'))
    $elT = $asm.GetType('EnvDTE80.ErrorList', $true)
    $el = & $com { $asm.GetType('EnvDTE80.ToolWindows', $true).GetProperty('ErrorList').GetValue($asm.GetType('EnvDTE80.DTE2', $true).GetProperty('ToolWindows').GetValue($dte, $null), $null) }
    foreach ($f in 'ShowWarnings', 'ShowMessages') { & $com { $elT.GetProperty($f).SetValue($el, $false, $null) } }   # a developer who hides warnings
    $filters = { (@('ShowErrors', 'ShowWarnings', 'ShowMessages') | ForEach-Object { "$_=$(& $com { $elT.GetProperty($_).GetValue($el, $null) })" }) -join ' ' }
    $activeName = { "$(& $com { $dte.ActiveDocument.Name })" }
    $timed = { param([string[]]$a) $t = [Diagnostics.Stopwatch]::StartNew(); $x = & $J (& $h $a); $x | Add-Member -NotePropertyName seconds -NotePropertyValue ([math]::Round($t.Elapsed.TotalSeconds, 1)) -PassThru }

    # 1. Open, analyze, read: rule ids from the build, one row per finding, the developer's view kept.
    $r1 = & $timed sonar, -Repo, $repo, -Check, issues, -File, 'App/Program.cs', -Update
    $f1 = @($r1.files)[0]
    $cs0219 = @($r1.issues | Where-Object { $_.rule -eq 'CS0219' }); $ca1303 = @($r1.issues | Where-Object { $_.rule -eq 'CA1303' })
    Check ($r1.status -eq 'OK' -and $r1.sources.ide.status -eq 'OK' -and $f1.opened -eq $true -and $f1.analysis -eq 'ANALYZED' -and $f1.diagnostics -ge 2) "IDE: -Update opened the file and its rows changed after opening (ANALYZED, $($f1.diagnostics) rows, $($r1.seconds) s)" ($r1 | ConvertTo-Json -Compress -Depth 5)
    Check ($cs0219.Count -eq 1 -and $cs0219[0].source -eq 'ide+build' -and $cs0219[0].line -eq 7 -and $cs0219[0].column -eq 13 -and $ca1303.Count -eq 1 -and $ca1303[0].source -eq 'ide+build' -and $ca1303[0].line -eq 8 -and $ca1303[0].column -eq 34) 'IDE: each live row takes its rule id from the logged build (by text, or by its place when the texts differ); one row per finding' (($r1.issues | ConvertTo-Json -Compress))
    Check ((& $filters) -eq 'ShowErrors=True ShowWarnings=False ShowMessages=False' -and $r1.sources.ide.detail -match 'hid warnings and messages' -and (& $activeName) -eq 'Other.cs') "IDE: warnings and messages were shown for the read and hidden again; the developer's active document is still in front ($(& $activeName))" "$(& $filters) | $($r1.sources.ide.detail)"
    Check ($r1.sources.ide.sonarForIde -match '^(SonarQube|not found in the Visual Studio extension folders)' -and $r1.sources.ide.connectedMode -eq 'NOT VERIFIED') "IDE: the source says whether SonarQube for IDE is installed ($($r1.sources.ide.sonarForIde)) and the Connected Mode status, so an Error List without Sonar findings is not mistaken for clean"

    # 2. An open file is not reopened.
    $r2 = & $timed sonar, -Repo, $repo, -Check, issues, -File, 'App/Program.cs', -Update
    # READ, or ANALYZED when analyzer rows arrived after the first read (a busy IDE): either way only additions, nothing resolved.
    Check (@($r2.files)[0].opened -eq $false -and @($r2.files)[0].analysis -in 'READ', 'ANALYZED' -and -not @(@($r2.files)[0].resolved).Count -and @($r2.files)[0].diagnostics -ge $f1.diagnostics -and $r2.seconds -lt $r1.seconds) "IDE: a second -Update does not reopen the open file and does not wait ($(@($r2.files)[0].analysis), $($r2.seconds) s)" ($r2.files | ConvertTo-Json -Compress -Depth 4)
    $ra = & $J (& $h sonar, -Repo, $repo, -Check, issues, -Scope, active, -Source, ide)
    Check ($ra.scope -eq 'active' -and @($ra.files).Count -eq 1 -and @($ra.files)[0].file -eq 'App/Other.cs' -and $ra.sources.ide.status -eq 'OK') 'IDE: -Scope active reads the developer''s active document' ($ra | ConvertTo-Json -Compress -Depth 4)

    # 3. A fix, reanalyzed after reopening: the fixed finding is resolved; validation passes for it and fails for one still there.
    $doc = & $com { $dte.Documents.Item("$repo\App\Program.cs") }
    $null = & $com { $doc.Close(2) }   # vsSaveChangesNo: unchanged in the editor
    [IO.File]::WriteAllText("$repo\App\Program.cs", ($program -replace '        int unused = 1;\r\n', '') + "// changed`r`n", $utf8)
    $fixed = "The variable 'unused' is assigned but its value is never used"
    $r3 = & $timed sonar, -Repo, $repo, -Check, issues, -File, 'App/Program.cs', -Update, -Text, $fixed
    $f3 = @($r3.files)[0]
    Check ($f3.opened -eq $true -and $f3.analysis -eq 'ANALYZED' -and (@($f3.resolved) -join "`n") -match [regex]::Escape($fixed) -and -not @($r3.issues | Where-Object { $_.message -eq $fixed }).Count -and $f3.validation -eq 'PASSED' -and $f3.build -eq 'NOT VERIFIED') "IDE: after the fix the file is reanalyzed, the finding is in resolved, and validation PASSED; the stale build log is NOT VERIFIED, not reused ($($r3.seconds) s)" ($r3.files | ConvertTo-Json -Compress -Depth 4)
    $still = @($r3.issues | Where-Object { $_.line -eq 7 -and $_.column -eq 34 })[0].message
    $r4 = & $J (& $h sonar, -Repo, $repo, -Check, issues, -File, 'App/Program.cs', -Text, $still)
    $r5 = & $J (& $h sonar, -Repo, $repo, -Check, issues, -File, 'App/Program.cs', -Key, CA1303)
    Check ($still -and @($r4.files)[0].validation -eq 'FAILED' -and @($r4.files)[0].validationDetail -match 'line 7' -and @($r5.files)[0].validation -eq 'NOT VERIFIED' -and @($r5.files)[0].validationDetail -match 'no rule id|no analysis') 'IDE: a finding still reported fails validation; a rule the IDE rows cannot name is NOT VERIFIED, never PASSED' "$(@($r4.files)[0] | ConvertTo-Json -Compress) | $(@($r5.files)[0] | ConvertTo-Json -Compress)"
    # Visual Studio 2022's GitHub Copilot for Azure writes its own rules into the solution folder about 30 s after the solution opens, without the helper.
    $vsOwn = (Test-Path "$repo\.github\copilot-instructions.md") -and ([IO.File]::ReadAllText("$repo\.github\copilot-instructions.md") -match '^- @azure Rule')
    if ($vsOwn) { Write-Output 'NOTE  Visual Studio (GitHub Copilot for Azure) wrote .github/copilot-instructions.md into the solution folder on its own' }
    $other = @(& git -C $repo status --porcelain | Where-Object { $_ -ne ' M App/Program.cs' -and -not ($vsOwn -and $_ -eq '?? .github/') })
    Check ((& $filters) -eq 'ShowErrors=True ShowWarnings=False ShowMessages=False' -and -not $other.Count) 'IDE: the filters are still the developer''s; the helper wrote nothing into the repository' ($other -join '; ')
} finally {
    if ($dte) {
        try { $dte.Quit() } catch { }
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($dte)
        $p = Get-Process devenv -ErrorAction SilentlyContinue   # none ran before this test: any instance now is the one it started
        if ($p -and -not $p.WaitForExit(30000)) { $p | Stop-Process -Force }
    }
    $env:AKZO_AGENT_HOME, $env:SONAR_TOKEN, $env:SONAR_HOST_URL, $env:MSBUILDDISABLENODEREUSE, $env:UseSharedCompilation = $keepEnv
    if (-not $KeepTemp) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue } else { Write-Output "temp kept: $tmp" }
}
Write-Output "IDE tests: $($script:pass) passed, $($script:fail) failed"
exit [int]($script:fail -gt 0)
