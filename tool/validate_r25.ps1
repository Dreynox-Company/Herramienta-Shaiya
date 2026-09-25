# Validate the delivered source without modifying a remote branch or a game DATA.
# Example: pwsh -File tool/validate_r25.ps1 -FormatSources -BuildWindows
[CmdletBinding()]
param([switch]$FormatSources, [switch]$BuildWindows)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$qa = Join-Path $root ('qa-r25-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $qa | Out-Null
function Invoke-Checked {
    param([string]$Name, [string]$Command, [string[]]$Arguments)
    Write-Host "=== $Name ==="
    & $Command @Arguments 2>&1 | Tee-Object -FilePath (Join-Path $qa ($Name + '.txt'))
    if ($LASTEXITCODE -ne 0) { throw "$Name failed with exit code $LASTEXITCODE. No success is recorded." }
}
Push-Location $root
try {
    Get-Command flutter, dart, python -ErrorAction Stop | Out-Null
    $versionOutput = & flutter --version --machine
    if ($LASTEXITCODE -ne 0) { throw 'Flutter version could not be inspected.' }
    $version = ($versionOutput -join "`n") | ConvertFrom-Json
    if ($version.frameworkVersion -ne '3.47.4') {
        throw 'Use Flutter 3.47.4 pinned by the verified R24 workflow, or audit a separate toolchain update.'
    }
    $versionOutput | Set-Content -Encoding utf8 (Join-Path $qa 'toolchain.json')
    Invoke-Checked -Name 'dependencies' -Command 'flutter' -Arguments @('pub','get','--enforce-lockfile')
    if ($FormatSources) {
        # Only mechanical, explicitly named lint fixes. Does not disable lints.
        Invoke-Checked -Name 'mechanical-fixes' -Command 'dart' -Arguments @('fix','--apply','--code=curly_braces_in_flow_control_structures,unnecessary_import')
        Invoke-Checked -Name 'format' -Command 'dart' -Arguments @('format','lib','test','integration_test','tool')
    }
    Invoke-Checked -Name 'format-check' -Command 'dart' -Arguments @('format','--output=none','--set-exit-if-changed','lib','test','integration_test','tool')
    Invoke-Checked -Name 'analysis' -Command 'flutter' -Arguments @('analyze')
    Invoke-Checked -Name 'dart-flutter-tests' -Command 'flutter' -Arguments @('test','--reporter','expanded',"--file-reporter=json:$qa/flutter-tests.json")
    Invoke-Checked -Name 'python-tests' -Command 'python' -Arguments @('-m','unittest','discover','-s','tool/tests','-v')
    Invoke-Checked -Name 'flight-audit' -Command 'dart' -Arguments @('run','tool/audit_flight_latency.dart')
    if ($BuildWindows) {
        if ($env:OS -ne 'Windows_NT') { throw 'A real Windows host is required for the native gate.' }
        Invoke-Checked -Name 'prepare-windows' -Command 'python' -Arguments @('tool/prepare.py','--platforms','windows')
        Invoke-Checked -Name 'windows-dependencies' -Command 'flutter' -Arguments @('pub','get','--enforce-lockfile')
        $fixture = Join-Path $qa 'synthetic-data'
        $env:SHAIYA_FIXTURE_PATH = $fixture
        $env:SHAIYA_QA_PATH = Join-Path $qa 'native'
        Invoke-Checked -Name 'fixture' -Command 'python' -Arguments @('tool/make_native_fixture.py',$fixture)
        Invoke-Checked -Name 'windows-integration' -Command 'flutter' -Arguments @('test','integration_test/native_studio_test.dart','-d','windows','--reporter','expanded')
        Invoke-Checked -Name 'windows-release' -Command 'flutter' -Arguments @('build','windows','--release')
        Invoke-Checked -Name 'angle-dependencies' -Command 'python' -Arguments @('-m','pip','install','--disable-pip-version-check','--require-hashes','-r','ci/angle-runtime-requirements.txt')
        $release = Join-Path $root 'build/windows/x64/runner/Release'
        Invoke-Checked -Name 'angle-hardening' -Command 'python' -Arguments @('ci/harden_angle_runtime.py','--release',$release,'--evidence',(Join-Path $qa 'angle-runtime.json'))
        $env:PATH = "$release;$env:PATH"
        Invoke-Checked -Name 'spk-writer' -Command 'flutter' -Arguments @('test','test/spk_writer_test.dart','--reporter','expanded')
        & (Join-Path $root 'tool/smoke_windows.ps1')
        Copy-Item (Join-Path $root 'qa-windows') (Join-Path $qa 'window-smoke') -Recurse
    }
    @{source='R25 local delivery';strict_source_gates=$true;windows_gates=[bool]$BuildWindows;
      real_data_visual_acceptance=$false;native_game_exe_modified=$false;
      note='This result exists only after the commands above succeeded. Windows release folder is not the final CI package; ResourceProbe and FlightV3 extras still require the existing packaging workflow.'} |
        ConvertTo-Json | Set-Content -Encoding utf8 (Join-Path $qa 'SUCCESS.json')
    Write-Host "Validation finished: $qa"
} catch {
    @{success=$false;error=$_.Exception.Message} | ConvertTo-Json |
        Set-Content -Encoding utf8 (Join-Path $qa 'FAILURE.json')
    throw
} finally {
    Pop-Location
}
