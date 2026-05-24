@echo off
REM Run main trading scene (windowed)
REM Usage: F:\Aion\LegendaryTrader\run_project_game.bat
setlocal

set "REPO=%~dp0"
if "%REPO:~-1%"=="\" set "REPO=%REPO:~0,-1%"
set "PROJ=%REPO%\Project"

set "GODOT=%REPO%\Godot_v4.6.2-stable_win64.exe"

if not exist "%GODOT%" (
    echo [run_project_game] FATAL: Godot exe not found: %GODOT%
    exit /b 2
)
if not exist "%PROJ%\project.godot" (
    echo [run_project_game] FATAL: project.godot not found: %PROJ%
    exit /b 2
)

echo [run_project_game] PROJ=%PROJ%
echo [run_project_game] GODOT=%GODOT%
echo [run_project_game] launching main scene...

"%GODOT%" --path "%PROJ%" "res://scenes/Main.tscn"
exit /b %ERRORLEVEL%
