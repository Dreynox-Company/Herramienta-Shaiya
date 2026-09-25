param(
    [string]$ReleasePath = "",
    [string]$ManifestRoot = "",
    [string]$InstallRoot = "",
    [string]$EvidencePath = ""
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path "$PSScriptRoot/..").Path
if ([string]::IsNullOrWhiteSpace($ReleasePath)) {
    $ReleasePath = Join-Path $root 'build/windows/x64/runner/Release'
}
if ([string]::IsNullOrWhiteSpace($ManifestRoot)) {
    $ManifestRoot = Join-Path $root 'ci/angle-vcpkg'
}
if ([string]::IsNullOrWhiteSpace($InstallRoot)) {
    $InstallRoot = Join-Path $root 'build/angle-vcpkg-installed'
}
if ([string]::IsNullOrWhiteSpace($EvidencePath)) {
    $EvidencePath = Join-Path $root 'qa-angle/angle-hardening.json'
}

if (!(Test-Path $ReleasePath)) {
    throw "Windows Release folder does not exist: $ReleasePath"
}
if (!(Test-Path (Join-Path $ManifestRoot 'vcpkg.json'))) {
    throw "Pinned ANGLE vcpkg manifest is missing: $ManifestRoot"
}

function Resolve-Vcpkg {
    $command = Get-Command vcpkg -ErrorAction SilentlyContinue
    if ($null -ne $command) { return $command.Source }

    $candidates = @()
    if ($env:VCPKG_INSTALLATION_ROOT) {
        $candidates += (Join-Path $env:VCPKG_INSTALLATION_ROOT 'vcpkg.exe')
    }
    $candidates += 'C:\vcpkg\vcpkg.exe'
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) { return $candidate }
    }
    throw 'vcpkg.exe was not found on the Windows build agent.'
}

function Resolve-Dumpbin {
    $command = Get-Command dumpbin.exe -ErrorAction SilentlyContinue
    if ($null -ne $command) { return $command.Source }

    $programFilesX86 = [Environment]::GetFolderPath('ProgramFilesX86')
    $vswhere = Join-Path $programFilesX86 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (!(Test-Path $vswhere)) {
        throw 'vswhere.exe is unavailable; cannot audit PE dependencies.'
    }
    $vs = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath).Trim()
    if ([string]::IsNullOrWhiteSpace($vs)) {
        throw 'Visual Studio C++ toolchain was not found.'
    }
    $candidates = Get-ChildItem (Join-Path $vs 'VC\Tools\MSVC\*\bin\Hostx64\x64\dumpbin.exe') -ErrorAction SilentlyContinue | Sort-Object FullName -Descending
    if (!$candidates) {
        throw 'dumpbin.exe was not found in the active Visual Studio toolchain.'
    }
    return $candidates[0].FullName
}

function Get-PeMachine([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    try {
        $reader = New-Object IO.BinaryReader($stream)
        if ($reader.ReadUInt16() -ne 0x5A4D) {
            throw "Not a PE image: $Path"
        }
        $stream.Position = 0x3C
        $pe = $reader.ReadInt32()
        $stream.Position = $pe
        if ($reader.ReadUInt32() -ne 0x00004550) {
            throw "Invalid PE signature: $Path"
        }
        return $reader.ReadUInt16()
    }
    finally {
        $stream.Dispose()
    }
}

function Get-PeDependencies([string]$Dumpbin, [string]$Path) {
    $raw = & $Dumpbin /nologo /dependents $Path 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw ("dumpbin failed for " + $Path + [Environment]::NewLine + ($raw -join [Environment]::NewLine))
    }
    $deps = @()
    foreach ($line in $raw) {
        $value = $line.Trim()
        if ($value -match '^[A-Za-z0-9._+-]+\.dll$') {
            $deps += $value.ToLowerInvariant()
        }
    }
    return @($deps | Sort-Object -Unique)
}

$vcpkg = Resolve-Vcpkg
$dumpbin = Resolve-Dumpbin

$cache = Join-Path $root 'build/vcpkg-binary-cache'
New-Item -ItemType Directory -Force -Path $cache | Out-Null
$env:VCPKG_FEATURE_FLAGS = 'manifests,binarycaching'
$env:VCPKG_BINARY_SOURCES = "clear;files,$cache,readwrite"

Write-Host 'Building pinned ANGLE Release runtime through vcpkg...'
& $vcpkg install "--x-manifest-root=$ManifestRoot" "--x-install-root=$InstallRoot" '--triplet=x64-windows' '--clean-after-build'
if ($LASTEXITCODE -ne 0) {
    throw "vcpkg ANGLE installation failed with exit code $LASTEXITCODE."
}

$runtimeBin = Join-Path $InstallRoot 'x64-windows/bin'
$egl = Join-Path $runtimeBin 'libEGL.dll'
$gles = Join-Path $runtimeBin 'libGLESv2.dll'
foreach ($required in @($egl, $gles)) {
    if (!(Test-Path $required)) {
        throw "Pinned ANGLE build did not produce $required"
    }
    if ((Get-PeMachine $required) -ne 0x8664) {
        throw "ANGLE runtime is not AMD64: $required"
    }
}

$releaseDlls = Get-ChildItem $runtimeBin -Filter '*.dll' -File
if (!$releaseDlls) {
    throw 'No Release runtime DLLs were produced by ANGLE/vcpkg.'
}
foreach ($dll in $releaseDlls) {
    Copy-Item $dll.FullName (Join-Path $ReleasePath $dll.Name) -Force
}

$debugCrt = @(
    'msvcp140d.dll',
    'ucrtbased.dll',
    'vccorlib140d.dll',
    'vcruntime140_1d.dll',
    'vcruntime140d.dll'
)

$angleDependencies = @{}
foreach ($name in @('libEGL.dll', 'libGLESv2.dll')) {
    $path = Join-Path $ReleasePath $name
    $dependencies = Get-PeDependencies $dumpbin $path
    $angleDependencies[$name] = $dependencies
    $bad = @($dependencies | Where-Object { $debugCrt -contains $_ })
    if ($bad.Count -gt 0) {
        throw "$name still imports Debug CRT: $($bad -join ', ')"
    }
}

foreach ($name in $debugCrt) {
    $candidate = Join-Path $ReleasePath $name
    if (Test-Path $candidate) {
        Remove-Item $candidate -Force
    }
}
$remainingDebug = @(
    Get-ChildItem $ReleasePath -File |
        Where-Object { $debugCrt -contains $_.Name.ToLowerInvariant() } |
        ForEach-Object { $_.Name }
)
if ($remainingDebug.Count -gt 0) {
    throw "Debug CRT remains in Release: $($remainingDebug -join ', ')"
}

$plugin = Join-Path $ReleasePath 'flutter_angle_plugin.dll'
if (Test-Path $plugin) {
    $pluginDependencies = Get-PeDependencies $dumpbin $plugin
    if (!($pluginDependencies -contains 'libegl.dll') -or !($pluginDependencies -contains 'libglesv2.dll')) {
        throw 'flutter_angle_plugin.dll no longer imports both ANGLE runtime DLLs.'
    }
} else {
    $pluginDependencies = @()
}

$packageList = (& $vcpkg list "--x-install-root=$InstallRoot" 2>&1 | Out-String).Trim()
$manifest = Get-Content (Join-Path $ManifestRoot 'vcpkg.json') -Raw | ConvertFrom-Json
$angleHashes = @{}
foreach ($name in @('libEGL.dll', 'libGLESv2.dll')) {
    $path = Join-Path $ReleasePath $name
    $angleHashes[$name] = (Get-FileHash $path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$evidenceDir = Split-Path $EvidencePath
New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null
$evidence = [ordered]@{
    schema = 1
    source = 'microsoft/vcpkg angle'
    builtinBaseline = $manifest.'builtin-baseline'
    requestedAngleVersion = $manifest.dependencies[0].'version>='
    triplet = 'x64-windows'
    packageList = $packageList
    runtimeFolder = $runtimeBin
    copiedReleaseDlls = @($releaseDlls | ForEach-Object { $_.Name } | Sort-Object)
    sha256 = $angleHashes
    dependencies = $angleDependencies
    flutterAnglePluginDependencies = $pluginDependencies
    debugCrtRemaining = $remainingDebug
    amd64 = $true
}
$evidence | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 $EvidencePath

Write-Host 'ANGLE Release runtime hardened successfully.'
Write-Host "Evidence: $EvidencePath"
