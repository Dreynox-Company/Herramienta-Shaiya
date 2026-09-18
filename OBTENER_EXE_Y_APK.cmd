@echo off
setlocal
cd /d "%~dp0"
echo SHAIYA STUDIO 0.4.0 - Compilar Windows y Android en GitHub
rem No instala SDKs, no cambia ExecutionPolicy, no lee credenciales.
where py >nul 2>nul
if not errorlevel 1 (
  py -3 tool\cloud_build.py
) else (
  python tool\cloud_build.py
)
echo.
pause
endlocal
