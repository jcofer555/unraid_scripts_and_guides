#!/bin/bash

# Search directory you want to be scanned
SEARCH_DIR="/mnt/user/mymedia"
# Location of the log file for what files are hardlinked in the directory above
LOG_FILE="/mnt/user/data/hardlink_audit.log"

# DON'T CHANGE ANYTHING BELOW

echo "Scanning for hardlinks in $SEARCH_DIR..." > "$LOG_FILE"

find "$SEARCH_DIR" -type f -links +1 -exec ls -li {} \; >> "$LOG_FILE"

echo "Scan complete. Results saved to $LOG_FILE"