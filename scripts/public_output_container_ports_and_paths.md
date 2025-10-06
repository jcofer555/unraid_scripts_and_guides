```bash
#!/bin/bash

OUTPUT_FILE="/mnt/user/system/docker_info.log"

#### DON'T CHANGE ANYTHING BELOW HERE ####

echo "Starting outputting of container ports and paths"

TEMPLATE_DIR="/boot/config/plugins/dockerMan/templates-user"

rm -f "$OUTPUT_FILE"

# ---------------------------
# Function to parse template <Config> blocks for Paths or Ports
# ---------------------------
parse_template_configs() {
    local file="$1"
    local type="$2"  # "Path" or "Port"
    local arr_name="$3"
    declare -n arr="$arr_name"

    arr=()
    mapfile -t cfg_lines < <(grep -oP "<Config[^>]*Type=\"$type\"[^>]*>.*?</Config>" "$file")
    for cfg in "${cfg_lines[@]}"; do
        target=$(echo "$cfg" | sed -n 's/.*Target="\([^"]*\)".*/\1/p')
        host=$(echo "$cfg" | sed -n 's/.*>\(.*\)<\/Config>/\1/p' | xargs)
        
        # Remove trailing slash from paths
        [[ "$type" == "Path" ]] && host="${host%/}"
        
        # Append /Mode for ports if Mode exists
        if [[ "$type" == "Port" ]]; then
            mode=$(echo "$cfg" | sed -n 's/.*Mode="\([^"]*\)".*/\1/p')
            [[ -n "$mode" ]] && target="$target/$mode"
        fi

        if [[ -n "$target" && -n "$host" ]]; then
            arr+=("- Container: $target -> Host: $host")
        fi
    done
}

{
    echo "=== Docker Container Info (Paths + Ports with Diff) ==="
    echo "Generated: $(date)"
    echo

    # Get all container names sorted alphabetically
    mapfile -t containers < <(docker ps -a --format '{{.Names}}' | sort -f)

    for container in "${containers[@]}"; do
        echo "Container Name: $container"
        echo "-------------------------------------------------------------------------------"

        # -------------------
        # PATHS (Inspect)
        # -------------------
        echo "Path Mappings (Inspect):"
        mapfile -t inspect_paths < <(
            docker inspect --format='{{range .Mounts}}- Container: {{.Destination}} -> Host: {{.Source}}{{"\n"}}{{end}}' "$container" 2>/dev/null \
                | sed '/^[[:space:]]*$/d' | sort -u
        )
        # Remove trailing slash from inspect paths as well
        for i in "${!inspect_paths[@]}"; do
            inspect_paths[$i]=$(echo "${inspect_paths[$i]}" | sed 's|/$||')
        done

        if [ ${#inspect_paths[@]} -eq 0 ]; then
            echo "  (none)"
        else
            for p in "${inspect_paths[@]}"; do echo "  $p"; done
        fi

        # -------------------
        # PATHS (Template)
        # -------------------
        echo "Path Mappings (Template):"
        template_file="$TEMPLATE_DIR/my-${container}.xml"
        template_paths=()
        if [ -f "$template_file" ]; then
            parse_template_configs "$template_file" "Path" template_paths
        fi
        if [ ${#template_paths[@]} -eq 0 ]; then
            echo "  (none)"
        else
            for p in "${template_paths[@]}"; do echo "  $p"; done
        fi

# -------------------
# Diff Paths
# -------------------
echo "Diff Paths:"
diff_lines=$( { 
    comm -23 <(printf "%s\n" "${inspect_paths[@]}" | sort) <(printf "%s\n" "${template_paths[@]}" | sort) | sed 's/^/  [Only in Inspect] /'
    comm -13 <(printf "%s\n" "${inspect_paths[@]}" | sort) <(printf "%s\n" "${template_paths[@]}" | sort) | sed 's/^/  [Only in Template] /'
} )
if [ -z "$diff_lines" ]; then
    echo "  (none)"
else
    echo "$diff_lines"
fi

        echo

        # -------------------
        # PORTS (Inspect)
        # -------------------
        echo "Port Mappings (Inspect):"
        mapfile -t inspect_ports < <(
            {
                docker inspect --format='{{range $k, $v := .NetworkSettings.Ports}}{{if $v}}- Container: {{$k}} -> Host: {{(index $v 0).HostPort}}{{"\n"}}{{end}}{{end}}' "$container" 2>/dev/null
                docker inspect --format='{{range $k, $v := .HostConfig.PortBindings}}{{if $v}}- Container: {{$k}} -> Host: {{(index $v 0).HostPort}}{{"\n"}}{{end}}{{end}}' "$container" 2>/dev/null
            } | sed '/^[[:space:]]*$/d' | sort -u
        )
        if [ ${#inspect_ports[@]} -eq 0 ]; then
            echo "  (none)"
        else
            for p in "${inspect_ports[@]}"; do echo "  $p"; done
        fi

        # -------------------
        # PORTS (Template)
        # -------------------
        echo "Port Mappings (Template):"
        template_ports=()
        if [ -f "$template_file" ]; then
            parse_template_configs "$template_file" "Port" template_ports
        fi
        if [ ${#template_ports[@]} -eq 0 ]; then
            echo "  (none)"
        else
            for p in "${template_ports[@]}"; do echo "  $p"; done
        fi

# -------------------
# Diff Ports
# -------------------
echo "Diff Ports:"
diff_lines=$( { 
    comm -23 <(printf "%s\n" "${inspect_ports[@]}" | sort) <(printf "%s\n" "${template_ports[@]}" | sort) | sed 's/^/  [Only in Inspect] /'
    comm -13 <(printf "%s\n" "${inspect_ports[@]}" | sort) <(printf "%s\n" "${template_ports[@]}" | sort) | sed 's/^/  [Only in Template] /'
} )
if [ -z "$diff_lines" ]; then
    echo "  (none)"
else
    echo "$diff_lines"
fi

        echo
    done
} > "$OUTPUT_FILE"

echo "Done and saved results to: $OUTPUT_FILE"

```
