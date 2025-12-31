```bash
#!/bin/bash

# ============================================================
# Variables to change
# ============================================================

# VM names
vm_names=("vm1" "vm2" "vm3")

# Backup base path
backup_path="/mnt/user/backups/vms"

# VM storage location
vm_domains="/mnt/user/domains"

# Dry run option. Set to true to do a test run
DRY_RUN=false

        #### DON'T CHANGE ANYTHING BELOW HERE UNLESS YOU KNOW WHAT YOU'RE DOING ####

# ============================================================
# System paths
# ============================================================
xml_base="/etc/libvirt/qemu"
nvram_base="$xml_base/nvram"

mkdir -p "$nvram_base"

# ============================================================
# Log output helpers
# ============================================================
log()  { echo -e "[INFO]  $1"; }
warn() { echo -e "[WARN]  $1"; }
err()  { echo -e "[ERROR] $1"; }

# ============================================================
# Validation failure helper
# ============================================================
validation_fail() {
    err "$1"
    warn "Skipping VM: $vm"
}

# ============================================================
# Dry-run mode detection
# ============================================================
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
fi

if $DRY_RUN; then
echo ""
echo "============================================================"
echo "RUNNING IN DRY-RUN MODE — NO CHANGES WILL BE MADE"
echo "============================================================"
fi

# ============================================================
# Dry run wrapper
# ============================================================
run_cmd() {
    if $DRY_RUN; then
        echo "[DRY RUN] $*"
    else
        eval "$@"
    fi
}

# ============================================================
# Process each VM
# ============================================================
for vm in "${vm_names[@]}"; do
    echo ""
    echo "===================================="
    echo " Restoring VM: $vm"
    echo "===================================="

    backup_dir="$backup_path/$vm"

    xml_file="$backup_dir/$vm.xml"
    nvram_file=$(ls "$backup_dir"/*_VARS-pure-efi.fd 2>/dev/null | head -n1)
    disks=( "$backup_dir"/vdisk*.img )

    # ============================================================
    # Validate backup contents
    # ============================================================
    if [[ ! -d "$backup_dir" ]]; then
        validation_fail "Backup folder missing: $backup_dir"
        continue
    fi
    if [[ ! -f "$xml_file" ]]; then
        validation_fail "XML file missing: $xml_file"
        continue
    fi
    if [[ ! -f "$nvram_file" ]]; then
        validation_fail "NVRAM file missing (expected UUID*_VARS-pure-efi.fd)"
        continue
    fi
    if [[ ! -f "${disks[0]}" ]]; then
        validation_fail "No vdisk*.img files found"
        continue
    fi

    log "Backup validated."

    # ============================================================
    # Shutdown VM cleanly
    # ============================================================
    if virsh list --state-running | grep -q " $vm "; then
        log "Shutting down VM gracefully..."

        run_cmd virsh shutdown "$vm"
        sleep 10

        if virsh list --state-running | grep -q " $vm "; then
            warn "VM still running — forcing stop."
            run_cmd virsh destroy "$vm"
        fi
    else
        log "VM is not running."
    fi

    # ============================================================
    # Restore XML
    # ============================================================
    dest_xml="$xml_base/$vm.xml"
    log "Restoring XML → $dest_xml"

    run_cmd rm -f "$dest_xml"
    run_cmd cp "$xml_file" "$dest_xml"
    run_cmd chmod 644 "$dest_xml"

    # ============================================================
    # Restore NVRAM
    # ============================================================
    nvram_filename=$(basename "$nvram_file")
    dest_nvram="$nvram_base/$nvram_filename"

    log "Restoring NVRAM → $dest_nvram"

    run_cmd rm -f "$dest_nvram"
    run_cmd cp "$nvram_file" "$dest_nvram"
    run_cmd chmod 644 "$dest_nvram"

    # ============================================================
    # Restore vdisks
    # ============================================================
    dest_domain="$vm_domains/$vm"
    run_cmd mkdir -p "$dest_domain"

    for d in "${disks[@]}"; do
        file=$(basename "$d")
        log "Copying disk: $file → $dest_domain/"
        run_cmd cp "$d" "$dest_domain/$file"
        run_cmd chmod 644 "$dest_domain/$file"
    done

    # ============================================================
    # Redefine VM
    # ============================================================
    log "Redefining VM via libvirt…"
    run_cmd virsh define "$dest_xml"

    log "VM $vm restore completed."
    restored_vms+=("$vm")

done

echo ""
echo "============================================================"
echo "       VM RESTORE PROCESS COMPLETE"
echo "============================================================"
$DRY_RUN && echo "[DRY RUN] No changes were made."

```
