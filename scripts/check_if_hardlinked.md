```bash
#!/bin/bash

# Directory to scan
SEARCH_DIR="/mnt/user/appdata"

# Log files
LOG_NOT_HARDLINKED="/mnt/user/appdata/files_not_hardlinked.log"
JDUPE_LOG="/mnt/user/appdata/jdupes_hardlinking.log"

# Skip jdupes even if installed? set to "yes" or "no"
SKIP_JDUPES="no"

# Dry run variable: set to "yes" to preview only, "no" to perform hardlinking
DRY_RUN="yes"

echo
echo "=== Starting scan for non-hardlinked files in $SEARCH_DIR ==="

# Clear previous logs
echo "Scanning for non-hardlinked files in $SEARCH_DIR..."
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

# Run jdupes if not skipped and installed
if [ "$SKIP_JDUPES" != "yes" ] && command -v jdupes >/dev/null 2>&1; then
    if [ "$DRY_RUN" = "yes" ]; then
        echo "DRY RUN: Showing potential hardlinks without making changes..."
        if xargs -a "$LOG_NOT_HARDLINKED" jdupes -r --no-hidden 2>/dev/null >> "$JDUPE_LOG"; then
            echo "Dry run completed successfully."
        else
            echo "jdupes dry run failed"
        fi
    else
        echo "Running jdupes to deduplicate and hardlink files..."
        if xargs -a "$LOG_NOT_HARDLINKED" jdupes -r -L --no-hidden 2>/dev/null >> "$JDUPE_LOG"; then
            echo "jdupes deduplication complete. Log saved to: $JDUPE_LOG"
        else
            echo "jdupes hardlinking failed"
        fi
    fi
else
    echo "Skipping jdupes hardlinking step."
fi

```
