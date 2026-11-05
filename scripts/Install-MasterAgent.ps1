<#
.SYNOPSIS
  One-click front end for install.ps1: install/upgrade, repair, verify, uninstall, and repository management.
.DESCRIPTION
  Started by Install-MasterAgent.cmd / Uninstall-MasterAgent.cmd. Shows a resizable window (Windows Forms) unless
  -NoGui is given. Every action runs scripts\install.ps1 in a child Windows PowerShell, so its backups, manifest,
  rollback, and target-repository checks apply unchanged.
    Install  = install or upgrade (idempotent), then Verify
    Repair   = install + restore missing/modified files + remove Akzo text from VS Code Copilot memory (backed up), then Verify
    Verify   = install.ps1 -Verify; its CHECK lines fill the "Agent Installation Status" panel
    Uninstall= install.ps1 -Uninstall (asks first in the window)
  Repositories: Add, Edit, Remove, Open in Explorer, Validate, Refresh. Changes are saved to repos.json at once
  (backed up first). Removing a repository removes its registration only; the folder is never touched.
.EXAMPLE
  .\scripts\Install-MasterAgent.ps1                                   # window
  .\scripts\Install-MasterAgent.ps1 -Action Install -Repo C:\src\backend -NoGui
  .\scripts\Install-MasterAgent.ps1 -Action Uninstall                 # confirmation window, then uninstall
.NOTES
  Akzo SDD Agent — Developed and maintained by Arun RG
#>
[CmdletBinding()]
param(
    [ValidateSet('', 'Install', 'Repair', 'Verify', 'Uninstall')]
    [string]$Action = '',
    [string[]]$Repo,
    [switch]$NoGui,
    [switch]$NoVSCodeSettings,
    [string]$HomeRoot = $env:USERPROFILE
)
$ErrorActionPreference = 'Stop'
$Engine = Join-Path $PSScriptRoot 'install.ps1'
$Source = Split-Path -Parent $PSScriptRoot
$Version = (Get-Content (Join-Path $Source 'VERSION') -TotalCount 1).Trim()

# Windows PowerShell 5.1 quotes an argument with spaces but does not escape it: '"' is dropped (pasted quotes; not
# valid in a path) and a trailing '\' is doubled so it cannot escape the closing quote.
function ConvertTo-NativeArg([string]$s) {
    $s = $s -replace '"', ''
    if ($s -match '\s' -and $s -match '(\\+)$') { $s += $Matches[1] }
    $s
}

function Invoke-Engine([string]$what, [string[]]$extra = @()) {
    $a = @('-NoProfile', '-File', $Engine, '-HomeRoot', $HomeRoot)
    switch ($what) {
        'Install' { if (-not $NoVSCodeSettings) { $a += '-ConfigureVSCode' } }
        'Repair' { $a += '-CleanMemory'; if (-not $NoVSCodeSettings) { $a += '-ConfigureVSCode' } }
        'Verify' { $a += '-Verify' }
        'Uninstall' { $a += '-Uninstall' }
    }
    $a += @($extra | ForEach-Object { ConvertTo-NativeArg $_ })
    $ErrorActionPreference = 'Continue'   # Windows PowerShell 5.1: redirected native stderr must not abort
    $out = & powershell.exe @a 2>&1 | ForEach-Object { "$_" }
    [pscustomobject]@{ code = $LASTEXITCODE; text = ($out -join [Environment]::NewLine) }
}

function Get-InstalledVersion {
    $m = Join-Path $HomeRoot '.akzo-agent\install-manifest.json'
    if (Test-Path $m) { try { (Get-Content $m -Raw | ConvertFrom-Json).version } catch { 'unknown' } } else { 'not installed' }
}

if ($NoGui) {
    if (-not $Action) { throw '-NoGui needs -Action Install, Repair, Verify, or Uninstall.' }
    $extra = if ($Action -in 'Install', 'Repair' -and @($Repo | Where-Object { $_ }).Count) { @('-AddRepo', ($Repo -join ';')) } else { @() }
    $r = Invoke-Engine $Action $extra
    Write-Output $r.text
    exit $r.code
}

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()

if ($Action -eq 'Uninstall') {   # Uninstall-MasterAgent.cmd: confirm, run, show the result
    $ok = [Windows.Forms.MessageBox]::Show("Remove the Akzo Master SDD agent (installed version $(Get-InstalledVersion))?`n`nKept: your repos.json, tasks, inbox, specs, and backups in $HomeRoot\.akzo-agent.", 'Uninstall Akzo Master SDD Agent', 'YesNo', 'Question')
    if ($ok -ne 'Yes') { exit 0 }
    $r = Invoke-Engine 'Uninstall'
    [void][Windows.Forms.MessageBox]::Show(($r.text -split "`r?`n" | Select-Object -Last 15) -join "`n", $(if ($r.code -eq 0) { 'Uninstalled' } else { 'Uninstall reported a problem' }), 'OK', $(if ($r.code -eq 0) { 'Information' } else { 'Warning' }))
    exit $r.code
}

$StatusColor = @{ 'Valid' = 'DarkGreen'; 'Verified' = 'DarkGreen'; 'Warning' = 'DarkOrange'; 'Invalid' = 'Red'; 'Failed' = 'Red'; 'Not Applicable' = 'Gray'; 'Not Checked' = 'Gray' }
function New-Control([string]$type, [hashtable]$p) { New-Object "Windows.Forms.$type" -Property $p }
function New-List([int]$top, [int]$height, [object[]]$columns) {
    $l = New-Control ListView @{ Left = 12; Top = $top; Width = 790; Height = $height; View = 'Details'; FullRowSelect = $true; HideSelection = $false; MultiSelect = $false; GridLines = $true; ShowItemToolTips = $true; Anchor = 'Top, Left, Right' }
    foreach ($c in $columns) { [void]$l.Columns.Add($c[0], $c[1]) }
    $l
}
function Write-Log([string]$text, [switch]$Append) {
    if ($Append) { $log.AppendText([Environment]::NewLine + $text) } else { $log.Text = $text }
    $log.SelectionStart = $log.Text.Length; $log.ScrollToCaret()
}

$form = New-Control Form @{ Text = "Akzo Master SDD Agent $Version - Setup"; Width = 980; Height = 780; MinimumSize = New-Object Drawing.Size(820, 640); StartPosition = 'CenterScreen' }
$info = New-Control Label @{ Left = 12; Top = 10; Width = 940; Height = 36; Anchor = 'Top, Left, Right'; Font = New-Object Drawing.Font('Segoe UI', 9) }
$repoLabel = New-Control Label @{ Left = 12; Top = 52; Width = 400; Text = 'Repositories the agent works in (double-click or Enter to edit, Delete to remove):' }
$repoList = New-List 72 180 @(@('Repository Name', 170), @('Path', 330), @('Validation', 80), @('Agent Status', 300))
$repoButtons = @{}
$y = 72
foreach ($b in 'Add Repository...', 'Edit...', 'Remove', 'Open in Explorer', 'Validate', 'Refresh') {
    $repoButtons[$b] = New-Control Button @{ Text = $b; Left = 814; Top = $y; Width = 138; Height = 27; Anchor = 'Top, Right' }; $y += 31
}
$vscode = New-Control CheckBox @{ Left = 12; Top = 262; Width = 700; Checked = -not $NoVSCodeSettings; Text = 'Configure VS Code for fewer prompts (helper auto-approve, read access, 400 agent steps)' }
$buttons = foreach ($b in 'Install / Upgrade', 'Repair', 'Verify Installation', 'Uninstall', 'Close') { New-Control Button @{ Text = $b; Width = 140; Height = 32; Top = 290 } }
for ($i = 0; $i -lt $buttons.Count; $i++) { $buttons[$i].Left = 12 + $i * 150 }
$statusLabel = New-Control Label @{ Left = 12; Top = 332; Width = 700; Text = 'Agent Installation Status (configuration on disk; the IDE agent picker itself cannot be read from here):'; Font = New-Object Drawing.Font('Segoe UI', 9, [Drawing.FontStyle]::Bold) }
$statusList = New-List 354 200 @(@('Check', 230), @('Status', 100), @('Detail', 600))
$statusList.Width = 940
$log = New-Control TextBox @{ Left = 12; Top = 562; Width = 940; Height = 165; Multiline = $true; ScrollBars = 'Both'; WordWrap = $false; ReadOnly = $true; Anchor = 'Top, Bottom, Left, Right'; Font = New-Object Drawing.Font('Consolas', 8.5) }
$form.Controls.AddRange(@($info, $repoLabel, $repoList) + @($repoButtons.Values) + @($vscode) + $buttons + @($statusLabel, $statusList, $log))

function Get-Selected { if ($repoList.SelectedItems.Count) { $repoList.SelectedItems[0].Tag } }
function Update-RepoButtons {
    $sel = [bool](Get-Selected)
    foreach ($b in 'Edit...', 'Remove', 'Open in Explorer') { $repoButtons[$b].Enabled = $sel }
}

function Show-Repositories([string]$selectId) {
    $r = Invoke-Engine 'Registry' @('-ListRepos')
    $repoList.BeginUpdate(); $repoList.Items.Clear()
    $json = $r.text.Substring([Math]::Max(0, $r.text.IndexOf('[')))
    $rows = if ($r.code -eq 0) { try { @($json | ConvertFrom-Json | ForEach-Object { $_ }) } catch { @() } } else { @() }   # ForEach-Object: 5.1 emits a JSON array as one object
    if ($r.code -ne 0) { Write-Log $r.text }
    foreach ($row in $rows) {
        $it = New-Object Windows.Forms.ListViewItem($row.name)
        foreach ($s in $row.path, $row.validation, $row.agentStatus) { [void]$it.SubItems.Add("$s") }
        $it.Tag = $row; $it.ToolTipText = "$($row.path)`n$($row.validation): $($row.message)"; $it.UseItemStyleForSubItems = $false
        $it.SubItems[2].ForeColor = [Drawing.Color]::FromName($StatusColor["$($row.validation)"])
        [void]$repoList.Items.Add($it)
        if ($row.id -eq $selectId) { $it.Selected = $true; $it.Focused = $true }
    }
    $repoList.EndUpdate()
    $info.Text = "This folder: v$Version.  Installed: $(Get-InstalledVersion).  Repositories: $($rows.Count).`nAfter installing: restart VS Code (or Visual Studio 2026 18.5+), pick 'akzo-master-sdd-v$Version' in the Copilot Chat agent picker, and type 'start'."
    Update-RepoButtons
    $rows
}

function Show-Checks([string]$text) {
    $statusList.BeginUpdate(); $statusList.Items.Clear()
    foreach ($m in [regex]::Matches($text, '(?m)^CHECK \[([^\]]+)\] ([^:]+): (.*)$')) {
        $it = New-Object Windows.Forms.ListViewItem($m.Groups[2].Value)
        [void]$it.SubItems.Add($m.Groups[1].Value); [void]$it.SubItems.Add($m.Groups[3].Value.Trim())
        $it.ToolTipText = $m.Groups[3].Value.Trim(); $it.UseItemStyleForSubItems = $false
        $it.SubItems[1].ForeColor = [Drawing.Color]::FromName($StatusColor[$m.Groups[1].Value])
        [void]$statusList.Items.Add($it)
    }
    if (-not $statusList.Items.Count) { $it = New-Object Windows.Forms.ListViewItem('Installation'); [void]$it.SubItems.Add('Not Checked'); [void]$it.SubItems.Add('Click "Verify Installation".'); [void]$statusList.Items.Add($it) }
    $statusList.EndUpdate()
}

function Invoke-SetupAction([string]$what) {
    $script:NoVSCodeSettings = -not $vscode.Checked
    $form.Cursor = 'WaitCursor'; Write-Log "Running $what ..."; $form.Refresh()
    try {
        $r = Invoke-Engine $what
        Write-Log ($r.text + [Environment]::NewLine + $(if ($r.code -eq 0) { "== $what finished OK ==" } else { "== $what reported problems (exit $($r.code)) ==" }))
        if ($what -in 'Install', 'Repair' -and $r.code -eq 0) {   # report what is still unresolved after the change
            $v = Invoke-Engine 'Verify'
            $open = @([regex]::Matches($v.text, '(?m)^CHECK \[(Failed|Warning)\] .*$') | ForEach-Object { $_.Value })
            Write-Log -Append $(if ($open.Count) { "Still to resolve after $($what):`n" + ($open -join "`n") } else { "Verify after $($what): no failed or warning checks." })
            Show-Checks $v.text
        } elseif ($what -eq 'Verify') { Show-Checks $r.text }
    } finally { $form.Cursor = 'Default' }
    [void](Show-Repositories (Get-Selected).id)
    $r.code
}

# Add or edit one repository. The registry changes only when Save succeeds.
function Show-RepoDialog($row) {
    $d = New-Control Form @{ Text = $(if ($row) { "Edit repository '$($row.name)'" } else { 'Add repository' }); Width = 660; Height = 260; FormBorderStyle = 'FixedDialog'; StartPosition = 'CenterParent'; MinimizeBox = $false; MaximizeBox = $false }
    $tn = New-Control TextBox @{ Left = 140; Top = 14; Width = 490; Text = "$($row.name)" }
    $tp = New-Control TextBox @{ Left = 140; Top = 46; Width = 490; Text = "$($row.path)" }
    $hint = New-Control Label @{ Left = 140; Top = 72; Width = 490; Height = 30; ForeColor = [Drawing.Color]::DimGray; Text = 'Type or paste (Ctrl+V) a full path, e.g. C:\src\backend or \\server\share\backend. Quotes are removed; spaces are fine.' }
    $vl = New-Control Label @{ Left = 12; Top = 106; Width = 620; Height = 52 }
    $bBrowse = New-Control Button @{ Text = 'Browse...'; Left = 140; Top = 170; Width = 90; Height = 28 }
    $bValidate = New-Control Button @{ Text = 'Validate'; Left = 238; Top = 170; Width = 90; Height = 28 }
    $bSave = New-Control Button @{ Text = 'Save'; Left = 440; Top = 170; Width = 90; Height = 28 }
    $bCancel = New-Control Button @{ Text = 'Cancel'; Left = 540; Top = 170; Width = 90; Height = 28; DialogResult = 'Cancel' }
    $d.Controls.AddRange(@((New-Control Label @{ Left = 12; Top = 17; Width = 125; Text = 'Repository name:' }), $tn, (New-Control Label @{ Left = 12; Top = 49; Width = 125; Text = 'Repository path:' }), $tp, $hint, $vl, $bBrowse, $bValidate, $bSave, $bCancel))
    $d.AcceptButton = $bSave; $d.CancelButton = $bCancel
    $st = @{ named = [bool]$row; validation = $null }   # a name the user typed is never replaced by the suggestion
    $tn.Add_TextChanged({ if ($tn.Focused) { $st.named = [bool]$tn.Text.Trim() } })
    $tp.Add_TextChanged({
            $st.validation = $null; $vl.Text = ''
            $p = $tp.Text.Trim().Trim('"', "'").TrimEnd('\', '/')
            if (-not $st.named) { $tn.Text = if ($p) { ($p -split '[\\/]')[-1] } else { '' } }
        })
    $validate = {
        $extra = @('-ValidateRepo', $tp.Text) + $(if ($row) { @('-EditRepo', $row.id) } else { @() })
        $r = Invoke-Engine 'Registry' $extra
        $v = try { $r.text.Substring($r.text.IndexOf('{')) | ConvertFrom-Json } catch { $null }
        if (-not $v) { $vl.ForeColor = [Drawing.Color]::Red; $vl.Text = "Validation did not run: $($r.text)"; return $null }
        $vl.ForeColor = [Drawing.Color]::FromName($StatusColor[$v.status]); $vl.Text = "$($v.status): $($v.message)$(if ($v.path -and $v.path -ne $tp.Text.Trim()) { "`nWill be saved as: $($v.path)" })"
        $st.validation = $v
        $v
    }
    $bValidate.Add_Click({ [void](& $validate) })
    $bBrowse.Add_Click({
            try {
                if (-not ('Sdd.Windows.NativeFolderPicker' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'NativeFolderPicker.cs') }
                $cur = $tp.Text.Trim().Trim('"', "'")
                if (-not $cur -or -not (Test-Path -LiteralPath $cur -PathType Container)) { $cur = $null }
                $selected = [Sdd.Windows.NativeFolderPicker]::Select($d.Handle, $cur)
                if ($selected) { $tp.Text = $selected; [void](& $validate) }
            } catch {
                $vl.ForeColor = [Drawing.Color]::Red
                $vl.Text = "Folder selection failed: $($_.Exception.Message). Paste the repository path instead."
            }
        })
    $bSave.Add_Click({
            $v = & $validate
            if (-not $v -or $v.status -eq 'Invalid') { return }
            if (-not $tn.Text.Trim()) { $vl.ForeColor = [Drawing.Color]::Red; $vl.Text = 'Enter a repository name.'; return }
            if ($v.status -eq 'Warning' -and [Windows.Forms.MessageBox]::Show("$($v.message)`n`nSave anyway?", 'Repository', 'YesNo', 'Warning') -ne 'Yes') { return }
            $extra = if ($row) { @('-EditRepo', $row.id, '-RepoPath', $v.path, '-RepoName', $tn.Text.Trim()) } else { @('-AddRepo', $v.path, '-RepoName', $tn.Text.Trim(), '-RegistryOnly') }
            $r = Invoke-Engine 'Registry' $extra
            Write-Log $r.text
            if ($r.code -eq 0) { $d.DialogResult = 'OK'; $d.Close() } else { $vl.ForeColor = [Drawing.Color]::Red; $vl.Text = ($r.text -split "`r?`n" | Where-Object { $_ -match 'NOT SAVED|skip|error' }) -join "`n" }
        })
    $d.ShowDialog($form)
}

function Edit-Selected { $row = Get-Selected; if ($row -and (Show-RepoDialog $row) -eq 'OK') { [void](Show-Repositories $row.id) } }
function Remove-Selected {
    $row = Get-Selected; if (-not $row) { return }
    $msg = "Remove the repository registration?`n`nName: $($row.name)`nPath: $($row.path)`n`nOnly the agent's registration (and the authorization recorded for it) is removed. The folder, its Git repository, and your files are NOT deleted. Task files and the architecture map in $HomeRoot\.akzo-agent are kept."
    if ([Windows.Forms.MessageBox]::Show($msg, 'Remove repository', 'YesNo', 'Question') -ne 'Yes') { return }
    $r = Invoke-Engine 'Registry' @('-RemoveRepo', $row.id)
    Write-Log $r.text
    [void](Show-Repositories '')
}

$repoButtons['Add Repository...'].Add_Click({ if ((Show-RepoDialog $null) -eq 'OK') { [void](Show-Repositories '') } })
$repoButtons['Edit...'].Add_Click({ Edit-Selected })
$repoButtons['Remove'].Add_Click({ Remove-Selected })
$repoButtons['Open in Explorer'].Add_Click({
        $row = Get-Selected
        if ($row -and (Test-Path -LiteralPath $row.path -PathType Container)) { Start-Process explorer.exe -ArgumentList "`"$($row.path)`"" }
        elseif ($row) { [void][Windows.Forms.MessageBox]::Show("Folder not found: $($row.path)", 'Open in Explorer', 'OK', 'Warning') }
    })
$repoButtons['Validate'].Add_Click({
        $rows = Show-Repositories (Get-Selected).id
        Write-Log $(if ($rows.Count) { ($rows | ForEach-Object { "{0,-8} {1}  {2}  - {3}" -f $_.validation, $_.name, $_.path, $_.message }) -join [Environment]::NewLine } else { 'No repository registered yet: click "Add Repository...".' })
    })
$repoButtons['Refresh'].Add_Click({ [void](Show-Repositories (Get-Selected).id) })
$repoList.Add_ItemSelectionChanged({ Update-RepoButtons })
$repoList.Add_DoubleClick({ Edit-Selected })
$repoList.Add_KeyDown({
        param($s, $e)
        switch ($e.KeyCode) { 'Enter' { Edit-Selected; $e.Handled = $true } 'Delete' { Remove-Selected; $e.Handled = $true } 'F5' { [void](Show-Repositories (Get-Selected).id) } }
    })
$buttons[0].Add_Click({
        $code = Invoke-SetupAction 'Install'
        if ($code -eq 0 -and -not $repoList.Items.Count) { Write-Log -Append 'No repository registered yet: click "Add Repository..." to add your local clone.' }
    })
$buttons[1].Add_Click({ [void](Invoke-SetupAction 'Repair') })
$buttons[2].Add_Click({ [void](Invoke-SetupAction 'Verify') })
$buttons[3].Add_Click({
        if ([Windows.Forms.MessageBox]::Show('Remove the agent? Your repos.json, tasks, inbox, specs, and backups are kept.', 'Uninstall', 'YesNo', 'Question') -eq 'Yes') { [void](Invoke-SetupAction 'Uninstall') }
    })
$buttons[4].Add_Click({ $form.Close() })
[void](Show-Repositories '')
Show-Checks ''
if ($Action) { $form.Add_Shown({ [void](Invoke-SetupAction $Action) }) }
[void]$form.ShowDialog()
