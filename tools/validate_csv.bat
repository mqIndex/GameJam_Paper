@echo off
REM 校验 Project/data/cards.csv 字段完整性, 失败时 exit /b 1
REM 用法: tools\validate_csv.bat
setlocal

set "REPO=%~dp0.."
if "%REPO:~-1%"=="\" set "REPO=%REPO:~0,-1%"
set "PROJ=%REPO%\Project"

set "GODOT=%REPO%\Godot_v4.6.2-stable_win64.exe"
if not exist "%GODOT%" (
    echo [validate_csv] FATAL: Godot exe not found: %GODOT%
    exit /b 2
)
if not exist "%PROJ%\project.godot" (
    echo [validate_csv] FATAL: project.godot not found: %PROJ%
    exit /b 2
)

echo [validate_csv] PROJ=%PROJ%
echo [validate_csv] running validate_cards.gd ...

"%GODOT%" --headless --path "%PROJ%" --script "res://tools/validate_cards.gd"
set "RC=%ERRORLEVEL%"
echo [validate_csv] exit code = %RC%
exit /b %RC%
