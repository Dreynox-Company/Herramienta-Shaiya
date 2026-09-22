@echo off
setlocal
cd /d "%~dp0"
py -3 tool\build_flight_key.py
if errorlevel 1 (
  echo La compilacion fallo. Revisa el registro en .build-logs.
  pause
  exit /b 1
)
echo Listo. Los paquetes estan en dist y dist-game.
pause
