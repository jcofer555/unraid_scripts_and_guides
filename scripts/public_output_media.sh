#!/bin/bash

# TV shows directories
DIR1="/mnt/user/mymedia/media/tv - need to encode"
DIR2="/mnt/user/mymedia/media/tv"
OUTPUT1="/mnt/user/data/computer/tv_shows_list.txt"

# Movie Directories
DIR3="/mnt/user/mymedia/media/movies/animated"
DIR4="/mnt/user/mymedia/media/movies/a-z"
DIR5="/mnt/user/mymedia/media/movies/a-z - need to encode"
DIR6="/mnt/user/mymedia/media/movies/marvel-dc"
OUTPUT2="/mnt/user/data/computer/movies_list.txt"


    #### DON'T CHANGE ANYTHING HERE EXCEPT FOR THE BOTTOM VARIABLES SECTIONS TO MATCH THE VARIABLES ABOVE ####
    

# Function to find which disk a file/folder is on
find_disk() {
  local rel_path="$1"
  for disk in /mnt/disk*; do
    if [ -e "$disk/$rel_path" ]; then
      basename "$disk"  # disk1, disk2, etc.
      return
    fi
  done
}

# Function to process directories
process_dirs() {
  local OUT="${!#}"  # Last argument is output file
  local DIRS=("${@:1:$(($#-1))}")  # All but the last argument

  > "$OUT"  # Clear output

  for DIR in "${DIRS[@]}"; do
    if [[ ! -d "$DIR" ]]; then
      echo "❌ Error: '$DIR' is not a directory."
      continue
    fi

    while IFS= read -r entry; do
      rel_path="${DIR#/mnt/user/}/$entry"  # Strip /mnt/user/
      disk=$(find_disk "$rel_path")
      echo "$entry [$disk]" >> "$OUT"
    done < <(find "$DIR" -mindepth 1 -maxdepth 1 -type d -printf "%f\n")
  done

  sort -u "$OUT" -o "$OUT"
  echo "✅ Folder list with disk info saved to: $OUT"
}

# TV shows variables
process_dirs "$DIR1" "$DIR2" "$OUTPUT1"

# Movies variables
process_dirs "$DIR3" "$DIR4" "$DIR5" "$DIR6" "$OUTPUT2"
