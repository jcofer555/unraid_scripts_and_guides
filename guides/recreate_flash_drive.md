# STEPS TO RECREATE YOUR FLASH DRIVE USING THE SAME FLASH DRIVE OR A NEW FLASH DRIVE:
> [!IMPORTANT]
> - **DO NOT SKIP STEP 1**
### 1. Backup your current flash drive either in unraid with the flash backup button located by clicking flash in blue letters on the main page of unraids webui or by copying and pasting all files using another os like windows to your desktop or another folder
### 2. If your flash drive was having errors then I'd suggest doing a full format not a quick format using windows or another os, if no errors then continue, if errors it might be worth changing to a new flash drive.
### 3. Download and install the usb creator at https://unraid.net/download, then use the creator to create your flash drive fresh with the version of unraid you wish to be on 
> [!TIP]
> - Sometimes it's worth picking the same version you were on prior
> - If the creator fails to work you can try using the manual method to create the flash drive for this step, instructions at https://docs.unraid.net/unraid-os/getting-started/set-up-unraid/create-your-bootable-media/#manual-install-method

> [!NOTE]
> - You can determine what version you were on prior by opening changes.txt file at the root of the flash drive backup you made in step 1
### 4. Once creator or manual method is done successfully copy the entire config folder from your backup onto the flash drive, if you get a popup asking if you want to overwrite files say yes
> [!IMPORTANT]
> - Make sure there is only one .key file within config, deleting all but the one that matches your current license if there happens to be more than one in there

> [!NOTE]
> - The .key filenames are named after your license type, so if you have a starter license then the .key filename will be starter.key for example
### 5. Copy the syslinux.cfg file from your backups syslinux folder and put into the syslinux folder on the flash drive and say yes if you get asked to overwrite
> [!NOTE]
> - Don't copy the entire syslinux folder, copy only the syslinux.cfg file that is within the syslinux folder
### 6. If you have a folder named extra in your backup, copy it to the flash drive
### 7. All done, boot unraid with your recreated flash drive
### 8. ***only use this step if you switched to a different flash drive.***
Go to tools —> registration and click replace key to do the license transfer process, you can look here for more info on that process at https://docs.unraid.net/unraid-os/manual/changing-the-flash-device/
