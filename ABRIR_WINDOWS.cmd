@echo off
cd /d "%~dp0"
rem La politica se aplica solo a este proceso, no se modifica el sistema.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0COMPILAR.ps1" -Plataforma Windows -Ejecutar
if errorlevel 1 pause
