#!/bin/bash

# Variables
DISKS_FILE="/var/local/emhttp/disks.ini"
OUTPUT_FILE="/mnt/user/backups/disk_assignments.txt"
SKIP_DRIVES=("parity" "parity2")

    #### DON'T CHANGE ANYTHING BELOW HERE ####

# Checking if disks.ini exists
echo "Checking if disks.ini exists"
if [[ ! -f "$DISKS_FILE" ]]; then
    echo "Error, $DISKS_FILE doesn't exist, exiting"
    exit 1
fi
echo "disks.ini exists, starting output of disk assignments"
# Function to check for skipped drives
echo "Disk Assignments as of $(date +"%m-%d-%Y_%I-%M-%S_%p")" > "$OUTPUT_FILE"
echo

is_skipped_drive() {
    local drive="$1"
    for skip in "${SKIP_DRIVES[@]}"; do
        if [[ "$drive" == "$skip" ]]; then
            return 0
        fi
    done
    return 1
}

# First pass to determine max lengths
max_disk_len=0
max_device_len=0
max_status_len=0
while IFS='=' read -r key value; do
    value=$(echo "$value" | tr -d '"')
    if [[ $key == "name" ]]; then
        disk_name=$value
    elif [[ $key == "id" ]]; then
        device_id=$value
    elif [[ $key == "status" ]]; then
        status=$value
        if is_skipped_drive "$disk_name"; then
            continue
        fi
        # Update max lengths
        (( ${#disk_name} > max_disk_len )) && max_disk_len=${#disk_name}
        (( ${#device_id} > max_device_len )) && max_device_len=${#device_id}
        (( ${#status} > max_status_len )) && max_status_len=${#status}
    fi
done < "$DISKS_FILE" || {
    echo "Failed to parse $DISKS_FILE during determining phase, Ensure the file exists and is formatted correctly"
}

# Second pass to print formatted output
while IFS='=' read -r key value; do
    value=$(echo "$value" | tr -d '"')
    if [[ $key == "name" ]]; then
        disk_name=$value
    elif [[ $key == "id" ]]; then
        device_id=$value
    elif [[ $key == "status" ]]; then
        status=$value
        if is_skipped_drive "$disk_name"; then
            continue
        fi
        if [[ -z $disk_name || -z $device_id || -z $status ]]; then
            echo "Missing required disk info name=$disk_name, id=$device_id, status=$status"
        else
            printf "DISK %-${max_disk_len}s  DEVICE %-${max_device_len}s  STATUS %-${max_status_len}s\n" \
                "$disk_name" "$device_id" "$status" | tee -a "$OUTPUT_FILE"
        fi
    fi
done < "$DISKS_FILE" || {
    echo "Failed to parse $DISKS_FILE during creation phase, Ensure the file exists and is formatted correctly"
}

echo "Script is finished and disk assignments created at $OUTPUT_FILE"