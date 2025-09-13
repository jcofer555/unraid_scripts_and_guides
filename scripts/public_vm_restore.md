```bash
#!/bin/bash

# Define VM names
vm_names=("vm1" "vm2" "vm3")  # Add as many as needed

# Base paths
backup_path="/mnt/user/data/computer/backups/unraid_vms"

        #### DON'T CHANGE ANYTHING BELOW HERE ####

xml_base="/etc/libvirt/qemu"
nvram_base="$xml_base/nvram"
domain_base="/mnt/user/domains"

# Ensure required directories exist
mkdir -p "$nvram_base"

for vm_name in "${vm_names[@]}"; do
    echo "Restoring VM: $vm_name"

    vm_backup_path="$backup_path/$vm_name"
    vm_xml="$xml_base/$vm_name.xml"
    vm_domain_path="$domain_base/$vm_name"

    # Navigate to the VM's backup folder
    cd "$vm_backup_path" || { echo "Backup path not found for $vm_name"; continue; }

    # Stop the VM if it's running
    virsh shutdown "$vm_name"
    sleep 5

    # Remove old XML and restore new one
    rm -f "$vm_xml"
    cp "$vm_name.xml" "$vm_xml"

    # Restore NVRAM and disk image
    cp *.fd "$nvram_base/"
    mkdir -p "$vm_domain_path"
    cp *.img "$vm_domain_path/"

    # Redefine the VM
    virsh define "$vm_xml"

    echo "Restore of $vm_name is complete"
done

```
