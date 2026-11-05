<#
.SYNOPSIS
  Start Development launcher: choose the refined PBI in a file dialog, then any supporting documents, and queue them
  for the Akzo Master SDD agent (<inbox>\<name>\refined-pbi.md, original under source\, supporting documents under
  supporting\; originals are never changed).
.DESCRIPTION
  Uses the installed helper (%USERPROFILE%\.akzo-agent\modules\investigate\scripts\akzo.ps1 pick), the same command
  the agent runs when you type "Start Development" in Copilot Chat. Then select akzo-master-sdd-v<version> and type "start".
.EXAMPLE
  .\scripts\Start-Development.ps1                       # file dialog
  .\scripts\Start-Development.ps1 -Source C:\docs\PBI-305912.docx -NoGui
  .\scripts\Start-Development.ps1 -Source C:\docs\PBI.docx -Supporting 'C:\docs\rules.xlsx;C:\docs\api.yaml' -NoGui
.NOTES
  Akzo SDD Agent — Developed and maintained by Arun RG
#>
[CmdletBinding()]
param([string]$Source, [string]$Supporting, [switch]$NoGui, [string]$HomeRoot = $env:USERPROFILE)
$ErrorActionPreference = 'Stop'
$helper = Join-Path $HomeRoot '.akzo-agent\modules\investigate\scripts\akzo.ps1'
if (-not $NoGui) { Add-Type -AssemblyName System.Windows.Forms }
function Show-Result([string]$text, [string]$title, [string]$icon) {
    if ($NoGui) { Write-Output $text } else { [void][Windows.Forms.MessageBox]::Show($text, $title, 'OK', $icon) }
}
if (-not (Test-Path $helper)) { Show-Result -text 'The Akzo Master SDD agent is not installed. Double-click Install-MasterAgent.cmd first.' -title 'Start Development' -icon 'Warning'; exit 1 }

$env:AKZO_AGENT_HOME = Join-Path $HomeRoot '.akzo-agent'
$versionFile = Join-Path $HomeRoot '.akzo-agent\modules\VERSION'   # the installed agent's name in the picker carries this version
$agentName = if (Test-Path $versionFile) { "akzo-master-sdd-v$((Get-Content $versionFile -TotalCount 1).Trim())" } else { 'akzo-master-sdd' }
$pickArgs = @{}; if ($Source) { $pickArgs.Source = $Source }; if ($Supporting) { $pickArgs.Supporting = $Supporting }
try { $json = (& $helper pick @pickArgs) -join "`n"; $r = $json | ConvertFrom-Json }
catch { Show-Result -text "Could not queue the PBI: $($_.Exception.Message)" -title 'Start Development' -icon 'Error'; exit 1 }
if ($r.status -eq 'CANCELLED') { exit 0 }
$title = if ($r.item.suggestedTitle) { $r.item.suggestedTitle } else { $r.item.name }
$docs = @($r.supporting | Where-Object { $_.status -in 'added', 'renamed' }).Count
$notAdded = @($r.supporting | Where-Object { $_ -and $_.status -notin 'added', 'renamed' } | ForEach-Object { "$($_.name): $($_.status)" })
$id = if ($r.item.suggestedId) { "PBI $($r.item.suggestedId) - " } else { '' }
try { Set-Clipboard -Value 'start' } catch { Write-Verbose 'clipboard unavailable' }   # paste into Copilot Chat
Show-Result -title 'Start Development' -icon 'Information' -text "Ready: $id$title`n`nQueued as $($r.item.pbiFile)`nSupporting documents: $docs$(if ($notAdded) { ' (not added: ' + ($notAdded -join ', ') + ')' })`n`nNext: in Copilot Chat (VS Code or Visual Studio 2026) select '$agentName' and type:  start`n('start' is on the clipboard.)"
if ($NoGui) { Write-Output $json }
