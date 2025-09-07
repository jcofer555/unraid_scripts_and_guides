#!/bin/bash

# TV shows directories
TVSHOWSDIR1="/mnt/user/mymedia/media/tv - need to encode"
TVSHOWSDIR2="/mnt/user/mymedia/media/tv"
TVSHOWOUTPUT="/mnt/user/data/computer/tv_shows_list.txt"

# Movies Directories
MOVIESDIR1="/mnt/user/mymedia/media/movies/animated"
MOVIESDIR2="/mnt/user/mymedia/media/movies/a-z"
MOVIESDIR3="/mnt/user/mymedia/media/movies/a-z - need to encode"
MOVIESDIR4="/mnt/user/mymedia/media/movies/marvel-dc"
MOVIESOUTPUT="/mnt/user/data/computer/movies_list.txt"


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
process_dirs "$TVSHOWSDIR1" "$TVSHOWSDIR2" "$OUTPUT1"

# Movies variables
process_dirs "$MOVIESDIR1" "$MOVIESDIR2" "$MOVIESDIR3" "$MOVIESDIR4" "$OUTPUT2"
