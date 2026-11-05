<#
.SYNOPSIS
  Builds the architecture analyzer (src\ArchitectureAnalyzer) into copilot\modules\analyzers\architecture, where
  install.ps1 installs it with the other modules, and records the SHA-256 of its source in source.sha256 there, so
  make-release.ps1 refuses a package whose analyzer was not built from the current source.
.DESCRIPTION
  Needs the .NET SDK 8 or later. The Roslyn packages come from the NuGet cache, or from nuget.org when the cache does not
  have them: at build time only. Installing a package never downloads anything. The output is framework-dependent
  net8.0 at the package root and net472 under net472 (Visual Studio MSBuild 18+).
.PARAMETER NoRestore
  Reuse an existing restore when dependency manifests, SDK and NuGet configuration are unchanged.
  Missing restore assets fail explicitly. Do not use this after changing dependencies.
.NOTES
  Akzo SDD Agent — Developed and maintained by Arun RG
#>
param([switch]$NoRestore)
$ErrorActionPreference = 'Stop'
$Source = Split-Path -Parent $PSScriptRoot
$src = Join-Path $Source 'src\ArchitectureAnalyzer'
$out = Join-Path $Source 'copilot\modules\analyzers\architecture'
# Line endings are normalized, so a checkout with other line endings has the same source hash.
$hash = {
    $lines = Get-ChildItem $src -Recurse -File -Include *.cs, *.csproj | Where-Object { $_.FullName -notmatch '\\(bin|obj)\\' } | Sort-Object FullName |
        ForEach-Object { "$($_.FullName.Substring($src.Length + 1))=$([IO.File]::ReadAllText($_.FullName).Replace("`r`n", "`n"))" }
    [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes(($lines -join "`n")))).Replace('-', '')
}
$tmp = Join-Path $src "obj\publish-$([guid]::NewGuid().ToString('N'))"
try {
    if (-not $NoRestore) {
        & dotnet restore (Join-Path $src 'ArchitectureAnalyzer.csproj') --nologo
        if ($LASTEXITCODE -ne 0) { throw "dotnet restore failed (exit $LASTEXITCODE)." }
    }
    & dotnet publish (Join-Path $src 'ArchitectureAnalyzer.csproj') -c Release -f net8.0 -o $tmp --no-restore --nologo
    if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed (exit $LASTEXITCODE)." }
    & dotnet publish (Join-Path $src 'ArchitectureAnalyzer.csproj') -c Release -f net472 -o (Join-Path $tmp 'net472') --no-restore --nologo
    if ($LASTEXITCODE -ne 0) { throw "net472 publish failed (exit $LASTEXITCODE)." }
    # Replace only files produced by this publish; never recursively remove the package or a parent directory.
    New-Item -ItemType Directory -Force $out | Out-Null
    foreach ($file in Get-ChildItem -LiteralPath $tmp -Recurse -File) {
        $target = Join-Path $out $file.FullName.Substring($tmp.Length + 1)
        New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
        [IO.File]::Copy($file.FullName, $target, $true)
    }
    # These compile-only references may remain from an older package; Locator must resolve the installed toolset.
    foreach ($hostDir in @($out, (Join-Path $out 'net472'))) {
        foreach ($name in 'Microsoft.Build.dll', 'Microsoft.Build.Framework.dll', 'Microsoft.Build.Tasks.Core.dll', 'Microsoft.Build.Utilities.Core.dll') {
            $stale = Join-Path $hostDir $name
            if (Test-Path -LiteralPath $stale -PathType Leaf) { Remove-Item -LiteralPath $stale -Force }
        }
    }
    [IO.File]::WriteAllText((Join-Path $out 'source.sha256'), "$(& $hash)`n")
} finally { if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force } }
Write-Output "architecture analyzer: $out ($(@(Get-ChildItem $out -Recurse -File).Count) files, source $((Get-Content (Join-Path $out 'source.sha256') -TotalCount 1).Substring(0, 12)))"
