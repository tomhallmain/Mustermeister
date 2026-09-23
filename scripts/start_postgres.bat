@echo off
:: Starts the PostgreSQL Windows service given as the first argument.
:: Needs administrator rights: start.bat runs it elevated and waits for it.
set PG_SERVICE=%~1
if "%PG_SERVICE%"=="" set PG_SERVICE=postgresql-x64-17

echo Starting PostgreSQL service %PG_SERVICE%...
net start %PG_SERVICE%
if errorlevel 1 (
    echo Error: PostgreSQL service %PG_SERVICE% could not be started
    pause
    exit /b 1
)
exit /b 0
