#!/bin/bash

    #### MAKE SURE THIS AND ANY OTHER SCRIPT DOESN'T HAVE THE WORD MOVER IS THE NAME ####

# Variables
QBIT_CONTAINER_NAME="qbittorrent"
QBM_CONTAINER_NAME="qbitmanage"
QBIT_URL="10.100.10.250:8061"
QBIT_USER="YOUR_USER"
TRASH_MOVER_SCRIPT_LOCATION"/mnt/user/appdata/qbittorrent/scripts/mover.py"
DAYS_FROM"0"	# the amount of days you want to target for the pause from the trash guide script
DAYS_TO"2"
export QBIT_PASSWORD="YOUR_PASSWORD"

	#### DON'T CHANGE ANYTHING BELOW HERE UNLESS NEEDING TO ADD EXTRA STOP/STARTS OF CONTAINERS ####

# Mover check
echo "Checking if mover is already running"
if pgrep -f mover &>/dev/null; then
    sleep 15
    pgrep -f mover &>/dev/null && {
	echo "Mover still running after 15s, exiting"
        exit 1
    }
fi
echo "Mover is not currently running, continuing"

# Stopping qbitmanage container
echo "Stopping qbitmanage container"
for container in "$QBM_CONTAINER_NAME"; do
    if docker stop "$container"; then
        echo "Successfully stopped $container"
    else
        echo "Failed to stop $container"
    fi
done

# Stop qbittorrent torrents and run mover
echo "Starting mover script mover.py"
if docker ps -q -f name="$QBIT_CONTAINER_NAME" > /dev/null; then
    python3 "$TRASH_MOVER_SCRIPT_LOCATION" \
        --host "$QBIT_URL" --user "$QBIT_USER" --password "$QBIT_PASSWORD" \
        --cache-mount "$CACHE_MOUNT_POINT" --days_from "$DAYS_FROM" --days_to "$DAYS_TO" || echo "Qbittorrent mover script mover.py failed"
echo "Qbittorent mover script mover.py is finished"
else
    echo "Starting mover"
    mover start || echo "Mover start failed"
    echo "Mover is finished"
fi

# Starting qbitmanage container while qbittorrent is running
if [ "$(docker ps -q -f name="$QBIT_CONTAINER_NAME")" ]; then
echo "Starting to start $QBM_CONTAINER_NAME container while qbittorrent is running"
for container in "$QBM_CONTAINER_NAME"; do
    if docker start "$container"; then
        echo "Successfully started $container"
    else
        echo "Failed to start $container"
    fi
done

else

# Qbittorrent not running, starting qbittorrent container
echo "$QBIT_CONTAINER_NAME not running, starting $QBIT_CONTAINER_NAME"
if docker start "$QBIT_CONTAINER_NAME"; then
    echo "Successfully started $QBIT_CONTAINER_NAME"
else
    echo "Failed to start $QBIT_CONTAINER_NAME"
fi

# Starting qbitmanage container
echo "Starting $QBM_CONTAINER_NAME container"
for container in "$QBM_CONTAINER_NAME"; do
    if docker start "$container"; then
        echo "Successfully started $container"
    else
        echo "Failed to start $container"
    fi
done

fi