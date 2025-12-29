```bash
#!/bin/bash

# Set the target directory to the path you want to work on.
TARGET_DIR="/mnt/cache/isos"

        #### DON'T CHANGE ANYTHING BELOW HERE ####

# Change to the target directory and exit if it fails.
cd "$TARGET_DIR" || { echo "Error: Could not change directory to $TARGET_DIR exiting without doing anything"; exit 1; }

# Enable nullglob to avoid issues when no files match.
# Enable nocaseglob so all cases of extensions are considered.
shopt -s nullglob nocaseglob

# Iterate only over files with the allowed extensions.
for file in *.mp4 *.mov *.avi *.wmv *.webm *.mkv *.mxf *.mpeg *.vob *.m2fs *.srt *.vtt *.sub *.ssa *.ass *.stl *.ttml *.dfxp *.scc *.mcc *.sbv *.lrc *.sup *.idx; do
    # Process only regular files.
    [ -f "$file" ] || continue

    # Get the base name (everything before the last dot).
    base="${file%.*}"

    # Create the directory if it doesn't already exist.
    mkdir -p "$base"

    # Move the file into the folder.
    mv -f "$file" "$base/"
done

echo "Script is done running"

```
