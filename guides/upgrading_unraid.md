# UPDATING UNRAID OS TO A NEW RELEASE: 

> [!IMPORTANT]
> read the release notes and these instructions before attempting the upgrade. If you have any questions, please ask in the #unraid-stable channel of the unraid official discord server which can be joined at this url https://discord.unraid.net \
> You can use this procedure for testing releases (the ’Next’ branch) as well, but make sure to read the release notes for it and all previous testing versions.

> [!IMPORTANT]
> **DO NOT SKIP STEP 1**

> [!TIP]
> Have a monitor and keyboard hooked to the server for any troubleshooting that might come up

### 1. **Go to the boot device section of the main tab and click on flash. Make a USB backup and test it to make sure it extracts correctly**
  > [!NOTE]
  > If using unraid connect for USB backups, go to settings —> management access and make sure the backup is up to date
### 2. If it isn’t installed, install the fix common problems plugin as well as fully update all plugins that are installed
### 4. Go to settings —> docker and set enable docker to no to stop the docker service and all containers
  > [!NOTE]
  > Confirm docker is stopped by checking the status at the top right of the settings > docker screen
### 5. Shutdown any running virtual machines and then go to settings —> vm manager and set enable vms to no to stop the service
  > [!NOTE]
  > Confirm vm manager is stopped by checking the status at the top right of the settings > vm manager screen
### 6. Go to settings > disk settings and set enable auto start to no to prevent the array from auto-starting after the update
### 7. Close any open web terminal sessions, ssh sessions, and make sure local terminal (at the server with a monitor) is logged out, and exit the unRAID webgui on any browsers/devices not being used to perform the update (on local or remote systems)
### 8. If you are using the user scripts plugin, or you run scripts manually make sure no scripts are running
### 9. Go to the main page on unraids webui and unmount any disks and any smb/nfs shares under the unassigned devices section
### 10. Stop the array from the array operations section at the bottom of the main page of the unraids webui. Confirm it says array stopped in the bottom taskbar
### 11. Perform the upgrade at tools —> update os. Make sure to wait for any driver related plugins like nvidia drivers, realtek drivers, or others to confirm they have been updated
### 12. Reboot ONLY once you get a notification that it is ready to reboot
### 13. Once it reboots, login to the webgui and check to make sure all array and pool devices appear OK
  > [!NOTE]
  > Optional: go to settings —> global share settings and set permit exclusive shares to yes \
  > Click on permit exclusive shares under global share settings and read the context sensitive help by pressing f1 on the keyboard. Also see the unraid documentation for more info at \
  > https://docs.unraid.net/unraid-os/release-notes/6.12.0/#exclusive-shares
### 14. In the array operations section at the bottom of the main page in unraids webui you should see “Configuration valid”. If so, start the array
### 15. Once the array has started and things look OK, re-enable docker and vm manager services and confirm that your containers and vm's operate as expected
### 16. If you prefer array auto start, go to settings —> disk settings and set enable auto start back to yes so the array autostarts on boot
> [!NOTE]
> Many users prefer to leave auto start disabled so they can check their array and pool devices are all recognized properly after a shutdown/reboot
### 17. All done, enjoy the new version unraid os