```bash
#!/bin/bash

# Directory to scan
SEARCH_DIR="/mnt/user/mymedia"

# Log files
LOG_HARDLINKED="/mnt/user/data/files_that_are_hardlinked.log"
LOG_NOT_HARDLINKED="/mnt/user/data/files_not_hardlinked.log"

        #### DON'T CHANGE ANYTHING BELOW HERE ####

# Clear previous logs
echo "Scanning for hardlinked files in $SEARCH_DIR..." > "$LOG_HARDLINKED"
echo "Scanning for non-hardlinked files in $SEARCH_DIR..." > "$LOG_NOT_HARDLINKED"

# Find all regular files
ALL_FILES=$(find "$SEARCH_DIR" -type f)

# Iterate and classify
while IFS= read -r file; do
    link_count=$(stat --format="%h" "$file")
    inode_info=$(ls -li "$file")
    if [ "$link_count" -gt 1 ]; then
        echo "$inode_info" >> "$LOG_HARDLINKED"
    else
        echo "$inode_info" >> "$LOG_NOT_HARDLINKED"
    fi
done <<< "$ALL_FILES"

echo "Scan complete."
echo "Hardlinked files saved to: $LOG_HARDLINKED"
echo "Non-hardlinked files saved to: $LOG_NOT_HARDLINKED"```
