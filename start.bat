@echo off
TITLE Mustermeister
set PG_SERVICE=postgresql-x64-17
echo Current directory: %CD%

where rails >nul 2>&1
if errorlevel 1 (
    echo Error: 'rails' command not found in PATH
    echo Please ensure Ruby and Rails are properly installed and in your PATH
    pause
    exit /b 1
)

sc query %PG_SERVICE% | find "RUNNING" >nul
if not errorlevel 1 (
    echo PostgreSQL is already running
    goto start_rails
)

:: Starting a service needs administrator rights. When this window is not
:: elevated, Windows can only grant them to a new process, so the service is
:: started from a separate short-lived window while this one waits.
net session >nul 2>&1
if not errorlevel 1 (
    call "%~dp0scripts\start_postgres.bat" %PG_SERVICE%
) else (
    echo Requesting administrator privileges to start PostgreSQL...
    powershell -NoProfile -Command "$p = Start-Process -FilePath '%~dp0scripts\start_postgres.bat' -ArgumentList '%PG_SERVICE%' -Verb RunAs -Wait -PassThru -ErrorAction Stop; exit $p.ExitCode"
)
if errorlevel 1 (
    echo Error: PostgreSQL is not running
    pause
    exit /b 1
)

:start_rails
echo Starting Rails server...
rails server
