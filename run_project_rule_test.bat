@echo off
REM Run rule smoke test (headless). Authoritative log: Project\logs\rule_smoke.log
REM Usage: F:\Aion\LegendaryTrader\run_project_rule_test.bat
setlocal

set "REPO=%~dp0"
if "%REPO:~-1%"=="\" set "REPO=%REPO:~0,-1%"
set "PROJ=%REPO%\Project"

set "GODOT=%REPO%\Godot_v4.6.2-stable_win64.exe"
if not exist "%GODOT%" (
    echo [run_project_rule_test] FATAL: Godot exe not found: %GODOT%
    exit /b 2
)
if not exist "%PROJ%\project.godot" (
    echo [run_project_rule_test] FATAL: project.godot not found: %PROJ%
    exit /b 2
)

if not exist "%PROJ%\logs" mkdir "%PROJ%\logs"
if exist "%PROJ%\logs\rule_smoke.log" del "%PROJ%\logs\rule_smoke.log"
if exist "%PROJ%\logs\rule_run.out"   del "%PROJ%\logs\rule_run.out"

echo [run_project_rule_test] PROJ=%PROJ%
echo [run_project_rule_test] GODOT=%GODOT%
echo [run_project_rule_test] running RuleSmokeTest.tscn ...

"%GODOT%" --headless --path "%PROJ%" "res://tests/RuleSmokeTest.tscn" 1> "%PROJ%\logs\rule_run.out" 2>&1
set "RC=%ERRORLEVEL%"

echo [run_project_rule_test] godot exit code = %RC%
echo [run_project_rule_test] stdout/stderr -^> Project\logs\rule_run.out
echo [run_project_rule_test] self-log      -^> Project\logs\rule_smoke.log
echo [run_project_rule_test] -------- last 10 lines of rule_smoke.log --------
powershell -NoProfile -Command "if (Test-Path '%PROJ%\logs\rule_smoke.log') { Get-Content '%PROJ%\logs\rule_smoke.log' -Tail 10 } else { Write-Output '(file not produced)' }"

findstr /B "PASS" "%PROJ%\logs\rule_smoke.log" >nul 2>&1
if %ERRORLEVEL%==0 (
    echo [run_project_rule_test] RESULT: PASS
    exit /b 0
)
echo [run_project_rule_test] RESULT: FAIL
if "%RC%"=="0" exit /b 3
exit /b %RC%
