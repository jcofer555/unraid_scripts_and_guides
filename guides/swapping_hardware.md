# STEPS SUGGESTED WHEN SWAPPING HARDWARE:
> [!IMPORTANT]
> - **DO NOT SKIP STEP 1**
### 1. Backup your current flash drive either in unraid with the flash backup button located by clicking flash in blue letters on the main page of unraids webui or by copying and pasting all files using another OS like windows to your desktop or another folder
### 2. Check tools —> system devices and look for any checkboxes that have checkmarks in them and uncheck them, then scroll down and click "bind selected to vfio at boot". This will effectively disabled the bindings
  > [!NOTE]
  > - This is done becuase bindings are specific to hardware and is related to your current hardware so it's best to reset this and redo after the swap of hardware if needed
  > - If cannot access the unraid webui to do the above, you can delete the file vfio-pci.cfg from the config folder of the flash drive
### 3. It can be worthwhile sometimes to reset network settings so defaults are used. Quick way to do this is delete network.cfg and network-rules.cfg (if you have this file) from the config folder of the flash drive
  > [!NOTE]
  > - This will reset your network settings for unraid to defaults which uses dhcp to get an ip address so your ip might change if you don't have an ip reservation in your router