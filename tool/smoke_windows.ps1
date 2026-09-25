param(
    [string]$DataPath = "",
    [string]$OutputFolder = ""
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path "$PSScriptRoot/..").Path
$folder = if ([string]::IsNullOrWhiteSpace($OutputFolder)) {
    Join-Path $root 'qa-windows'
} elseif ([IO.Path]::IsPathRooted($OutputFolder)) {
    $OutputFolder
} else {
    Join-Path $root $OutputFolder
}
New-Item -ItemType Directory -Force $folder | Out-Null

$exe = Join-Path $root 'build/windows/x64/runner/Release/herramienta_shaiya.exe'
if (!(Test-Path $exe)) { throw "Release executable missing: $exe" }

$arguments = @()
$scope = 'Arranque de la aplicacion sin DATA. No acredita renderizado de recursos del juego.'
if (![string]::IsNullOrWhiteSpace($DataPath)) {
    $resolvedData = (Resolve-Path $DataPath).Path
    $arguments += "--data=$resolvedData"
    $scope = 'Arranque Release con DATA sintetica montada. Acredita que el runtime grafico puede abrir Studio y mantener viva la ventana con una escena DATA, no paridad visual con game.exe.'
}

$p = Start-Process -FilePath $exe -ArgumentList $arguments -WorkingDirectory (Split-Path $exe) -PassThru -RedirectStandardOutput (Join-Path $folder 'stdout.txt') -RedirectStandardError (Join-Path $folder 'stderr.txt')
try {
    Start-Sleep -Seconds 22
    $p.Refresh()
    if ($p.HasExited) { throw "El programa termino durante el arranque. Codigo: $($p.ExitCode)" }
    if ($p.MainWindowHandle -eq 0) { throw 'No se encontro una ventana nativa visible.' }

    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName System.Windows.Forms
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bitmap = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
    $screenshot = Join-Path $folder 'arranque.png'
    $bitmap.Save($screenshot, [System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose()
    $bitmap.Dispose()

    [ordered]@{
        process_alive = $true
        native_window = $true
        window_title = $p.MainWindowTitle
        data_path = if ($arguments.Count -gt 0) { $resolvedData } else { $null }
        screenshot_sha256 = (Get-FileHash $screenshot -Algorithm SHA256).Hash.ToLowerInvariant()
        scope = $scope
    } | ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $folder 'resultado.json')
}
finally {
    if (-not $p.HasExited) {
        $p.CloseMainWindow() | Out-Null
        Start-Sleep -Seconds 2
        $p.Refresh()
        if (-not $p.HasExited) { $p.Kill() }
    }
}
