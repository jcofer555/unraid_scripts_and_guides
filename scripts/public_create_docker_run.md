```bash
#!/bin/bash

# Define the container name you want to create a docker run from
CONTAINER_NAME="Krusader"

        #### DON'T CHANGE ANYTHING BELOW HERE ####

# Check if the container exists
if ! docker ps -a --format '{{.Names}}' | grep -q "^$CONTAINER_NAME$"; then
    echo "Error: Container '$CONTAINER_NAME' not found."
    exit 1
fi

# Extract the full configuration in JSON format
CONFIG_JSON=$(docker inspect "$CONTAINER_NAME")

# Parse details using jq (ensure jq is installed)
IMAGE=$(echo "$CONFIG_JSON" | jq -r '.[0].Config.Image')
PORTS=$(echo "$CONFIG_JSON" | jq -r '.[0].HostConfig.PortBindings | to_entries | map("-p " + .key + ":" + .value[0].HostPort) | join("\n")')
VOLUMES=$(echo "$CONFIG_JSON" | jq -r '.[0].Mounts | map("-v " + .Source + ":" + .Destination) | join("\n")')
ENV_VARS=$(echo "$CONFIG_JSON" | jq -r '.[0].Config.Env | map("-e " + .) | join("\n")')

# Use printf to enforce newline spacing
printf "docker run -d\n"
printf "%s\n" "$PORTS"
printf "%s\n" "$VOLUMES"
printf "%s\n" "$ENV_VARS"
printf "%s\n" "$IMAGE"
```
