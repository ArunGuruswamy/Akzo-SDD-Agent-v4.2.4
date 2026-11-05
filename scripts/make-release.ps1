<#
.SYNOPSIS
  Builds Akzo-SDD-Agent-v<version>.zip with release-manifest.json (SHA-256 of every file) inside, and
  Akzo-SDD-Agent-v<version>.zip.sha256 beside it.
.DESCRIPTION
  install.ps1 checks release-manifest.json before installing and refuses a package whose files differ, are missing, or
  are not listed. Publish the .sha256 value through a trusted channel so recipients can check the zip itself
  (Get-FileHash <zip> -Algorithm SHA256). Hashes show that the package is unchanged; they do not show who produced or
  approved it. Where the organization requires it, sign the scripts with its code-signing certificate first
  (Set-AuthenticodeSignature) and keep the signed files in the package. Entries use forward slashes, so the zip
  extracts correctly on every platform.
.EXAMPLE
  .\scripts\make-release.ps1                    # writes ..\Akzo-SDD-Agent-v<version>.zip next to the package folder
  .\scripts\make-release.ps1 -OutDir C:\releases
.NOTES
  Akzo SDD Agent — Developed and maintained by Arun RG
#>
param([string]$OutDir)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$Source = Split-Path -Parent $PSScriptRoot
if (-not $OutDir) { $OutDir = Split-Path -Parent $Source }
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$version = (Get-Content (Join-Path $Source 'VERSION') -TotalCount 1).Trim()
$zip = Join-Path $OutDir "Akzo-SDD-Agent-v$version.zip"
if (Test-Path $zip) { throw "$zip already exists; remove it or choose -OutDir (a release is never overwritten silently)." }
# The architecture analyzer's binaries must be the build of this source (scripts\build-analyzer.ps1 records its hash).
$anSrc = Join-Path $Source 'src\ArchitectureAnalyzer'
if (Test-Path $anSrc) {
    $lines = Get-ChildItem $anSrc -Recurse -File -Include *.cs, *.csproj | Where-Object { $_.FullName -notmatch '\\(bin|obj)\\' } | Sort-Object FullName |
        ForEach-Object { "$($_.FullName.Substring($anSrc.Length + 1))=$([IO.File]::ReadAllText($_.FullName).Replace("`r`n", "`n"))" }
    $want = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes(($lines -join "`n")))).Replace('-', '')
    $stamp = Join-Path $Source 'copilot\modules\analyzers\architecture\source.sha256'
    if (-not (Test-Path $stamp) -or (Get-Content $stamp -TotalCount 1).Trim() -ne $want) { throw "The architecture analyzer in copilot\modules\analyzers\architecture is not the build of src\ArchitectureAnalyzer: run scripts\build-analyzer.ps1 first." }
}
$files = @(Get-ChildItem $Source -Recurse -File -Force | Where-Object {
    $relative = $_.FullName.Substring($Source.Length + 1)
    $relative -match '^(copilot|config|scripts|src|examples|benchmark)\\|^[^\\]+\.(md|cmd|html)$|^VERSION$' -and
    $_.Name -notin @('release-manifest.json', 'corporate-security-report.html', 'evaluation-report.html') -and
    $relative -notmatch '^src\\[^\\]+\\(bin|obj)\\'
} | Sort-Object FullName)
# User-local configuration and reference repositories must never become release defaults.
$defaults = Get-Content (Join-Path $Source 'config\repos.example.json') -Raw | ConvertFrom-Json
if (@($defaults.repos).Count -or $defaults.tasksDir) { throw 'Release registry must be empty and portable.' }
$profiles = Get-Content (Join-Path $Source 'copilot\modules\profiles\profiles.json') -Raw | ConvertFrom-Json
if (@($profiles.profiles).Count) { throw 'Release profiles must contain only portable shared policies, not application defaults.' }
foreach ($file in $files | Where-Object { $_.Extension -in '.md', '.ps1', '.cjs', '.json', '.html', '.config', '.xml', '.txt', '.csv', '.cmd', '.cs', '.csproj', '.props', '.targets', '.ts', '.tsx', '.js', '.yaml', '.yml' }) {
    if ([IO.File]::ReadAllText($file.FullName) -match '(?i)[A-Z]:[\\/]+Users[\\/]+[A-Za-z0-9_.-]+') {
        throw "Developer-specific user path in package file: $($file.FullName.Substring($Source.Length + 1))"
    }
}
$entries = @($files | ForEach-Object { [pscustomobject][ordered]@{ path = $_.FullName.Substring($Source.Length + 1) -replace '\\', '/'; sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash; bytes = $_.Length } })
$manifest = [pscustomobject][ordered]@{
    product = 'Akzo SDD Agent'; maintainer = 'Arun RG'; version = $version; built = (Get-Date).ToString('s'); builtBy = 'local release build'
    signature = (@($files | Where-Object { $_.Extension -eq '.ps1' } | ForEach-Object { "$($_.Name): $((Get-AuthenticodeSignature -LiteralPath $_.FullName).Status)" }) -join '; ')
    files = $entries
}
$z = [IO.Compression.ZipFile]::Open($zip, 'Create')
try {
    foreach ($f in $files) { [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($z, $f.FullName, ($f.FullName.Substring($Source.Length + 1) -replace '\\', '/'), 'Optimal') }
    $e = $z.CreateEntry('release-manifest.json', 'Optimal'); $w = New-Object IO.StreamWriter($e.Open(), (New-Object Text.UTF8Encoding($false)))
    try { $w.Write(($manifest | ConvertTo-Json -Depth 4)) } finally { $w.Dispose() }
} finally { $z.Dispose() }
$hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
[IO.File]::WriteAllText("$zip.sha256", "$hash  $(Split-Path $zip -Leaf)`n")
Write-Output "release ${version}: $zip ($($entries.Count) files + release-manifest.json)"
Write-Output "SHA-256 $hash (also in $zip.sha256)"
