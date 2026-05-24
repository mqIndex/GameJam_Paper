@echo off
REM Run main trading scene (windowed)
REM Usage: F:\Aion\LegendaryTrader\Project\run_game.bat
setlocal

set "PROJ=%~dp0"
if "%PROJ:~-1%"=="\" set "PROJ=%PROJ:~0,-1%"

set "GODOT=%~dp0..\Godot_v4.6.2-stable_win64.exe"

if not exist "%GODOT%" (
    echo [run_game] FATAL: Godot exe not found: %GODOT%
    exit /b 2
)

echo [run_game] PROJ=%PROJ%
echo [run_game] GODOT=%GODOT%
echo [run_game] launching main scene...

"%GODOT%" --path "%PROJ%" "res://scenes/Main.tscn"
exit /b %ERRORLEVEL%
