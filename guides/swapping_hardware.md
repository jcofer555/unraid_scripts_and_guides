# STEPS SUGGESTED WHEN SWAPPING HARDWARE:
> [!IMPORTANT]
> - **DO NOT SKIP STEP 1**
> - Unraid is mostly hardware agnostic so your drives and data is safe 99.9% of the time, you can help make things go smoother by following the below

> [!TIP]
> - Have a monitor and keyboard hooked to the server for any troubleshooting that might come up
### 1. Backup your current flash drive either in unraid with the flash backup button located by clicking flash in blue letters on the main page of unraids webui or by copying and pasting all files using another os like windows to your desktop or another folder
### 2. Check tools —> system devices and look for any checkboxes that have checkmarks in them and uncheck them, then scroll down and click bind selected to vfio at boot. This will effectively disabled the bindings
  > [!NOTE]
  > - This is done becuase bindings are specific to hardware and is related to your current hardware so it's best to reset this and redo after the swap of hardware if needed
### 3. It can be worthwhile sometimes to reset network settings so defaults are used. Quick way to do this is delete network.cfg and network-rules.cfg (if you have this file) from the config folder of the flash drive
  > [!NOTE]
  > - This will reset your network settings for unraid to defaults which uses dhcp to get an ip address so your ip might change if you don't have an ip reservation in your router
  > - Use the monitor and keyboard or your routers webui to check what the new unraid ip is
### 4. Go to settings —> disk settings and set enable auto start to no and hit apply to prevent the array from auto-starting after the update
### 5. Go to settings —> docker change enable docker to yes and hit apply
  > [!NOTE]
  > - Confirm docker is started by checking the status at the top right of the settings —> docker screen
### 6. Shutdown any running virtual machines and then go to settings —> vm manager and set enable vms to no and hit apply to stop the service
  > [!NOTE]
  > - Confirm vm manager is stopped by checking the status at the top right of the settings —> vm manager screen
### 7. Reboot unraid
### 8. In the array operations section at the bottom of the main page in unraids webui you should see “Configuration valid”. If so, start the array
### 9. Once the array has started and things look ok, re-enable docker at settings —> docker and set enable docker to yes and hit apply then re-enable vm manager at settings —> vm manager and set enable vms to yes and hit apply
  > [!NOTE]
  > - Confirm docker is started by checking the status at the top right of the settings —> docker screen
  > - Confirm vm manager is started by checking the status at the top right of the settings —> vm manager screen
### 10. If you prefer your array to auto start, go to settings —> disk settings and set enable auto start back to yes and hit apply so the array autostarts on boot
  > [!NOTE]
  > - Many users prefer to leave auto start disabled so they can check their array and pool devices are all recognized properly after a shutdown/reboot
### 11. If you need to bind hardware to vfio then do so again at tools —> system devices by putting checkboxes into the devices you want and then scrolling down and click bind selected to vfio at boot