#!/bin/bash

# Variables
UNIFI_PATH="/usr/lib/unifi/data/backup/autobackup/*"
UNIFI_DIR="/usr/lib/unifi/data/backup/autobackup"
	#### DON'T CHANGE THE ABOVE ####
UNIFI_SERVER="10.100.10.1"
UNIFI_USER="root"
UNIFI_PASSWORD="unifi-ssh-password"
UNRAID_PATH="/mnt/user/data/computer/networking/jons unifi/cloud ultra/autobackups/"
UNRAID_OWNER="jcofer555"
UNRAID_GROUP="users"
NUM_BACKUPS=15  # Number of backups to retrieve and keep

	#### DON'T CHANGE ANYTHING BELOW ####

# Remove old backups
echo "Removing all files in $UNRAID_PATH"
if rm -rf "${UNRAID_PATH}"; then
    echo "Files removed from $UNRAID_PATH"
else
    echo "Failed to remove files in $UNRAID_PATH"
fi

# Ensure backup location exists
echo "Checking if backup destination exists $UNRAID_PATH"
if [ -d "$UNRAID_PATH" ]; then
    echo "Backup destination already exists $UNRAID_PATH"
else
    echo "Backup destination does not exist, Attempting to create $UNRAID_PATH"
    if mkdir -p "$UNRAID_PATH"; then
        echo "Successfully created backup destination $UNRAID_PATH"
    else
        echo "Failed to create backup destination $UNRAID_PATH"
    fi
fi

# Change ownership of the backup directory
echo "Changing ownership of $UNRAID_PATH"
if chown -R "${UNRAID_OWNER}:${UNRAID_GROUP}" "$UNRAID_PATH"; then
    echo "Successfully changed ownership of $UNRAID_PATH"
else
    echo "Failed to change ownership of $UNRAID_PATH"
fi

# Get list of latest backup files
echo "Retrieving list of backup files from remote"
tmpfile=$(mktemp)
if sshpass -p "${UNIFI_PASSWORD}" ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
    "${UNIFI_USER}@${UNIFI_SERVER}" \
    "find ${UNIFI_DIR} -type f -name 'autobackup*' -print0 | xargs -0 ls -t | head -n ${NUM_BACKUPS} | tr '\n' '\0'" > "$tmpfile"; then
    echo "Successfully retrieved file list from remote"
    mapfile -d '' backup_files < "$tmpfile"
else
    echo "Failed to retrieve list of backup files from remote"
    backup_files=()
fi
rm -f "$tmpfile"

# Copy files
echo "****Starting the copy of files from unifi to local storage****"
echo
if [ ${#backup_files[@]} -eq 0 ]; then
    echo "No backup files found by the remote find command"
else
    for file in "${backup_files[@]}"; do
        echo "Copying file: ${file}"
        if sshpass -p "${UNIFI_PASSWORD}" scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
           "${UNIFI_USER}@${UNIFI_SERVER}:${file}" "${UNRAID_PATH}"; then
            echo "Successfully copied ${file}"
            echo
        else
            echo "Failed to copy file: ${file}"
        fi
    done
fi