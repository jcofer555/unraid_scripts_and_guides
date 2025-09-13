```bash
#!/bin/bash

# CHANGE THESE
QBITTORRENT_CONTAINER_NAME="qbittorrent"
VPN_CONTAINER_NAME="base"
CONF_PATH="/mnt/user/appdata/qbittorrent/config/qBittorrent.conf"

        #### DON'T CHANGE ANYTHING BELOW HERE ####

# Extract forwarded port
FORWARDED_PORT=$(docker logs "$VPN_CONTAINER_NAME" 2>/dev/null | awk '/Forwarded port/ {gsub(/[^0-9]/, "", $NF); print $NF}' | tail -n 1)
echo "Forwarded Port: $FORWARDED_PORT"

# Exit if forwarded port wasn't found
if [[ -z "$FORWARDED_PORT" ]]; then
    echo "Error: Forwarded port not found in logs. Script aborted..."
    exit 1
fi

# Extract current session port from qbittorrent.conf
CURRENT_PORT=$(awk -F '=' '/^Session\\Port=/ {print $2}' "$CONF_PATH")
echo "Current Port: $CURRENT_PORT"

# Compare ports and exit if they match
if (( FORWARDED_PORT == CURRENT_PORT )); then
    echo "No change needed. Ports match. Script aborted..."
    exit 0
fi

echo "Change detected, updating qBittorrent.conf with port $FORWARDED_PORT"

# Stop qBittorrent
docker stop "$QBITTORRENT_CONTAINER_NAME" > /dev/null 2>&1
echo "$QBITTORRENT_CONTAINER_NAME has stopped and now waiting 5 seconds before continuing"
sleep 5

# Update qbittorrent.conf with forwarded port
sed -i "s/^Session\\\\Port=[0-9]\\+/Session\\\\Port=$FORWARDED_PORT/" "$CONF_PATH"
echo "qbittorrent.conf session port updated to port $FORWARDED_PORT"

# Start qBittorrent
docker start "$QBITTORRENT_CONTAINER_NAME" > /dev/null 2>&1
echo "$QBITTORRENT_CONTAINER_NAME started"
echo "Script finished..."```
