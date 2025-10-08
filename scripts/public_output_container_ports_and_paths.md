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
        mode=$(echo "$cfg" | sed -n 's/.*Mode="\([^"]*\)".*/\1/p')

        if [[ "$type" == "Path" ]]; then
            host="${host%/}"
            access=$(echo "$mode" | cut -d',' -f1)
            prop=$(echo "$mode" | cut -d',' -f2)

            if [[ -n "$access" ]]; then
                if [[ "$prop" == "slave" || "$prop" == "shared" ]]; then
                    host="$host ($access,$prop)"
                else
                    host="$host ($access)"
                fi
            fi
        fi

        if [[ "$type" == "Port" ]]; then
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

    mapfile -t containers < <(docker ps -a --format '{{.Names}}' | sort -f)

    for container in "${containers[@]}"; do
        echo "Container Name: $container"
        echo "-------------------------------------------------------------------------------"

        # -------------------
        # PATHS (Inspect)
        # -------------------
        echo "Path Mappings (Inspect):"
        mapfile -t inspect_paths_raw < <(
            docker inspect --format='{{range .Mounts}}- Container: {{.Destination}} -> Host: {{.Source}} ({{if .RW}}rw{{else}}ro{{end}}{{with .Propagation}},{{.}}{{end}}){{"\n"}}{{end}}' "$container" 2>/dev/null \
                | sed '/^[[:space:]]*$/d' | sort -u
        )
        inspect_paths=()
        for line in "${inspect_paths_raw[@]}"; do
            mode=$(echo "$line" | sed -n 's/.*(\(.*\))$/\1/p')
            access=$(echo "$mode" | cut -d',' -f1)
            prop=$(echo "$mode" | cut -d',' -f2)

            if [[ "$mode" == "$access" || "$prop" == "rprivate" || -z "$prop" ]]; then
                clean=$(echo "$line" | sed -E 's/ \((rw|ro)(,[^)]*)?\)/ (\1)/')
                inspect_paths+=("$clean")
            else
                inspect_paths+=("$line")
            fi
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
