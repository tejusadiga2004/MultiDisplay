$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$release = Join-Path $root 'build\windows\x64\runner\Release'
$output = Join-Path $root 'build\installers\windows'
$versionLines = @(Get-Content (Join-Path $root 'pubspec.yaml') |
    Where-Object { $_ -match '^version:' })
if ($versionLines.Count -ne 1 -or $versionLines[0] -notmatch '^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$') {
    throw 'Installer packaging requires pubspec version: major.minor.patch+build'
}
$version = $Matches[1]
$build = $Matches[2]
$artifactVersion = "$version-build.$build"
$fileVersion = "$version.$build"

foreach ($file in 'display_controller.exe', 'dc_windows.dll', 'display_capture_plugin.dll',
        'flutter_windows.dll', 'data\icudtl.dat', 'data\flutter_assets\AssetManifest.bin') {
    if (-not (Test-Path (Join-Path $release $file) -PathType Leaf)) {
        throw "Missing build output: $file"
    }
}

# Deploy the licensed MSVC redistributable DLLs app-locally, avoiding an
# administrator-only runtime installer in this per-user setup.
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if ($LASTEXITCODE -ne 0 -or -not $vs) { throw 'Visual Studio C++ installation not found' }
$crt = Get-ChildItem (Join-Path $vs 'VC\Redist\MSVC\*\x64\Microsoft.VC*.CRT') -Directory |
    Sort-Object { [version]$_.Parent.Parent.Name } -Descending | Select-Object -First 1
if (-not $crt) { throw 'MSVC x64 redistributable directory not found' }
Copy-Item (Join-Path $crt.FullName '*.dll') $release -Force
foreach ($file in 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') {
    if (-not (Test-Path (Join-Path $release $file))) { throw "Missing runtime: $file" }
}

$compiler = Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'
if (-not (Test-Path $compiler)) { throw 'Install Inno Setup 6 before packaging' }
New-Item $output -ItemType Directory -Force | Out-Null
& $compiler "/DAppVersion=$version+$build" "/DFileVersion=$fileVersion" `
    "/DArtifactVersion=$artifactVersion" "/DReleaseDir=$release" "/DOutputDir=$output" `
    (Join-Path $PSScriptRoot 'multi-display.iss')
if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed: $LASTEXITCODE" }

$setup = Join-Path $output "Multi-Display-$artifactVersion-windows-x64-setup.exe"
if (-not (Test-Path $setup)) { throw "Missing installer: $setup" }
$zip = Join-Path $output "Multi-Display-$artifactVersion-windows-x64-portable.zip"
Compress-Archive -Path "$release\*" -DestinationPath $zip -Force
$checksums = foreach ($file in $setup, $zip) {
    $hash = (Get-FileHash $file -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $(Split-Path $file -Leaf)"
}
$checksums | Set-Content (Join-Path $output "Multi-Display-$artifactVersion-windows-x64-SHA256SUMS.txt") -Encoding ascii
