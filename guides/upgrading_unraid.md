# Updating unRAID OS to a new stable release - jcofer/AgentXXL hybrid version: 

****
Read the release notes and these instructions before attempting the upgrade (see note 1 below). If you have any questions, please ask in the 
#unraid-stable channel of the unRAID Official Discord server which can be joined at this url https://discord.unraid.net
****

DO NOT SKIP STEP 1!

1. *** **Go to the Boot Device section of the Main tab and click on Flash. Make a USB backup and test it to make sure it extracts correctly.** ***
    - Optional: If using unRAID Connect for USB backups, go to Settings —> Management Access and make sure the backup is up to date.
3. If it isn’t installed, install the Fix Common Problems plugin as well as fully update all plugins that are installed.
4. Go to Settings —> Docker and set Enable Docker to no to stop the Docker service and all containers.
5. Shutdown any running VMs and then go to Settings —> VM Manager and set Enable VMs to no to stop the VM service.
6. Go to Settings > Disk Settings and set Enable auto start to no to prevent the array from auto-starting after the update.
7. Close any open web terminal sessions, ssh sessions, and make sure local terminal (at the server with a monitor) is logged out, and exit the unRAID 
webgui on any browsers/devices not being used to perform the update (on local or remote systems).
8. If you are using the User Scripts plugin, or you run scripts manually make sure no scripts are running.
9. Go to the Main tab and unmount any disks and any smb/nfs shares under the Unassigned Devices plugin section.
10. Stop the array from the Array Operations section at the bottom of the Main tab. Confirm it says array stopped in the bottom taskbar.
11. Perform the upgrade at Tools —> Update OS. Make sure to wait for any plugins like the Nvidia drivers to confirm they have been updated.
12. Reboot ONLY once you get a notification that it is ready to reboot.
13. Once it reboots, login to the webgui and check to make sure all array and pool devices appear OK.
    - Optional: Go to Settings —> Global Share Settings and set Permit exclusive shares to yes. See note 3 below.
14. In the Array Operations sections you should see “Configuration valid”. If so, start the array.
15. Once the array has started and things look OK, re-enable Docker and VM Manager services and confirm that your containers and VMs operate as 
expected.
16. If you prefer array auto-start, go to Settings —> Disk Settings and set Enable auto start back to yes so the array autostarts on boot. See note 2 
below.
17. All done!

## Notes:

1. You can use this procedure for testing releases (the ’Next’ branch) as well, but make sure to read the release notes for it and all previous testing
 versions.
2. Many users prefer to leave auto-start disabled so they can check their array and pool devices are all recognized properly after a shutdown/reboot.
3. Click on Permit exclusive shares under Global Share Settings and read the context sensitive help. Also see the unRAID documentation for more info.

Enjoy the new version of unRAID!
