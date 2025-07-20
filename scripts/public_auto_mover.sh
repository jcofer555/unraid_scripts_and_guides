#!/bin/bash

# Variables
POOL_NAME="cache"
THRESHOLD=1

		#### DON'T CHANGE ANYTHING BELOW HERE ####

# Mover check
echo "Checking if mover is already running"
if pgrep -x mover &>/dev/null; then
    echo "Mover is running, waiting 15 seconds and checking again for safety"
    sleep 15
    pgrep -f mover &>/dev/null && {
        echo "Mover still running after 15s, exiting"
        exit 1
    }
fi
echo "Mover is not currently running, continuing"

# Check disk usage threshold
echo "Checking if /mnt/${POOL_NAME} is over threshold of ${THRESHOLD}%"
USED=$(df -h --si "/mnt/${POOL_NAME}" | awk 'NR==2 {print $5}' | sed 's/%//')
[ "$USED" -le "$THRESHOLD" ] && {
    echo "/mnt/${POOL_NAME} is ${USED}% full, under threshold of ${THRESHOLD}%, exiting"
    exit 1
}
echo "/mnt/${POOL_NAME} is over threshold of ${THRESHOLD}% so starting mover"

# Start mover
mover start

# After mover dusk usage check
USED2=$(df -h --si "/mnt/${POOL_NAME}" | awk 'NR==2 {print $5}' | sed 's/%//')
echo "/mnt/${POOL_NAME} is now ${USED2}% full"