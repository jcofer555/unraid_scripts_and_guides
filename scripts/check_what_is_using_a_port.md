```bash
#!/bin/bash

# This script checks if a tcp port is in use

# Change this to the port you want to search
PORT_TO_SEARCH="111"

        #### DON'T CHANGE ANYTHING BELOW HERE ####
        
# === VALIDATE NUMERIC VARIABLE ===
if ! [[ "$PORT_TO_SEARCH" =~ ^[0-9]+$ ]]; then
    echo "❌ Invalid value for PORT_TO_SEARCH: '$SPORT_TO_SEARCH"
    echo "Please enter a numeric value (digits only)"
    exit 1
fi

# === CHECK IF PORT IS LISTENING ===
if ! netstat -ltnp | grep -q ":$PORT_TO_SEARCH "; then
    echo "Port $PORT_TO_SEARCH is not currently in use on the system"
    exit 0
fi

# Flag to track if we found a known match
FOUND_MATCH=false

# Check NFS
NFS_ACTIVE=$(pgrep -x nfsd || pgrep -x rpcbind || pgrep -x mountd)

# Check SMB
SMBD_ACTIVE=$(pgrep -x smbd)

# Check SSH
SSH_PORT=$(grep -E "PORTSSH=" /boot/config/ident.cfg | sed -E 's/[^0-9]//g')
USE_SSH=$(grep -E '^USE_SSH=' /boot/config/ident.cfg | cut -d '=' -f2 | tr -d '"\r\n' | xargs)

# Check Unraid WebUI ports
UNRAID_HTTP_PORT=$(grep -E "PORT=" /boot/config/ident.cfg | sed -E 's/[^0-9]//g')
UNRAID_HTTPS_PORT=$(grep -E "PORTSSL=" /boot/config/ident.cfg | sed -E 's/[^0-9]//g')

# Check if VM Manager service (libvirt) is running
VM_MANAGER_ACTIVE=$(pgrep -x libvirtd)

# Check docker container ports
RESULT=$(netstat -ltnp \
  | grep -q ":$PORT_TO_SEARCH " \
  | sed -n 's|.* \([0-9]\+\)/.*|\1|p' \
  | xargs -r -I{} cat /proc/{}/cgroup \
  | grep '/docker/' \
  | sed -n 's|.*/docker/\([a-f0-9]\{64\}\)|--filter id=\1|p' \
  | xargs -r docker ps --format '{{.Names}}'
)

# Check VM VNC ports
VM_NAMES=$(virsh list --name)
for VM in $VM_NAMES; do
    VNC_PORT=$(virsh dumpxml "$VM" | grep "graphics type='vnc'" | sed -E "s/.*port='([0-9]+)'.*/\1/")
    if [[ -n "$VNC_PORT" && "$PORT_TO_SEARCH" == "$VNC_PORT" ]]; then
        echo "Port $PORT_TO_SEARCH is in use by VM '$VM' for VNC."
        FOUND_MATCH=true
        break
    fi
done

# Check matches Unraid's WebUI for HTTP
if [[ "$PORT_TO_SEARCH" == "$UNRAID_HTTP_PORT" ]]; then
    echo "Port $PORT_TO_SEARCH is being used by Unraid's WebUI for HTTP."
    FOUND_MATCH=true

elif [[ "$PORT_TO_SEARCH" == "$UNRAID_HTTPS_PORT" ]]; then
    echo "Port $PORT_TO_SEARCH is being used by Unraid's WebUI for HTTPS."
    FOUND_MATCH=true

elif [[ "$PORT_TO_SEARCH" == "$SSH_PORT" && "$USE_SSH" == "yes" ]]; then
    echo "Port $PORT_TO_SEARCH is being used by SSH."
    FOUND_MATCH=true

elif [[ ( "$PORT_TO_SEARCH" == "53" || "$PORT_TO_SEARCH" == "67" ) && -n "$VM_MANAGER_ACTIVE" ]]; then
    echo "Port $PORT_TO_SEARCH is in use by dnsmasq because Unraid's VM Manager service is running."
    FOUND_MATCH=true

elif [[ -n "$RESULT" ]]; then
    echo "$RESULT container has port $PORT_TO_SEARCH in use."
    FOUND_MATCH=true

elif [[ -n "$SMBD_ACTIVE" && ( "$PORT_TO_SEARCH" == "139" || "$PORT_TO_SEARCH" == "445" ) ]]; then
    echo "Port $PORT_TO_SEARCH is in use by SMB."
    FOUND_MATCH=true

elif [[ -n "$NFS_ACTIVE" && ( "$PORT_TO_SEARCH" == "2049" || "$PORT_TO_SEARCH" == "111" || "$PORT_TO_SEARCH" == "4045" || "$PORT_TO_SEARCH" -ge 32765 && "$PORT_TO_SEARCH" -le 32768 ) ]]; then
    echo "Port $PORT_TO_SEARCH is in use by NFS."
    FOUND_MATCH=true
fi

# Final fallback if no known match was found
if [[ "$FOUND_MATCH" == false ]]; then
    echo "Port $PORT_TO_SEARCH is actively in use on the system but unable to track what is using it."
fi

```
