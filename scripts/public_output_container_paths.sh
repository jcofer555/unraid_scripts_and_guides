#!/bin/bash
# Variables
OUTPUT_FILE="/mnt/user/appdata/docker_paths.log"
    
    #### Don't change anything below here ####

{
    echo "=== Docker Container Path Assignments (Running) ==="
    echo

    # Running containers (via docker inspect)
    for container in $(docker ps -a --format '{{.Names}}'); do
        echo "Container: $container"
        docker inspect --format='{{range .Mounts}}- Container: {{.Destination}}  |  Host: {{.Source}}{{"\n"}}{{end}}' "$container"
        echo
    done
} > "$OUTPUT_FILE"

echo "Saved results to: $OUTPUT_FILE"
