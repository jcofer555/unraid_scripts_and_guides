#!/bin/bash
if [ "$(stat -c '%i' /mnt/user/backups/mymedia/downloads/complete/tv/episode.mkv)" -eq "$(stat -c '%i' /mnt/user/backups/mymedia/downloads/tv/episode.mkv)" ]; then
    echo "The files are hardlinked."
else
    echo "The files are not hardlinked."
fi
