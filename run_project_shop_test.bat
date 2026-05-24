@echo off
REM Run shop smoke test (headless). Authoritative log: Project\logs\shop_smoke.log
REM Usage: F:\Aion\LegendaryTrader\run_project_shop_test.bat
setlocal

set "REPO=%~dp0"
if "%REPO:~-1%"=="\" set "REPO=%REPO:~0,-1%"
set "PROJ=%REPO%\Project"

set "GODOT=%REPO%\Godot_v4.6.2-stable_win64.exe"
if not exist "%GODOT%" (
    echo [run_project_shop_test] FATAL: Godot exe not found: %GODOT%
    exit /b 2
)
if not exist "%PROJ%\project.godot" (
    echo [run_project_shop_test] FATAL: project.godot not found: %PROJ%
    exit /b 2
)

if not exist "%PROJ%\logs" mkdir "%PROJ%\logs"
if exist "%PROJ%\logs\shop_smoke.log" del "%PROJ%\logs\shop_smoke.log"
if exist "%PROJ%\logs\shop_run.out"   del "%PROJ%\logs\shop_run.out"

echo [run_project_shop_test] PROJ=%PROJ%
echo [run_project_shop_test] GODOT=%GODOT%
echo [run_project_shop_test] running ShopSmokeTest.tscn ...

"%GODOT%" --headless --path "%PROJ%" "res://tests/ShopSmokeTest.tscn" 1> "%PROJ%\logs\shop_run.out" 2>&1
set "RC=%ERRORLEVEL%"

echo [run_project_shop_test] godot exit code = %RC%
echo [run_project_shop_test] stdout/stderr -^> Project\logs\shop_run.out
echo [run_project_shop_test] self-log      -^> Project\logs\shop_smoke.log
echo [run_project_shop_test] -------- last 10 lines of shop_smoke.log --------
powershell -NoProfile -Command "if (Test-Path '%PROJ%\logs\shop_smoke.log') { Get-Content '%PROJ%\logs\shop_smoke.log' -Tail 10 } else { Write-Output '(file not produced)' }"

findstr /B "PASS" "%PROJ%\logs\shop_smoke.log" >nul 2>&1
if %ERRORLEVEL%==0 (
    echo [run_project_shop_test] RESULT: PASS
    exit /b 0
)
echo [run_project_shop_test] RESULT: FAIL
if "%RC%"=="0" exit /b 3
exit /b %RC%
