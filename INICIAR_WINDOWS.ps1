$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
python tool/prepare.py
if ($LASTEXITCODE -ne 0) { throw 'No se pudieron preparar las plataformas.' }
flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'No se pudieron resolver las dependencias.' }
flutter run -d windows
