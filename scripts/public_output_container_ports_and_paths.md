```bash
#!/bin/bash

# Variables
OUTPUT_FILE="/mnt/user/system/docker_info.log"

#### DON'T CHANGE ANYTHING BELOW HERE ####

# Remove old file
rm -f "$OUTPUT_FILE"

{
    echo "=== Docker Container Info (Paths + Ports) ==="
    echo "Generated: $(date)"
    echo

    # Get containers sorted by name
    for container in $(docker ps -a --format '{{.Names}}' | sort); do
        echo "Container: $container"
        echo "----------------------------------------"

        # Path mappings
        echo "Path Mappings:"
        docker inspect --format='{{range .Mounts}}- Container: {{.Destination}}  |  Host: {{.Source}}{{"\n"}}{{end}}' "$container"

        # Port mappings
        echo "Port Mappings:"
        {
            # Active (running)
            docker inspect --format='{{range $k, $v := .NetworkSettings.Ports}}{{if $v}}- Container: {{$k}}  ->  Host: {{(index $v 0).HostPort}}{{"\n"}}{{end}}{{end}}' "$container"
            # Configured (even if stopped)
            docker inspect --format='{{range $k, $v := .HostConfig.PortBindings}}{{if $v}}- Container: {{$k}}  ->  Host: {{(index $v 0).HostPort}}{{"\n"}}{{end}}{{end}}' "$container"
        } | sort -u

        echo
    done
} > "$OUTPUT_FILE"

echo "Saved results to: $OUTPUT_FILE"

```
