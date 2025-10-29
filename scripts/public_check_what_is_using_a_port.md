```bash
#!/bin/bash

# VARIABLES
PORT_TO_SEARCH=443

#### DON'T CHANGE ANYTHING BELOW HERE ####

# --- Validation ---
if ! [[ "$PORT_TO_SEARCH" =~ ^[0-9]+$ ]]; then
  echo "❌ Invalid PORT_TO_SEARCH: '$PORT_TO_SEARCH' (must be numeric)"
  exit 1
fi

# --- Choose ss or netstat ---
if command -v ss >/dev/null 2>&1; then
  NETSTAT_CMD="ss -ltnp"
else
  NETSTAT_CMD="netstat -ltnp"
fi

# --- Confirm port is listening ---
if ! $NETSTAT_CMD 2>/dev/null | grep -q ":$PORT_TO_SEARCH "; then
  echo "Port $PORT_TO_SEARCH is not currently in use."
  exit 0
fi

VERBOSE=true
FOUND_MATCH=false

# ==========================================================
#  1. Check Docker containers
# ==========================================================
if command -v docker >/dev/null 2>&1; then
  while IFS= read -r line; do
    ID=$(echo "$line" | awk '{print $1}')
    NAME=$(echo "$line" | awk '{print $2}')
    IMAGE=$(echo "$line" | awk '{print $3}')
    PORTS=$(docker port "$ID" 2>/dev/null | awk '{print $NF}')
    if echo "$PORTS" | grep -q ":$PORT_TO_SEARCH\$"; then
      echo "✅ Port $PORT_TO_SEARCH is in use by container: $NAME "
      FOUND_MATCH=true
      break
    fi
  done < <(docker ps --format '{{.ID}} {{.Names}} {{.Image}}')
fi

# ==========================================================
#  2. Check VMs
# ==========================================================
if [[ "$FOUND_MATCH" == false ]] && command -v virsh >/dev/null 2>&1; then
  for VM in $(virsh list --name); do
    XML=$(virsh dumpxml "$VM" 2>/dev/null)

    # Extract standard VNC console port
    VNC_PORT=$(echo "$XML" | grep -E "graphics type='vnc'" | sed -E "s/.*port='([0-9]+)'.*/\1/")

    # Extract websocket (noVNC) port if present
    WS_PORT=$(echo "$XML" | grep -E "websocket='[0-9]+'" | sed -E "s/.*websocket='([0-9]+)'.*/\1/")

    if [[ -n "$VNC_PORT" && "$PORT_TO_SEARCH" == "$VNC_PORT" ]]; then
      echo "✅ Port $PORT_TO_SEARCH is in use by VM $VM"
      FOUND_MATCH=true
      break
    elif [[ -n "$WS_PORT" && "$PORT_TO_SEARCH" == "$WS_PORT" ]]; then
      echo "✅ Port $PORT_TO_SEARCH is in use by VM $VM"
      FOUND_MATCH=true
      break
    fi
  done
fi

# ==========================================================
#  3. Check Unraid built-in services
# ==========================================================
NFS_ACTIVE=$(pgrep -x nfsd || pgrep -x rpcbind || pgrep -x mountd)
SMBD_ACTIVE=$(pgrep -x smbd)
SSH_PORT=$(grep -E "^PORTSSH=" /boot/config/ident.cfg | sed -E 's/[^0-9]//g')
SSHD_ACTIVE=$(pgrep -x sshd)
UNRAID_HTTP_PORT=$(grep -E "^PORT=" /boot/config/ident.cfg | sed -E 's/[^0-9]//g')
UNRAID_HTTPS_PORT=$(grep -E "^PORTSSL=" /boot/config/ident.cfg | sed -E 's/[^0-9]//g')
VM_MANAGER_ACTIVE=$(pgrep -x libvirtd)

if [[ "$PORT_TO_SEARCH" == "$UNRAID_HTTP_PORT" ]]; then
  echo "✅ Port $PORT_TO_SEARCH is Unraid WebUI (HTTP)."; FOUND_MATCH=true
elif [[ "$PORT_TO_SEARCH" == "$UNRAID_HTTPS_PORT" ]]; then
  echo "✅ Port $PORT_TO_SEARCH is Unraid WebUI (HTTPS)."; FOUND_MATCH=true
elif [[ "$PORT_TO_SEARCH" == "$SSH_PORT" && -n "$SSHD_ACTIVE" ]]; then
  echo "✅ Port $PORT_TO_SEARCH is SSH (sshd)."; FOUND_MATCH=true
elif [[ ( "$PORT_TO_SEARCH" == "53" || "$PORT_TO_SEARCH" == "67" ) && -n "$VM_MANAGER_ACTIVE" ]]; then
  echo "✅ Port $PORT_TO_SEARCH is dnsmasq (VM Manager)."; FOUND_MATCH=true
elif [[ -n "$SMBD_ACTIVE" && ( "$PORT_TO_SEARCH" == "139" || "$PORT_TO_SEARCH" == "445" ) ]]; then
  echo "✅ Port $PORT_TO_SEARCH is SMB (smbd)."; FOUND_MATCH=true
elif [[ -n "$NFS_ACTIVE" && ( "$PORT_TO_SEARCH" == "2049" || "$PORT_TO_SEARCH" == "111" || "$PORT_TO_SEARCH" == "4045" || ( "$PORT_TO_SEARCH" -ge 32765 && "$PORT_TO_SEARCH" -le 32768 ) ) ]]; then
  echo "✅ Port $PORT_TO_SEARCH is NFS (nfsd/rpcbind)."; FOUND_MATCH=true
fi

# ==========================================================
#  4. Verbose fallback (raw process info)
# ==========================================================
if [[ "$FOUND_MATCH" == false ]]; then
  echo "⚠️  Port $PORT_TO_SEARCH is in use but not matched to any known service, container, or vm"
  if $VERBOSE; then
    echo
    echo "=== Detailed process info ==="
    $NETSTAT_CMD 2>/dev/null | grep ":$PORT_TO_SEARCH "
    echo
    echo "=== PIDs using the port ==="
    $NETSTAT_CMD 2>/dev/null | awk -v port=":$PORT_TO_SEARCH" '$4 ~ port {split($7,a,"/"); print a[1]}' | xargs -r ps -p
  fi
fi

```
