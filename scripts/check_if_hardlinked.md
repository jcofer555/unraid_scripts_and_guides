```bash
#!/bin/bash

# Directory to scan
SEARCH_DIR="/mnt/user/mymedia"

# Log files
LOG_NOT_HARDLINKED="/mnt/user/data/files_not_hardlinked.log"
JDUPE_LOG="/mnt/user/data/jdupes_hardlinking.log"

# Dry run variable: set to "yes" to preview only, "no" to perform hardlinking
DRY_RUN="yes"

#### DON'T CHANGE ANYTHING BELOW HERE ####

echo "=== Starting scan for non-hardlinked files in $SEARCH_DIR ==="

# Clear previous logs
echo "Scanning for non-hardlinked files in $SEARCH_DIR..." > "$LOG_NOT_HARDLINKED"
echo "=== jdupes results ===" > "$JDUPE_LOG"

# Find all regular files (skip hidden and system metadata files)
ALL_FILES=$(find "$SEARCH_DIR" -type f \
    ! -path '*/.*' \
    ! -iname '.ds_store' \
    ! -iname 'thumbs.db')

# Classify files by hardlink status
while IFS= read -r file; do
    link_count=$(stat --format="%h" "$file")
    if [ "$link_count" -eq 1 ]; then
        echo "$file" >> "$LOG_NOT_HARDLINKED"
    fi
done <<< "$ALL_FILES"

echo "Scan complete."
echo "Non-hardlinked files saved to: $LOG_NOT_HARDLINKED"
echo

# Run jdupes if installed
if command -v jdupes >/dev/null 2>&1; then
    if [ "$DRY_RUN" = "yes" ]; then
        echo "DRY RUN: Showing potential hardlinks without making changes..."
        jdupes -r --no-hidden --files-from "$LOG_NOT_HARDLINKED" | tee -a "$JDUPE_LOG"
    else
        echo "Running jdupes to deduplicate and hardlink files..."
        jdupes -r -L --no-hidden --files-from "$LOG_NOT_HARDLINKED" | tee -a "$JDUPE_LOG"
        echo "jdupes deduplication complete. Log saved to: $JDUPE_LOG"
    fi
else
    echo "WARNING: jdupes not installed. Skipping hardlinking step."
fi```
