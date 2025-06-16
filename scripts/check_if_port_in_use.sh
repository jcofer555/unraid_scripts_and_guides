#!/bin/bash

# This script checks unraids webui ports, docker container ports, ports that VM's use for vnc, and whether VM manager service is running which then uses port 53

# Change this to the port you want to search
PORT_TO_SEARCH="67"

# DON'T CHANGE ANYTHING BELOW

# Check Unraid WebUI ports
UNRAID_HTTP_PORT=$(grep -E "PORT=" /boot/config/ident.cfg | sed -E 's/[^0-9]//g')
UNRAID_HTTPS_PORT=$(grep -E "PORTSSL=" /boot/config/ident.cfg | sed -E 's/[^0-9]//g')

# Check if VM Manager service (libvirt) is running
VM_MANAGER_ACTIVE=$(pgrep -x libvirtd)

# Check docker container ports
RESULT=$(docker ps -q | xargs -I {} docker inspect --format='{{.Name}} {{range $k, $v := .NetworkSettings.Ports}}{{if $v}}{{(index $v 0).HostPort}}{{end}}{{end}}' {} | sed 's/^\///' | awk -v port="$PORT_TO_SEARCH" '$2 == port {print $1}')

# Check VM VNC ports
VM_NAMES=$(virsh list --name)
for VM in $VM_NAMES; do
    VNC_PORT=$(virsh dumpxml "$VM" | grep "graphics type='vnc'" | sed -E "s/.*port='([0-9]+)'.*/\1/")
    
    if [[ -n "$VNC_PORT" && "$PORT_TO_SEARCH" == "$VNC_PORT" ]]; then
        echo "Port $PORT_TO_SEARCH is in use by VM '$VM' for VNC."
        exit 0
    fi
done

# Check matches unraid's webui for http
if [[ "$PORT_TO_SEARCH" == "$UNRAID_HTTP_PORT" ]]; then
    echo "Port $PORT_TO_SEARCH is being used by Unraid's WebUI for HTTP."
# Check matches unraid's webui for https    
elif [[ "$PORT_TO_SEARCH" == "$UNRAID_HTTPS_PORT" ]]; then
    echo "Port $PORT_TO_SEARCH is being used by Unraid's WebUI for HTTPS."
# Check matches because unraid's vm manager service is running    
elif [[ ( "$PORT_TO_SEARCH" == "53" || "$PORT_TO_SEARCH" == "67" ) && -n "$VM_MANAGER_ACTIVE" ]]; then
    echo "Port $PORT_TO_SEARCH is in use by dnsmasq because Unraid's VM Manager service is running."
# Check doesn't match anything that is checked    
elif [[ -z "$RESULT" ]]; then
    echo "Nothing that is checked is using port $PORT_TO_SEARCH."
# Check matches a container    
else
    echo "$RESULT container has port $PORT_TO_SEARCH in use."
fi
