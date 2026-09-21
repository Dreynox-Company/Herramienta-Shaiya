@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0COMPILAR.ps1" -Plataforma Android
pause
