@echo off
setlocal enabledelayedexpansion

:: Configuration
set BACKUP_DIR=db_backups
set DB_NAME=rails_test_app_development

:: Check if backup file is provided
if "%~1"=="" (
    echo Usage: %0 ^<backup_file^>
    echo Available backups:
    dir /b /o-d "%BACKUP_DIR%\%DB_NAME%_*.sql"
    exit /b 1
)

set BACKUP_FILE=%~1

:: Check if backup file exists
if not exist "%BACKUP_FILE%" (
    echo Backup file not found: %BACKUP_FILE%
    exit /b 1
)

:: Confirm restore
set /p CONFIRM=Are you sure you want to restore from %BACKUP_FILE%? This will overwrite the current database. (y/n): 
if /i not "%CONFIRM%"=="y" (
    echo Restore cancelled.
    exit /b 1
)

:: Drop and recreate database
echo Dropping and recreating database...
dropdb -U postgres %DB_NAME%
createdb -U postgres %DB_NAME%

:: Restore from backup
echo Restoring from backup...
pg_restore -U postgres -d %DB_NAME% -v "%BACKUP_FILE%"

if %ERRORLEVEL% EQU 0 (
    echo Restore completed successfully.
) else (
    echo Restore failed!
    exit /b 1
) 