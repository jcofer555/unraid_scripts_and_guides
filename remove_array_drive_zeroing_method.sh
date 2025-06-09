#!/bin/bash
# A script to clear an unRAID array drive.  It first checks the drive is completely empty,
# except for a marker indicating that the user desires to clear the drive.  The marker is
# that the drive is completely empty except for a single folder named 'clear-me'.
#
# Array must be started, and drive mounted.  There's no other way to verify it's empty.
# Without knowing which file system it's formatted with, I can't mount it.
#
# Quick way to prep drive: format with ReiserFS, then add 'clear-me' folder.
#
# 1.0  first draft
# 1.1  add logging, improve comments
# 1.2  adapt for User.Scripts, extend wait to 60 seconds
# 1.3  add progress display; confirm by key (no wait) if standalone; fix logger
# 1.4  only add progress display if unRAID version >= 6.2

version="1.4"
marker="clear-me"
found=0
wait=60
p=${0%%$P}              # dirname of program
p=${p:0:18}
q="/tmp/user.scripts/"

echo -e "*** Clear an unRAID array data drive ***  v$version\n"

# Check if array is started
ls /mnt/disk[1-9]* 1>/dev/null 2>/dev/null
if [ $? -ne 0 ]
then
   echo "ERROR:  Array must be started before using this script"
   exit
fi

# Look for array drive to clear
n=0
echo -n "Checking all array data drives (may need to spin them up) ... "
if [ "$p" == "$q" ] # running in User.Scripts
then
   echo -e "\n"
   c="<font color=blue>"
   c0="</font>"
else #set color teal
   c="\x1b[36;01m"
   c0="\x1b[39;49;00m"
fi

for d in /mnt/disk[1-9]*
do
   #echo -e "ls -A d:$d\n"
   x=`ls -A $d`
   #echo $x
   #echo -e "d:"$d "x:"${x:0:20}

   # the test for marker
   if [ "$x" == "$marker" ]
   then
        z=`du -s $d`
        y=${z:0:1}
        #echo -e "d:"$d "x:"${x:0:20} "y:"$y "z:"$z
        # the test for emptiness
        if [ "$y" == "0" ]
        then
            found=1
            #echo -e "d:"$d "is empty and has the 'clear-me' marker"
            break
        fi
   fi
   let n=n+1
done

#echo -e "found:"$found "d:"$d "marker:"$marker "z:"$z "n:"$n

# No drives found to clear
if [ $found == "0" ]
then
   echo -e "\rChecked $n drives, did not find an empty drive ready and marked for clearing!\n"
   echo "To use this script, the drive must be completely empty first, no files"
   echo "or folders left on it.  Then a single folder should be created on it"
   echo "with the name 'clear-me', exactly 8 characters, 7 lowercase and 1 hyphen."
   echo "This script is only for clearing unRAID data drives, in preparation for"
   echo "removing them from the array.  It does not add a Preclear signature."
   exit
fi

# check unRAID version
v1=`cat /etc/unraid-version`
v2="${v1:9:1}"
if [[ $v2 -ge 7 ]]
then
    v=" status=progress"
else
    v2="${v1:9:1}${v1:11:2}"
    if [[ $v2 -ge 610 ]]
    then
       v=" status=progress"
    else
       v=""
    fi
fi
#echo -e "v1=$v1  v2=$v2  v=$v\n"

# First, warn about the clearing, and give them a chance to abort
echo -e "\rFound a marked and empty drive to clear: $c Disk ${d:9} $c0 ( $d ) "
echo -e "* Disk ${d:9} will be unmounted first."
echo "* Then zeroes will be written to the entire drive."
echo "* Parity will be preserved throughout."
echo "* Clearing while updating Parity takes a VERY long time!"
echo "* The progress of the clearing will not be visible until it's done!"
echo "* When complete, Disk ${d:9} will be ready for removal from array."
echo -e "* Commands to be executed:\n***** $c umount $d $c0\n***** $c dd bs=1M if=/dev/zero of=/dev/md${d:9}p1 $v $c0\n"
if [ "$p" == "$q" ] # running in User.Scripts
then
   echo -e "You have $wait seconds to cancel this script (click the red X, top right)\n"
   sleep $wait
else
   echo -n "Press ! to proceed. Any other key aborts, with no changes made. "
   ch=""
   read -n 1 ch
   echo -e -n "\r                                                                  \r"
   if [ "$ch" != "!" ];
   then
      exit
   fi
fi

# Perform the clearing
logger -tclear_array_drive "Clear an unRAID array data drive  v$version"
echo -e "\rUnmounting Disk ${d:9} ..."
logger -tclear_array_drive "Unmounting Disk ${d:9}  (command: umount $d ) ..."
umount $d
echo -e "Clearing   Disk ${d:9} ..."
logger -tclear_array_drive "Clearing Disk ${d:9}  (command: dd bs=1M if=/dev/zero of=/dev/md${d:9}p1 $v ) ..."
dd bs=1M if=/dev/zero of=/dev/md${d:9}p1 $v
#logger -tclear_array_drive "Clearing Disk ${d:9}  (command: dd bs=1M if=/dev/zero of=/dev/md${d:9}p1 status=progress count=1000 seek=1000 ) ..."
#dd bs=1M if=/dev/zero of=/dev/md${d:9}p1 status=progress count=1000 seek=1000

# Done
logger -tclear_array_drive "Clearing Disk ${d:9} is complete"
echo -e "\nA message saying \"error writing ... no space left\" is expected, NOT an error.\n"
echo -e "Unless errors appeared, the drive is now cleared!"
echo -e "Because the drive is now unmountable, the array should be stopped,"
echo -e "and the drive removed (or reformatted)."
exit