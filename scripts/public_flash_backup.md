```bash
#!/bin/bash

# ============================
# User Variables
# ============================
BACKUP_LOCATION="/mnt/user/data/computer/backups/unraid_flash/"   # keep trailing slash
MAX_BACKUPS=7   # number of backups to keep

# ============================
# Validation
# ============================

# Validate MAX_BACKUPS is numeric
if ! [[ "$MAX_BACKUPS" =~ ^[0-9]+$ ]]; then
    echo "Invalid value for MAX_BACKUPS: '$MAX_BACKUPS'"
    echo "Please enter a numeric value (digits only)"
    exit 1
fi

# Ensure backup directory exists
if [[ ! -d "$BACKUP_LOCATION" ]]; then
    echo "Backup directory does not exist. Creating: $BACKUP_LOCATION"
    if ! mkdir -p "$BACKUP_LOCATION"; then
        echo "Failed to create backup directory"
        exit 1
    fi
fi

# ============================
# Create Backup
# ============================

backup_file="${BACKUP_LOCATION}flash_$(date +"%m-%d-%Y").tar.gz"

echo "Starting backup of Unraid flash drive to $backup_file"
if tar czf "$backup_file" -C / boot; then
    echo "Flash backup archive created: $backup_file"
else
    echo "Backup of Unraid flash drive FAILED"
    exit 1
fi

# ============================
# Verify Integrity
# ============================

echo "Checking integrity of archive"
if tar -tf "$backup_file" > /dev/null 2>&1; then
    echo "Backup file integrity check passed"
else
    echo "Backup file integrity check FAILED"
    echo "Deleting corrupted backup"
    rm -f "$backup_file"
    exit 1
fi

# ============================
# Ownership Normalization
# ============================

echo "Setting ownership for backup directory and all files"
if chown -R nobody:users "$BACKUP_LOCATION"; then
    echo "Ownership updated successfully for $BACKUP_LOCATION"
else
    echo "Failed to update ownership for $BACKUP_LOCATION"
    exit 1
fi

# ============================
# Cleanup Old Backups
# ============================

sleep 15  # optional pause

echo "Starting cleanup of old backups"
backup_files=( $(ls -1t "${BACKUP_LOCATION}"/flash_*.tar.gz 2>/dev/null) )
num_backups=${#backup_files[@]}

echo "Found $num_backups backup files"

if (( num_backups > MAX_BACKUPS )); then
    remove_count=$(( num_backups - MAX_BACKUPS ))
    echo "Removing $remove_count oldest backups"

    for (( idx=MAX_BACKUPS; idx<num_backups; idx++ )); do
        file="${backup_files[$idx]}"
        echo "Removing $file"
        rm -f "$file" || echo "Failed to remove file $file"
    done
else
    echo "No cleanup required"
fi

echo "Backup process completed successfully"

```
