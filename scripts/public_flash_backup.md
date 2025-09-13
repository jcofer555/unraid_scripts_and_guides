```bash
#!/bin/bash

# Variables
BACKUP_LOCATION="/mnt/user/data/computer/backups/unraid_flash/"     # make sure to keep the / at the end of the path
MAX_BACKUPS=7  # Number of backups to keep

    #### DON'T CHANGE ANYTHING BELOW HERE ####

# Run the backup
backup_file="${BACKUP_LOCATION}flash_$(date +"%m-%d-%Y").tar.gz"
echo "Starting backup of Unraid flash drive to $backup_file"
if tar czf "$backup_file" -C / boot; then
    echo "Flash backup archive created $backup_file"
else
    echo "Backup of Unraid flash drive FAILED"
    exit 1
fi

# Verify integrity
echo "Checking integrity of archive"
if tar -tf "$backup_file" > /dev/null 2>&1; then
    echo "Backup file integrity check passed"
else
    echo "Backup file integrity check FAILED"
    echo "Deleting backup since integrity check failed"
    rm -rf "$backup_file"
    exit 1
fi

# Pause before cleanup
sleep 15

# Cleanup process to keep just the latest $MAX_BACKUPS backups
echo "Starting cleanup of old backups"
echo "Removing all but the latest $MAX_BACKUPS files in $BACKUP_LOCATION"
backup_files=( $(ls -1t "${BACKUP_LOCATION}"/flash_*.tar.gz 2>/dev/null) )
num_backups=${#backup_files[@]}

if [ "$num_backups" -gt "$MAX_BACKUPS" ]; then
    echo "Found $num_backups backup files; removing $((num_backups - MAX_BACKUPS)) oldest backups"
    for (( idx=MAX_BACKUPS; idx<num_backups; idx++ )); do
        file="${backup_files[$idx]}"
        echo "Removing $file"
        rm -f "$file" || {
            echo "Failed to remove file $file";
        }
    done
else
    echo "Only $num_backups backup files found; no cleanup required"
fi```
