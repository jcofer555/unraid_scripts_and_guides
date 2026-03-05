```bash
1111111111111111111111111111111111111111111#!/bin/bash
set -e

# Mount devunraid dev_files share
echo "Attempting to mount devunraid dev_files share"

# Define the expected mount point
DEV_FILES_MOUNT="/mnt/remotes/devunraid_dev_files"

if mountpoint -q "$DEV_FILES_MOUNT"; then
    echo "$DEV_FILES_MOUNT is already mounted, skipping mount"
else
    if /usr/local/sbin/rc.unassigned mount //10.100.10.252/dev_files >/dev/null 2>&1; then
        echo "Mounting devunraid dev_files share succeeded"
        sleep 5
else
    echo "Mounting devunraid dev_files share failed"
    exit 1
fi
fi

# Proceed if mounted
if mountpoint -q "/mnt/remotes/devunraid_dev_files"; then
    echo "****Devunraid dev_files share is mounted successfully, proceeding with automover copy****"

# Options: 1-latest, 2-second, 3-third, 4-fourth, 5-fifth
RESTORE_VERSION="01-latest"

# Paths
BACKUP_BASE="/mnt/remotes/devunraid_dev_files/automover"
TARGET_DIR="/usr/local/emhttp/plugins/automover"

# ===============================
# SAFETY CHECKS
# ===============================
SRC_DIR="$BACKUP_BASE/$RESTORE_VERSION"

if [[ ! -d "$SRC_DIR" ]]; then
  echo "Backup version '$RESTORE_VERSION' not found at $SRC_DIR"
  exit 1
fi

if [[ ! -d "$TARGET_DIR" ]]; then
  echo "Target directory missing. Creating $TARGET_DIR..."
  mkdir -p "$TARGET_DIR"
fi

# ===============================
# RESTORE PROCESS
# ===============================
echo "Restoring Automover from backup: $SRC_DIR → $TARGET_DIR"

# Clean existing plugin files
rm -rf "$TARGET_DIR"

# Copy backup to destination
cp -r "$SRC_DIR" "$TARGET_DIR"	
	
else
    echo "Devunraid dev_files share not mounted, skipping backup"
fi

# Syncing
TIMEOUT="30"
if sync; then
    echo "Successfully flushed buffers"
else    
    echo "Failed to flush buffers"
fi
echo "Waiting 10 seconds"
sleep 10

# Unmount devunraid dev_files share
echo "Attempting to unmount devunraid dev_files share (timeout: ${TIMEOUT}s)"
unmounted=false
for (( i=0; i<$TIMEOUT; i++ )); do
    if /usr/local/sbin/rc.unassigned umount //10.100.10.252/dev_files >/dev/null 2>&1; then
        echo "Unmounting devunraid dev_files succeeded"
        unmounted=true
        break
    fi
    sleep 1
done

if [ "$unmounted" = false ]; then
    echo "Unmounting devunraid dev_files share failed after ${TIMEOUT}s"
fi
```
