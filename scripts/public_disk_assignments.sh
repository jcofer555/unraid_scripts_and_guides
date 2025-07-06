#!/bin/bash

# Variables
DISKS_FILE="/var/local/emhttp/disks.ini"
OUTPUT_FILE="/boot/config/disk_assignments.txt"
SKIP_DRIVES=("parity" "parity2")

# Checking if disks.ini exists
echo "Checking if disks.ini exists"
if [[ ! -f "$DISKS_FILE" ]]; then
    echo "Error, $DISKS_FILE doesn't exist, exiting"
    send_discord_error "Error, disks.ini file doesn't exist, exiting"
    exit 1
fi

# Function to check for skipped drives
echo "Disk Assignments as of $(date +"%m-%d-%Y_%I-%M-%S_%p")" > "$OUTPUT_FILE"
is_skipped_drive() {
    local drive="$1"
    for skip in "${SKIP_DRIVES[@]}"; do
        if [[ "$drive" == "$skip" ]]; then
            return 0
        fi
    done
    return 1
}

# Creating disk_assignment.txt
echo "Starting of creating disk_assignment.txt on the flash drive"
disk_name=""
device_id=""
status=""
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
            echo "DISK $disk_name  DEVICE $device_id  STATUS $status" >> "$OUTPUT_FILE"
			echo "DISK $disk_name  DEVICE $device_id  STATUS $status"
        fi
    fi
done < "$DISKS_FILE" || {
    echo "Failed to parse $DISKS_FILE, Ensure the file exists and is formatted correctly"
}