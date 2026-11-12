# One-step release: builds the Windows app and compiles the installer.
# Usage (from the project folder):  .\build_release.ps1
# To release a new version, bump `version:` in pubspec.yaml first.

$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot

# Version comes from pubspec.yaml ("1.2.0+3" -> "1.2.0") so it is set in one place.
$line = Select-String -Path 'pubspec.yaml' -Pattern '^version:\s*(\S+)' | Select-Object -First 1
if (-not $line) { throw 'Could not find version: in pubspec.yaml' }
$version = ($line.Matches[0].Groups[1].Value -split '\+')[0]
Write-Host "Building version $version"

$buildArgs = @('build', 'windows', '--release')
if (Test-Path -LiteralPath 'supabase_config.json') {
    $buildArgs += '--dart-define-from-file=supabase_config.json'
    Write-Host 'Including Supabase config for cloud sync'
}
flutter @buildArgs
if ($LASTEXITCODE -ne 0) { throw 'flutter build failed' }

# Locate the Inno Setup compiler.
$candidates = @(
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
)
$iscc = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $iscc) {
    $cmd = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($cmd) { $iscc = $cmd.Source }
}
if (-not $iscc) {
    throw 'Inno Setup 6 not found. Install it from https://jrsoftware.org/isdl.php and re-run.'
}

& $iscc "/DMyAppVersion=$version" 'installer.iss'
if ($LASTEXITCODE -ne 0) { throw 'Inno Setup compile failed' }

Write-Host ''
Write-Host "Done. Send this file to your friend:"
Write-Host "  $PSScriptRoot\installer_output\DnDTracker_Setup_$version.exe"

