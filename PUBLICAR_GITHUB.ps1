[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Repositorio,
    [string]$Rama = 'feat/studio-05-integration',
    [switch]$SoloLocal
)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
$python = Get-Command py -ErrorAction SilentlyContinue
$prefix = @()
if ($python) { $prefix = @('-3') } else { $python = Get-Command python -ErrorAction SilentlyContinue }
if (-not $python) { throw 'Se necesita Python 3. Consulta INSTRUCCIONES.md.' }
$parameters = @('tool/publish_sources.py', $Repositorio, '--branch', $Rama)
if ($SoloLocal) { $parameters += '--no-push' }
& $python.Source @prefix @parameters
if ($LASTEXITCODE -ne 0) { throw 'Publicación detenida. No hay force-push ni fusión automática con main.' }
