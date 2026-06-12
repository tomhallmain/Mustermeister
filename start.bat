CALL TITLE Mustermeister
@echo off
:: Check if running as administrator
net session >nul 2>&1
if %errorLevel% == 0 (
    echo Running as administrator
    echo Current directory: %CD%
    
    :: Check if rails command is available
    where rails >nul 2>&1
    if %errorLevel% neq 0 (
        echo Error: 'rails' command not found in PATH
        echo Please ensure Ruby and Rails are properly installed and in your PATH
        pause
        exit /b 1
    )
    
    echo Starting Rails server...
    rails server
) else (
    echo Current directory: %CD%
    
    :: Check if PostgreSQL is running and store result
    for /f "tokens=*" %%a in ('sc query postgresql-x64-17 ^| find "RUNNING"') do set POSTGRES_RUNNING=1
    
    if defined POSTGRES_RUNNING (
        echo PostgreSQL is already running
        echo Starting Rails server...
        rails server
    ) else (
        echo Requesting administrator privileges to start PostgreSQL...
        powershell -Command "Start-Process cmd.exe -ArgumentList '/k cd /d \"%CD%\" && start.bat' -Verb RunAs"
        exit /b
    )
) 
