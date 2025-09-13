# UPDATING UNRAID OS TO A NEW VERSION: 

> [!IMPORTANT]
> - Read the release notes and these instructions before attempting the upgrade. If you have any questions, please ask in the #unraid-stable channel of the unraid official discord server which can be joined at https://discord.unraid.net
> - You can use this procedure for testing versions the ’next’ branch as well, but make sure to read the release notes for it and all previous testing versions

> [!IMPORTANT]
> - **DO NOT SKIP STEP 1**

> [!TIP]
> - Have a monitor and keyboard hooked to the server for any troubleshooting that might come up

### 1. **Go to the boot device section of the main tab and click on flash. Make a USB backup and test it to make sure it extracts correctly**
  > [!NOTE]
  > - If using unraid connect for USB backups, go to settings —> management access and make sure the backup is up to date
### 2. If it isn’t installed, install the fix common problems plugin as well as fully update all plugins that are installed
### 3. Go to settings —> docker and set enable docker to no to stop the docker service and all containers
  > [!NOTE]
  > - Confirm docker is stopped by checking the status at the top right of the settings —> docker screen
### 4. Shutdown any running virtual machines and then go to settings —> vm manager and set enable vms to no to stop the service
  > [!NOTE]
  > - Confirm vm manager is stopped by checking the status at the top right of the settings —> vm manager screen
### 5. Go to settings —> disk settings and set enable auto start to no to prevent the array from auto-starting after the update
### 6. Close any open web terminal sessions, ssh sessions, and make sure local terminal (at the server with a monitor) is logged out, and exit the unraid webgui on any browsers/devices not being used to perform the update (on local or remote systems)
### 7. If you are using the user scripts plugin, or you run scripts manually make sure no scripts are running
### 8. Go to the main page on unraids webui and unmount any disks and any smb/nfs shares under the unassigned devices section
### 9. Stop the array from the array operations section at the bottom of the main page of the unraids webui. Confirm it says array stopped in the bottom taskbar
### 10. Perform the upgrade at tools —> update os. Make sure to wait for any driver related plugins like nvidia drivers, realtek drivers, or others to confirm they have been updated
### 11. Reboot ONLY once you get a notification that it is ready to reboot
### 12. Once it reboots, login to the webgui and check to make sure all array and pool devices appear OK
  > [!NOTE]
  > - Optional: go to settings —> global share settings and set permit exclusive shares to yes
  > - Read the context sensitive help by pressing f1 on the keyboard. Also see the unraid documentation for more info at
  https://docs.unraid.net/unraid-os/release-notes/6.12.0/#exclusive-shares
### 13. In the array operations section at the bottom of the main page in unraids webui you should see “Configuration valid”. If so, start the array
### 14. Once the array has started and things look OK, re-enable docker and vm manager services and confirm that your containers and vm's operate as expected
### 15. If you prefer array auto start, go to settings —> disk settings and set enable auto start back to yes so the array autostarts on boot
  > [!NOTE]
  > - Many users prefer to leave auto start disabled so they can check their array and pool devices are all recognized properly after a shutdown/reboot
### 16. All done, enjoy the new version of unraid os
  > [!WARNING]
  > - Some plugins have issues going from one version to the next, happens more often with big version jumps. Known ones that i'm aware of is folderview, mover tuning, and themepark
  > - If you use these plugins and have problems with the system after updating you might need to remove them and look for new versions of them