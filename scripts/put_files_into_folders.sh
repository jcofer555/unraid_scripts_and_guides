#!/bin/bash

# Set the target directory to the path you want to work on.
TARGET_DIR="/mnt/user/sharename/test"

# DON'T CHANGE ANYTHING BELOW

# Change to the target directory and exit if it fails.
cd "$TARGET_DIR" || { echo "Error: Could not change directory to $TARGET_DIR exiting without doing anything"; exit 1; }

# Enable nullglob to avoid issues when no files match.
shopt -s nullglob

# Iterate over every item in the directory.
for file in *; do
    # Process only regular files.
    [ -f "$file" ] || continue

    # Get the base name (everything before the last dot). Files with the same 
    # base name (even if they have different extensions) will share the same folder.
    base="${file%.*}"

    # Create the directory if it doesn't already exist.
    mkdir -p "$base"

    # Move the file into the folder.
    mv -f "$file" "$base/"
done

echo "Script is done running"