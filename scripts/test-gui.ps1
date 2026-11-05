<#
.SYNOPSIS
  GUI self-test: drives the real windows through Windows UI Automation in an isolated temporary profile.
  1. Start-Development.cmd -> the file dialog opens, a .docx is chosen, the PBI lands in the inbox, the result box is closed.
  2. Install-MasterAgent.cmd -> the setup window opens, "Verify Installation" is clicked, VERIFY OK appears in its log.
  3. Uninstall-MasterAgent.cmd -> the confirmation is answered "Yes", the agent is removed.
  Needs an interactive desktop session. Exit code 0 = all assertions passed. Never touches the real profile.
.NOTES
  Akzo SDD Agent — Developed and maintained by Arun RG
#>
param([switch]$KeepTemp)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, UIAutomationClientSideProviders, System.IO.Compression, System.IO.Compression.FileSystem   # client-side providers expose classic Win32 controls
$Source = Split-Path -Parent $PSScriptRoot
$script:fail = 0; $script:pass = 0
function Check([bool]$ok, [string]$what) { if ($ok) { $script:pass++; Write-Output "PASS  $what" } else { $script:fail++; Write-Output "FAIL  $what" } }
$UIA = [Windows.Automation.AutomationElement]
Add-Type -Namespace '' -Name AkzoWin -MemberDefinition @'
[DllImport("user32.dll")] public static extern IntPtr GetDlgItem(IntPtr hDlg, int id);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string cls, string title);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr w, string l);
[DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, int msg, IntPtr w, IntPtr l);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int max);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr w, System.Text.StringBuilder l);
public delegate bool EnumWindowCallback(IntPtr h, IntPtr data);
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowCallback callback, IntPtr data);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, System.Text.StringBuilder text, int max);
'@
function Find-Window([string]$titleLike, [int]$seconds = 20) {
    $deadline = (Get-Date).AddSeconds($seconds)
    while ((Get-Date) -lt $deadline) {
        $handles = New-Object 'Collections.Generic.List[IntPtr]'
        [void][AkzoWin]::EnumWindows({
            param($handle, $data)
            $text = New-Object Text.StringBuilder 512
            [void][AkzoWin]::GetWindowText($handle, $text, 512)
            if ($text.ToString() -like $titleLike) { $handles.Add($handle) }
            return $true
        }, [IntPtr]::Zero)
        if ($handles.Count) { return $UIA::FromHandle($handles[0]) }
        Start-Sleep -Milliseconds 300
    }
    $null
}
function Find-In($parent, [string]$prop, $value) {
    $cond = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::$prop, $value)
    $parent.FindFirst([Windows.Automation.TreeScope]::Descendants, $cond)
}
# The common Open dialog's file name box (item 1148) is not exposed to UI Automation: set it and press Open (item 1)
# with window messages, which needs no keyboard focus (nothing is typed into other windows).
function Submit-FileDialog($dialog, [string]$fileText) {
    $hDlg = [IntPtr]$dialog.Current.NativeWindowHandle
    $edit = [IntPtr]::Zero
    for ($i = 0; $i -lt 30 -and $edit -eq [IntPtr]::Zero; $i++) {
        $combo = [AkzoWin]::GetDlgItem($hDlg, 1148)
        $inner = [AkzoWin]::FindWindowEx($combo, [IntPtr]::Zero, 'ComboBox', [NullString]::Value)
        $edit = [AkzoWin]::FindWindowEx($(if ($inner -ne [IntPtr]::Zero) { $inner } else { $combo }), [IntPtr]::Zero, 'Edit', [NullString]::Value)
        if ($edit -eq [IntPtr]::Zero) { $edit = [AkzoWin]::GetDlgItem($hDlg, 1152) }
        if ($edit -eq [IntPtr]::Zero) { Start-Sleep -Milliseconds 300 }
    }
    if ($edit -eq [IntPtr]::Zero) { throw 'Native file/folder dialog input was not found.' }
    [void][AkzoWin]::SendMessage($edit, 0x000C, [IntPtr]::Zero, $fileText)                         # WM_SETTEXT
    [void][AkzoWin]::PostMessage([AkzoWin]::GetDlgItem($hDlg, 1), 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero)   # BM_CLICK on Open
}
# Message boxes: press a button by its dialog item id (IDOK 1, IDYES 6), or close a single-OK box with WM_CLOSE.
function Close-MessageBox($box, [int]$buttonId) {
    $h = [IntPtr]$box.Current.NativeWindowHandle
    $b = [AkzoWin]::GetDlgItem($h, $buttonId)
    if ($b -ne [IntPtr]::Zero) { [void][AkzoWin]::PostMessage($b, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero) } else { [void][AkzoWin]::PostMessage($h, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) }
}
# Windows Forms controls by window text / class, so the test does not depend on UI Automation proxies.
function Invoke-ChildButton($top, [string]$text) {
    $b = [AkzoWin]::FindWindowEx([IntPtr]$top.Current.NativeWindowHandle, [IntPtr]::Zero, [NullString]::Value, $text)
    if ($b -eq [IntPtr]::Zero) { throw "Button '$text' not found." }
    [void][AkzoWin]::PostMessage($b, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero)   # BM_CLICK
}
function Get-EditText($top) {
    $h = [IntPtr]::Zero
    while (($h = [AkzoWin]::FindWindowEx([IntPtr]$top.Current.NativeWindowHandle, $h, [NullString]::Value, [NullString]::Value)) -ne [IntPtr]::Zero) {
        $cls = New-Object Text.StringBuilder 256; [void][AkzoWin]::GetClassName($h, $cls, 256)
        if ($cls.ToString() -match 'EDIT') { $sb = New-Object Text.StringBuilder 200000; [void][AkzoWin]::SendMessage($h, 0x000D, [IntPtr]200000, $sb); return $sb.ToString() }   # WM_GETTEXT
    }
    ''
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("akzo-gui-" + [guid]::NewGuid().ToString('N').Substring(0, 6))
$home2 = Join-Path $tmp 'h'
New-Item -ItemType Directory -Force $home2 | Out-Null
$started = @()
try {
    $null = & powershell.exe -NoProfile -File (Join-Path $Source 'scripts\install.ps1') -HomeRoot $home2
    Check ($LASTEXITCODE -eq 0) 'setup: agent installed in a temporary profile'
    $docx = Join-Path $tmp 'PBI 305912 Paint System.docx'
    Set-Content (Join-Path $tmp 'business-rules.md') "# Business rules`nA paint system starts in Draft."
    Set-Content (Join-Path $tmp 'api-contract.yaml') "openapi: 3.0.0`npaths: {}"
    $zip = [IO.Compression.ZipFile]::Open($docx, 'Create')
    try {
        $w = New-Object IO.StreamWriter($zip.CreateEntry('word/document.xml').Open())
        $w.Write('<?xml version="1.0"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>305912 Adaptation imitation request - paint system</w:t></w:r></w:p><w:p><w:r><w:t>AC1: a paint system is created with status Draft and version 1.</w:t></w:r></w:p></w:body></w:document>')
        $w.Dispose()
    } finally { $zip.Dispose() }

    # 0. The agent's own pick (as Copilot runs it): the dialog opens; Cancel reports CANCELLED and creates nothing.
    $inboxDir = Join-Path $home2 '.akzo-agent\inbox'
    $inboxBefore = @(Get-ChildItem $inboxDir -ErrorAction SilentlyContinue).Count
    $pickOut = Join-Path $env:TEMP "akzo-gui-pick-$PID.json"
    $env:AKZO_AGENT_HOME = Join-Path $home2 '.akzo-agent'
    $pp = Start-Process powershell.exe -ArgumentList '-NoProfile', '-STA', '-File', "`"$(Join-Path $home2 '.akzo-agent\modules\investigate\scripts\akzo.ps1')`"", 'pick' -RedirectStandardOutput $pickOut -PassThru -WindowStyle Minimized
    $started += $pp
    $cdlg = Find-Window 'Akzo Master SDD - select*'
    Check ([bool]$cdlg) 'pick (as the agent runs it) opens the PBI file dialog'
    if ($cdlg) { Close-MessageBox $cdlg 2 }   # Cancel
    [void]$pp.WaitForExit(30000)
    $pres = try { Get-Content $pickOut -Raw | ConvertFrom-Json } catch { $null }
    Check ($pres.status -eq 'CANCELLED' -and $pres.next -match 'nothing was created' -and @(Get-ChildItem $inboxDir -ErrorAction SilentlyContinue).Count -eq $inboxBefore) 'cancelling the dialog reports CANCELLED and creates nothing'
    Remove-Item Env:AKZO_AGENT_HOME -ErrorAction SilentlyContinue; Remove-Item $pickOut -ErrorAction SilentlyContinue
    # 1. Start Development: real file dialog.
    $started += Start-Process cmd.exe -ArgumentList "/c `"`"$(Join-Path $Source 'Start-Development.cmd')`" -HomeRoot `"$home2`"`"" -PassThru -WindowStyle Minimized
    $dlg = Find-Window 'Akzo Master SDD - select*'
    Check ([bool]$dlg) 'Start-Development.cmd opens the Windows file dialog'
    if ($dlg) {
        Submit-FileDialog $dlg $docx
        # Second dialog: several supporting documents at once (multi-select: quoted names in the dialog's folder).
        $more = Find-Window 'Akzo Master SDD - optional*'
        Check ([bool]$more) 'a second dialog offers supporting documents (multi-select)'
        if ($more) { Submit-FileDialog $more '"business-rules.md" "api-contract.yaml"' }
        $box = Find-Window 'Start Development'
        $text = if ($box) { (Find-In -parent $box -prop 'AutomationIdProperty' -value '65535').Current.Name } else { '' }
        Check ($text -match 'Ready: PBI 305912 - Adaptation imitation request - paint system' -and $text -match 'type:\s+start') "file chosen in the dialog is queued; result box shows the next step ($($text -split "`n" | Select-Object -First 1))"
        Check ($text -match 'Supporting documents: 2') 'both supporting documents selected together are queued with the PBI'
        if ($box) { Close-MessageBox $box 2 }
        $pbi = Join-Path $home2 '.akzo-agent\inbox\PBI 305912 Paint System\refined-pbi.md'
        Check ((Test-Path $pbi) -and (Get-Content $pbi -Raw) -match '# 305912 Adaptation' -and (Test-Path (Join-Path (Split-Path $pbi) 'source\PBI 305912 Paint System.docx'))) 'selected PBI converted into the inbox workspace; original kept under source\'
        Check ((Test-Path (Join-Path (Split-Path $pbi) 'supporting\business-rules.md')) -and (Test-Path (Join-Path (Split-Path $pbi) 'supporting\api-contract.yaml'))) 'supporting documents copied under supporting\ beside the PBI'
    }

    # 2. Setup window: Verify.
    $started += Start-Process cmd.exe -ArgumentList "/c `"`"$(Join-Path $Source 'Install-MasterAgent.cmd')`" -HomeRoot `"$home2`"`"" -PassThru -WindowStyle Minimized
    $win = Find-Window 'Akzo Master SDD Agent * - Setup'
    Check ([bool]$win) 'Install-MasterAgent.cmd opens the setup window'
    if ($win) {
        Invoke-ChildButton $win 'Verify Installation'
        $deadline = (Get-Date).AddSeconds(60); $log = ''
        while ((Get-Date) -lt $deadline -and $log -notmatch '== Verify') {
            Start-Sleep -Milliseconds 500
            $log = Get-EditText $win
        }
        Check ($log -match 'VERIFY OK' -and $log -match '== Verify finished OK ==') 'setup window: Verify button runs the check and shows VERIFY OK'
        # Add Repository: a path pasted with quotes and spaces is saved at once, with the name suggested from the folder.
        $clone = Join-Path $tmp 'My Clone'; New-Item -ItemType Directory -Force $clone | Out-Null; & git -C $clone init -q
        Invoke-ChildButton $win 'Add Repository...'
        $add = $null   # an owned dialog: UI Automation lists it under the setup window
        for ($i = 0; $i -lt 40 -and -not $add; $i++) { Start-Sleep -Milliseconds 500; $add = Find-In -parent $win -prop 'NameProperty' -value 'Add repository' }
        if ($add) {
            $edits = @(); $h = [IntPtr]::Zero
            while (($h = [AkzoWin]::FindWindowEx([IntPtr]$add.Current.NativeWindowHandle, $h, [NullString]::Value, [NullString]::Value)) -ne [IntPtr]::Zero) {
                $cls = New-Object Text.StringBuilder 256; [void][AkzoWin]::GetClassName($h, $cls, 256); if ($cls.ToString() -match 'EDIT') { $edits += $h }
            }
            Invoke-ChildButton $add 'Browse...'
            $folder = Find-Window 'Select repository folder'
            Check ([bool]$folder) 'setup Browse opens the native Windows Shell folder picker'
            if ($folder) { Close-MessageBox $folder 2 }
            Start-Sleep -Milliseconds 500
            $before = New-Object Text.StringBuilder 4096
            [void][AkzoWin]::SendMessage($edits[1], 0x000D, [IntPtr]4096, $before)
            Check (-not $before.ToString() -and -not @((Get-Content (Join-Path $home2 '.akzo-agent\repos.json') -Raw | ConvertFrom-Json).repos | Where-Object { $_.path -eq $clone }).Count) 'folder cancellation preserves the empty path and registry'
            Invoke-ChildButton $add 'Browse...'
            $folder = Find-Window 'Select repository folder'
            if (-not $folder) { throw 'Native folder picker did not reopen.' }
            Submit-FileDialog $folder $clone
            Start-Sleep -Milliseconds 1000
            $chosen = New-Object Text.StringBuilder 4096
            [void][AkzoWin]::SendMessage($edits[1], 0x000D, [IntPtr]4096, $chosen)
            Check ($chosen.ToString() -eq $clone) 'native Explorer folder selection returns the exact selected repository path'
            [void][AkzoWin]::SendMessage($edits[1], 0x000C, [IntPtr]::Zero, "`"$clone`"")   # WM_SETTEXT on the path box, as pasted
            Invoke-ChildButton $add 'Save'
            $deadline = (Get-Date).AddSeconds(30); $saved = $null
            while ((Get-Date) -lt $deadline -and -not $saved) { Start-Sleep -Milliseconds 500; $saved = try { @((Get-Content (Join-Path $home2 '.akzo-agent\repos.json') -Raw | ConvertFrom-Json).repos | Where-Object { $_.path -eq $clone }) | Select-Object -First 1 } catch { $null } }
            Check ($saved -and $saved.name -eq 'My Clone') 'setup window: Add Repository saves a pasted, quoted path with the suggested name'
        } else { Check $false 'setup window: Add Repository opens its dialog' }
        Invoke-ChildButton $win 'Close'
    }

    # 3. Uninstall with confirmation.
    $started += Start-Process cmd.exe -ArgumentList "/c `"`"$(Join-Path $Source 'Uninstall-MasterAgent.cmd')`" -HomeRoot `"$home2`"`"" -PassThru -WindowStyle Minimized
    $ask = Find-Window 'Uninstall Akzo Master SDD Agent'
    Check ([bool]$ask) 'Uninstall-MasterAgent.cmd asks for confirmation first'
    if ($ask) {
        Close-MessageBox $ask 6
        $done = Find-Window 'Uninstalled' 60
        Check ([bool]$done -and -not (Test-Path (Join-Path $home2 '.copilot\agents\akzo-master-sdd.agent.md')) -and (Test-Path (Join-Path $home2 '.akzo-agent\repos.json'))) 'uninstall removes the agent and keeps repos.json'
        if ($done) { Close-MessageBox $done 2 }
    }
} finally {
    foreach ($p in $started) { if ($p -and -not $p.HasExited) { $p.WaitForExit(10000) | Out-Null } }
    if (-not $KeepTemp) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue } else { Write-Output "Temp kept: $tmp" }
}
Write-Output "`n$($script:pass) passed, $($script:fail) failed."
exit $(if ($script:fail) { 1 } else { 0 })
