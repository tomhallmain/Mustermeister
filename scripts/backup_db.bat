@echo off
setlocal enabledelayedexpansion

:: Configuration
set TIMESTAMP=%date:~-4%%date:~3,2%%date:~0,2%_%time:~0,2%%time:~3,2%%time:~6,2%
set TIMESTAMP=%TIMESTAMP: =0%

:: Use backup directory from parameter or default to db_backups
if "%~1"=="" (
    set BACKUP_DIR=db_backups
) else (
    set BACKUP_DIR=%~1
)

set DB_NAME=myapp_development
set DB_USER=myapp
set DB_PASS=test
set BACKUP_FILE=%BACKUP_DIR%\%DB_NAME%_%TIMESTAMP%.sql

:: Create backup directory if it doesn't exist
if not exist "%BACKUP_DIR%" mkdir "%BACKUP_DIR%"

:: Create backup
echo Creating backup of %DB_NAME%...
set PGPASSWORD=%DB_PASS%
pg_dump -U %DB_USER% -h localhost -F c -b -v -f "%BACKUP_FILE%" %DB_NAME%

:: Check if backup was successful
if %ERRORLEVEL% EQU 0 (
    echo Backup completed successfully: %BACKUP_FILE%
) else (
    echo Backup failed!
    exit /b 1
)

:: Keep only the last 5 backups
for /f "skip=5 delims=" %%F in ('dir /b /o-d "%BACKUP_DIR%\%DB_NAME%_*.sql"') do (
    del "%BACKUP_DIR%\%%F"
)

echo Backup process completed. 