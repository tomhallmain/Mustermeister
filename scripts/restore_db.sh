#!/bin/bash

# Configuration
BACKUP_DIR="db_backups"
DB_NAME="myapp_development"
DB_USER="myapp"
DB_PASS="test"

# Check if backup file is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <backup_file>"
    echo "Available backups:"
    ls -la "$BACKUP_DIR/${DB_NAME}_"*.sql 2>/dev/null || echo "No backups found"
    exit 1
fi

BACKUP_FILE="$1"

# Check if backup file exists
if [ ! -f "$BACKUP_FILE" ]; then
    echo "Backup file not found: $BACKUP_FILE"
    exit 1
fi

# Confirm restore
read -p "Are you sure you want to restore from $BACKUP_FILE? This will overwrite the current database. (y/n): " CONFIRM
if [ "$CONFIRM" != "y" ]; then
    echo "Restore cancelled."
    exit 1
fi

# Drop and recreate database
echo "Dropping and recreating database..."
PGPASSWORD="$DB_PASS" dropdb -U "$DB_USER" -h localhost "$DB_NAME"
PGPASSWORD="$DB_PASS" createdb -U "$DB_USER" -h localhost "$DB_NAME"

# Restore from backup
echo "Restoring from backup..."
PGPASSWORD="$DB_PASS" pg_restore -U "$DB_USER" -h localhost -d "$DB_NAME" -v "$BACKUP_FILE"

if [ $? -eq 0 ]; then
    echo "Restore completed successfully."
else
    echo "Restore failed!"
    exit 1
fi 