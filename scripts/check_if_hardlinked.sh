#!/bin/bash
if [ "$(stat -c '%i' /mnt/user/backups/mymedia/downloads/complete/tv/Hawaii.Five-O.S12.1080p.AMZN.WEB-DL.DDP2.0.H.264-MZABI/Hawaii.Five-O.S12E20.Woe.To.Wo.Fat.1080p.AMZN.WEB-DL.DDP2.0.H.264-MZABI.mkv)" -eq "$(stat -c '%i' /mnt/user/backups/mymedia/downloads/tv/Hawaii\ Five-O\ 1968/Hawaii\ Five-O\ 1968\ -\ Season\ 12/Hawaii\ Five-O\ 1968\ -\ S12E20\ -\ Woe\ To\ Wo\ Fat.mkv)" ]; then
    echo "The files are hardlinked."
else
    echo "The files are not hardlinked."
fi