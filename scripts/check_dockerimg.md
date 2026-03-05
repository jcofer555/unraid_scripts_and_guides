```bash
#!/bin/bash
# =============================================================================
# check_dockerimg
# Deterministic, atomic, auditable Docker image/volume/container report script.
# Skill: unified-jonathan-weighted-skill (Bash Module)
# =============================================================================
# DEVIATION NOTE: set -e is NOT used globally because docker commands may
# return non-zero on empty result sets which are non-fatal.
# set -uo pipefail is used instead for unbound variable and pipe safety.
set -uo pipefail

# =============================================================================
# CONSTANTS
# =============================================================================
readonly SCRIPT_NAME="check_dockerimg"
readonly WEBHOOK_URL="https://discord.com/api/webhooks/1389372076502028442/CN_Oo7nk1ZpKwT0zzNB7MB77mnxcUXBP3vLI0g3W6pJXbkVz4_E73mLVHElcjFvWSPIF"
readonly LOG_FILE="/mnt/user/data/computer/unraidstuff/userscript_logs/${SCRIPT_NAME}.log"
readonly ARCHIVE_DIR="/mnt/user/data/computer/unraidstuff/userscript_logs/old_logs/${SCRIPT_NAME}"
readonly LOG_OWNER="jcofer555:users"
readonly LOG_RETENTION=7
readonly LOCK_DIR="/tmp/scriptsrunning"
readonly LOCK_FILE="${LOCK_DIR}/${SCRIPT_NAME}"

# =============================================================================
# CONFIGURABLE FLAGS
# Set to "yes" to enable optional cleanup steps.
# These are intentionally not readonly so they can be overridden at runtime
# via environment variable: remove_orphaned_images=yes bash check_dockerimg.sh
# =============================================================================
remove_orphaned_images="${remove_orphaned_images:-no}"
remove_unconnected_volumes="${remove_unconnected_volumes:-no}"

# =============================================================================
# STATE
# =============================================================================
ERRORS=""
START_TIME=$(date +%s)

# =============================================================================
# LOGGING
# =============================================================================
log_info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO]  $*" | tee -a "$LOG_FILE"
}

log_error() {
    local msg="$*"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $msg" | tee -a "$LOG_FILE"
    ERRORS="${ERRORS}${msg}"$'\n'
}

log_section() {
    echo "" | tee -a "$LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [====] $*" | tee -a "$LOG_FILE"
}

log_separator() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [----] -------------------------------------------------------" | tee -a "$LOG_FILE"
}

# =============================================================================
# DISCORD
# =============================================================================
send_discord_message() {
    local title="$1"
    local message="$2"
    local color="$3"
    local json
    json=$(jq -n \
        --arg title   "$title" \
        --arg message "$message" \
        --argjson color "$color" \
        '{embeds: [{title: $title, description: $message, color: $color}]}')
    curl -s -X POST -H "Content-Type: application/json" -d "$json" "$WEBHOOK_URL"
}

send_discord_error() {
    send_discord_message "CHECK DOCKERIMG ERROR" "$1" 15158332
}

send_discord_success() {
    send_discord_message "CHECK DOCKERIMG" "$1" 3066993
}

# =============================================================================
# LOCK
# =============================================================================
acquire_lock() {
    mkdir -p "$LOCK_DIR"
    if [ -f "$LOCK_FILE" ]; then
        send_discord_message "LOCK CONFLICT" "${SCRIPT_NAME} is already running — lock file exists." 15158332
        echo "$(date '+%Y-%m-%d %H:%M:%S') [ABORT] Lock file exists: $LOCK_FILE" >&2
        exit 1
    fi
    touch "$LOCK_FILE"
}

# =============================================================================
# CLEANUP TRAP
# =============================================================================
cleanup() {
    local exit_code=$?
    if [ -f "$LOCK_FILE" ]; then
        if rm -f "$LOCK_FILE"; then
            log_info "Lock file removed: $LOCK_FILE"
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] Failed to remove lock file: $LOCK_FILE" | tee -a "$LOG_FILE"
        fi
    fi
    exit "$exit_code"
}
trap cleanup EXIT SIGTERM SIGINT SIGHUP SIGQUIT

# =============================================================================
# LOG ROTATION (atomic with retention cap)
# =============================================================================
rotate_logs() {
    mkdir -p "$ARCHIVE_DIR"

    local timestamp
    timestamp=$(date +'%m-%d-%Y_%I-%M-%S_%p')
    local archive_log="${ARCHIVE_DIR}/${SCRIPT_NAME}_${timestamp}.log"

    if [ -s "$LOG_FILE" ]; then
        if cp "$LOG_FILE" "$archive_log"; then
            log_info "Archived previous log to: $archive_log"
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') [WARN] Could not archive log: $archive_log" >&2
        fi
    fi

    local num_logs
    num_logs=$(find "$ARCHIVE_DIR" -maxdepth 1 -type f -name "*.log" | wc -l)
    if [ "$num_logs" -gt "$LOG_RETENTION" ]; then
        local excess=$(( num_logs - LOG_RETENTION ))
        find "$ARCHIVE_DIR" -maxdepth 1 -type f -name "*.log" -printf '%T+ %p\n' \
            | sort | head -n "$excess" | awk '{print $2}' \
            | while IFS= read -r old_log; do
                if rm -f "$old_log"; then
                    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO]  Pruned old log: $old_log"
                else
                    echo "$(date '+%Y-%m-%d %H:%M:%S') [WARN]  Could not prune: $old_log"
                fi
            done
    fi

    if chown -R "$LOG_OWNER" "$ARCHIVE_DIR" 2>/dev/null; then
        log_info "Ownership set on archive dir: $ARCHIVE_DIR"
    else
        log_info "Could not set ownership on archive dir (non-fatal): $ARCHIVE_DIR"
    fi
}

# =============================================================================
# DURATION FORMAT
# =============================================================================
format_duration() {
    local duration=$1
    local hours=$(( duration / 3600 ))
    local minutes=$(( (duration % 3600) / 60 ))
    local seconds=$(( duration % 60 ))

    if [ "$hours" -gt 0 ]; then
        echo "$hours hours, $minutes minutes, and $seconds seconds"
    elif [ "$minutes" -gt 0 ]; then
        echo "$minutes minutes and $seconds seconds"
    else
        echo "$seconds seconds"
    fi
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    acquire_lock
    rotate_logs

    > "$LOG_FILE"
    log_info "===== Script started: $(date +'%m-%d-%Y %I:%M:%S %p') ====="
    log_info "remove_orphaned_images=$remove_orphaned_images | remove_unconnected_volumes=$remove_unconnected_volumes"

    # --- Optional: orphaned image cleanup ---
    log_section "Orphaned image cleanup"
    if [ "$remove_orphaned_images" = "yes" ]; then
        log_info "Removing orphaned images..."
        if docker image prune -af 2>&1 | tee -a "$LOG_FILE"; then
            log_info "Orphaned images removed successfully"
        else
            log_error "Failed to remove orphaned images"
        fi
    else
        log_info "Skipping orphaned image cleanup (set remove_orphaned_images=yes to enable)"
    fi

    log_separator

    # --- Optional: unconnected volume cleanup ---
    log_section "Unconnected volume cleanup"
    if [ "$remove_unconnected_volumes" = "yes" ]; then
        log_info "Removing unconnected volumes..."
        if docker volume prune -f 2>&1 | tee -a "$LOG_FILE"; then
            log_info "Unconnected volumes removed successfully"
        else
            log_error "Failed to remove unconnected volumes"
        fi
    else
        log_info "Skipping unconnected volume cleanup (set remove_unconnected_volumes=yes to enable)"
    fi

    # --- Docker system disk usage ---
    log_section "Docker system disk usage"
    if docker system df --format 'There are \t {{.TotalCount}} \t {{.Type}} \t taking up ......{{.Size}}' \
        2>&1 | tee -a "$LOG_FILE"; then
        log_info "Docker system disk usage displayed"
    else
        log_error "docker system df command failed"
    fi

    # --- Container sizes ---
    log_section "Docker container sizes"
    if docker container ls -a \
        --format '{{.Size}} \t Is being taken up by ......... {{.Image}}' \
        2>&1 | tee -a "$LOG_FILE"; then
        log_info "Docker container sizes displayed"
    else
        log_error "docker container ls command failed"
    fi

    # --- Images sorted by size ---
    log_section "Docker images sorted by size"
    # DEVIATION NOTE: pipeline used here for sort/awk transform;
    # pipefail will catch failures in any segment of the pipe.
    if docker image ls --format "{{.Repository}} {{.Size}}" \
        | awk '{if ($2~/GB/) print substr($2,1,length($2)-2)*1000 "MB - " $1; else print $2 " - " $1}' \
        | sed '/^0/d' \
        | sort -nr \
        2>&1 | tee -a "$LOG_FILE"; then
        log_info "Images sorted by size displayed"
    else
        log_error "Failed to list images sorted by size"
    fi

    # --- Volume report ---
    log_section "Docker volume report"
    local volumes
    volumes=$(docker volume ls --format '{{.Name}}' 2>/dev/null)

    if [ -z "$volumes" ]; then
        log_info "No Docker volumes found"
    else
        while IFS= read -r volume; do
            local mountpoint containers size
            mountpoint=$(docker volume inspect --format '{{ .Mountpoint }}' "$volume" 2>/dev/null)
            containers=$(docker ps -a --filter "volume=$volume" --format '{{.Names}}' 2>/dev/null | paste -sd ',' -)
            size=$(du -sh "$mountpoint" 2>/dev/null | cut -f1)
            containers="${containers:-<none>}"
            size="${size:-unknown}"
            log_info "Volume: $volume | Size: $size | Connected to: $containers"
        done <<< "$volumes"
        log_info "Docker volume report complete"
    fi

    # --- Ownership on log ---
    if chown "$LOG_OWNER" "$LOG_FILE" 2>/dev/null; then
        log_info "Ownership set on log: $LOG_FILE"
    else
        log_error "Failed to set ownership on log: $LOG_FILE"
    fi

    # --- Duration ---
    local end_time duration duration_msg
    end_time=$(date +%s)
    duration=$(( end_time - START_TIME ))
    duration_msg=$(format_duration "$duration")
    log_info "Script completed in $duration_msg"

    # --- Final notification ---
    if [ -n "$ERRORS" ]; then
        send_discord_error "$(printf 'Errors during run:\n%s\nCheck log: %s' "$ERRORS" "$LOG_FILE")"
    else
        :
    fi
}

main "$@"```
