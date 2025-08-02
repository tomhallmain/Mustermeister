#!/bin/bash

# Configuration
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Use backup directory from parameter or default to db_backups
if [ -z "$1" ]; then
    BACKUP_DIR="db_backups"
else
    BACKUP_DIR="$1"
fi

DB_NAME="myapp_development"
DB_USER="myapp"
DB_PASS="test"
BACKUP_FILE="${BACKUP_DIR}/${DB_NAME}_${TIMESTAMP}.sql"

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Create backup
echo "Creating backup of $DB_NAME..."
PGPASSWORD="$DB_PASS" pg_dump -U "$DB_USER" -h localhost -F c -b -v -f "$BACKUP_FILE" "$DB_NAME"

# Check if backup was successful
if [ $? -eq 0 ]; then
    echo "Backup completed successfully: $BACKUP_FILE"
else
    echo "Backup failed!"
    exit 1
fi

# Keep only the last 5 backups
cd "$BACKUP_DIR"
ls -t "${DB_NAME}_"*.sql 2>/dev/null | tail -n +6 | xargs -r rm

echo "Backup process completed." 