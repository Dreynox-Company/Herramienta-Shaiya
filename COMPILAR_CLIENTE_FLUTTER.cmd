@echo off
setlocal
cd /d "%~dp0"
py -3 tool\prepare_local_game.py --platforms windows
if errorlevel 1 exit /b %errorlevel%
cd ingenieria_inversa\flutter_game
call flutter pub get --enforce-lockfile
if errorlevel 1 exit /b %errorlevel%
call flutter build windows --release
if errorlevel 1 exit /b %errorlevel%
echo EXE: %CD%\build\windows\x64\runner\Release\game.exe
