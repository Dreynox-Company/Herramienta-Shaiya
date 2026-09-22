$ErrorActionPreference = 'Stop'
$root = (Resolve-Path "$PSScriptRoot/..").Path
$folder = Join-Path $root 'qa-windows'
New-Item -ItemType Directory -Force $folder | Out-Null
$exe = Join-Path $root 'build/windows/x64/runner/Release/herramienta_shaiya.exe'
$p = Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe) -PassThru -RedirectStandardOutput (Join-Path $folder 'stdout.txt') -RedirectStandardError (Join-Path $folder 'stderr.txt')
try {
    Start-Sleep -Seconds 18
    $p.Refresh()
    if ($p.HasExited) { throw "El programa termino durante el arranque. Codigo: $($p.ExitCode)" }
    if ($p.MainWindowHandle -eq 0) { throw 'No se encontro una ventana nativa visible.' }
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName System.Windows.Forms
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bitmap = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
    $bitmap.Save((Join-Path $folder 'arranque.png'), [System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose(); $bitmap.Dispose()
    @{process_alive=$true;native_window=$true;window_title=$p.MainWindowTitle;scope='Arranque de la aplicacion sin DATA. No acredita renderizado de recursos del juego.'} | ConvertTo-Json | Set-Content (Join-Path $folder 'resultado.json')
} finally {
    if (-not $p.HasExited) { $p.CloseMainWindow() | Out-Null; Start-Sleep -Seconds 2; $p.Refresh(); if (-not $p.HasExited) { $p.Kill() } }
}
