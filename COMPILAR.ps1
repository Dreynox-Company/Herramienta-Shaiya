[CmdletBinding()]
param(
    [ValidateSet('Windows','Android','Ambos','Pruebas')][string]$Plataforma = 'Windows',
    [switch]$Ejecutar,
    [switch]$Integracion
)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
$python = Get-Command py -ErrorAction SilentlyContinue
$prefix = @()
if ($python) { $prefix = @('-3') } else { $python = Get-Command python -ErrorAction SilentlyContinue }
if (-not $python) { throw 'Se necesita Python 3 para preparar los runners oficiales. Consulta INSTRUCCIONES.md.' }
$names = @{ Windows='windows'; Android='android'; Ambos='both'; Pruebas='test' }
$parameters = @('tool/build.py', '--platform', $names[$Plataforma])
if ($Ejecutar) { $parameters += '--run' }
if ($Integracion) { $parameters += '--integration' }
& $python.Source @prefix @parameters
if ($LASTEXITCODE -ne 0) { throw 'El proceso se detuvo. Revisa el mensaje anterior y .build-logs; no se ha declarado una compilación correcta.' }
