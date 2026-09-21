# Dreynox Shaiya Clean Client

Cliente Windows propio para el laboratorio de compatibilidad de Shaiya.

## Objetivo de 0.1

- No ejecuta ni modifica `game.exe`.
- No contiene VMProtect, anti-VM ni comprobaciones de Hyper-V.
- Lee recursos directamente desde una carpeta `DATA_Español` / `DATA`.
- WebGL 2 se ejecuta dentro de WebView2 mediante un host virtual local.
- Los guardados del laboratorio viven bajo `%LOCALAPPDATA%\Dreynox\ShaiyaCleanClient`.
- El modo inicial es offline. La arquitectura deja el transporte de servidor desacoplado para una fase posterior.

## Hosts internos

- `https://app.shaiya.local/` -> renderer incluido junto al ejecutable.
- `https://data.shaiya.local/` -> carpeta DATA elegida por el usuario.

No se abre un servidor HTTP ni se expone DATA por red.
