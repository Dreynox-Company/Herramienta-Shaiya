@echo off
setlocal
cd /d "%~dp0"
echo SHAIYA STUDIO 0.4.0 - Compilar con Flutter instalado en este equipo
where py >nul 2>nul
if not errorlevel 1 (
  py -3 tool\build.py --platform both --run
) else (
  python tool\build.py --platform both --run
)
echo.
pause
endlocal
