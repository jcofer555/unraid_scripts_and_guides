# STEPS TO RECREATE YOUR FLASH DRIVE USING THE SAME FLASH DRIVE:

*** **make sure to do step1** ***

1. backup your current flash drive either in unraid with the flash backup button located by clicking flash in blue letters on the main page or by 
copying and pasting all files using another OS like windows to your desktop or another folder
2. if your flash drive was having errors then I'd suggest doing a full format not a quick format using windows or another OS, if no errors then 
continue, if errors it might be worth changing to a new flash drive.
3. download and install the usb creator at https://unraid.net/download, then use the creator to create your flash drive fresh with the version of 
unraid you wish to be on (sometimes it's worth picking the same version you were on prior)
    - note: you can determine what version you were on prior by opening changes.txt file at the root of the flash drive backup you made in step 1
    - note: if the creator fails to work you can try using the manual method to create the flash drive for this step, instructions at 
https://docs.unraid.net/unraid-os/getting-started/manual-install-method/
4. once creator or manual method is done successfully copy the entire config folder from your backup onto the flash drive, if you get a popup asking 
if you want to overwrite files say yes, then make sure there is only 1 .key file within config, deleting all but the one that matches your current 
license if there happens to be more than 1 in there
5. copy the syslinux.cfg file from your backups syslinux folder and put into the syslinux folder on the flash drive and say yes if you get asked to 
overwrite
6. if you have a folder named extra in your backup, copy it to the flash drive
7. all done, boot unraid with your recreated flash drive
8. ***only use this step if you switched to a different flash drive.***
go to tools > registration and click replace key to do the license transfer process, you can look here for more info on that https://docs.unraid.net/unraid-os/manual/changing-the-flash-device/
