```bash
#!/bin/bash
# =============================================================================
# after_appdata_backup_start_containers
# Deterministic, atomic, auditable container restart script.
# Skill: unified-jonathan-weighted-skill (Bash Module)
# =============================================================================
# DEVIATION NOTE: set -e is NOT used globally because docker/unassigned.devices
# commands may return non-zero on benign conditions (already running, etc.).
# set -uo pipefail is used instead for unbound variable and pipe safety.
set -uo pipefail

# =============================================================================
# CONSTANTS
# =============================================================================
readonly SCRIPT_NAME="after_appdata_backup_start_containers"
readonly WEBHOOK_URL="https://discord.com/api/webhooks/1389372076502028442/CN_Oo7nk1ZpKwT0zzNB7MB77mnxcUXBP3vLI0g3W6pJXbkVz4_E73mLVHElcjFvWSPIF"
readonly DISKID="ata-ST5000LM000-2AN170_WCJ4SG6C"
readonly LOG_FILE="/mnt/user/data/computer/unraidstuff/userscript_logs/${SCRIPT_NAME}.log"
readonly ARCHIVE_DIR="/mnt/user/data/computer/unraidstuff/userscript_logs/old_logs/${SCRIPT_NAME}"
readonly LOG_OWNER="jcofer555:users"
readonly LOCK_DIR="/tmp/scriptsrunning"
readonly LOCK_FILE="${LOCK_DIR}/${SCRIPT_NAME}"
readonly LOG_RETENTION=7
readonly CONNECTIVITY_WAIT_SHORT=10
readonly CONNECTIVITY_WAIT_LONG=30
readonly CONNECTIVITY_WAIT_BASE=60
readonly DETACH_WAIT=30
readonly MAX_RETRIES=3

# DEVIATION NOTE: MARIADB_PASSWORD exported for child process use (docker exec).
export MARIADB_PASSWORD='Scjb8489!'

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
            # Cannot use log_error here safely (may loop); write directly
            echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] Failed to remove lock file: $LOCK_FILE" | tee -a "$LOG_FILE"
        fi
    fi
    exit "$exit_code"
}
trap cleanup EXIT SIGTERM SIGINT SIGHUP SIGQUIT

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
    send_discord_message "CONTAINER START ERROR" "$1" 15158332
}

send_discord_success() {
    send_discord_message "Script Completed" "$1" 3066993
}

# =============================================================================
# LOG ROTATION (atomic with retention cap)
# =============================================================================
rotate_logs() {
    mkdir -p "$ARCHIVE_DIR"

    local timestamp
    timestamp=$(date +'%m-%d-%Y_%I-%M-%S_%p')
    local archive_log="${ARCHIVE_DIR}/${SCRIPT_NAME}_${timestamp}.log"

    # Only archive if a previous log exists and has content
    if [ -s "$LOG_FILE" ]; then
        if cp "$LOG_FILE" "$archive_log"; then
            log_info "Archived previous log to: $archive_log"
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') [WARN] Could not archive log to $archive_log" >&2
        fi
    fi

    # Prune oldest logs beyond retention cap (atomic: list then delete)
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
# CONTAINER ACTIONS
# =============================================================================
start_and_log() {
    local container="$1"
    local action="$2"

    if ! docker inspect "$container" &>/dev/null; then
        log_error "Container does not exist: $container"
        return 1
    fi

    local state
    state=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null)

    case "$action" in
        start)
            if [ "$state" = "running" ]; then
                log_info "Container already running, skipping start: $container"
            else
                if docker start "$container" &>/dev/null; then
                    log_info "Started: $container"
                else
                    log_error "Failed to start: $container"
                fi
            fi
            ;;
        restart)
            if docker restart "$container" &>/dev/null; then
                log_info "Restarted: $container"
            else
                log_error "Failed to restart: $container"
            fi
            ;;
        stop)
            if [ "$state" = "exited" ] || [ "$state" = "dead" ]; then
                log_info "Container already stopped, skipping stop: $container"
            else
                if docker stop "$container" &>/dev/null; then
                    log_info "Stopped: $container"
                else
                    log_error "Failed to stop: $container"
                fi
            fi
            ;;
        *)
            log_error "Unknown action '${action}' for container: $container"
            return 1
            ;;
    esac
}

# =============================================================================
# CONNECTIVITY CHECKS
# =============================================================================
check_container_connectivity() {
    local container="$1"
    local mode="${2:-ping}"

    log_info "Connectivity check — container: $container | mode: $mode"

    case "$mode" in
        ping)
            docker exec "$container" ping -c 1 -W 2 google.com &>/dev/null && return 0
            ;;
        pg_isready)
            local output
            output=$(docker exec "$container" pg_isready -U jcofer555 -h 10.100.10.250 2>/dev/null)
            [[ "$output" == *"accepting connections"* ]] && return 0
            ;;
        mariadb-admin)
            local output
            output=$(docker exec "$container" /usr/bin/mariadb-admin ping \
                -h 10.100.10.250 -P 3506 -u jcofer555 --password="$MARIADB_PASSWORD" 2>/dev/null)
            [[ "$output" == *"mysqld is alive"* ]] && return 0
            ;;
        *)
            log_error "Unknown connectivity mode: $mode"
            return 1
            ;;
    esac

    return 1
}

# =============================================================================
# RETRY RESTART PATTERN
# Explicit state machine: INIT → RESTARTING → CONNECTED | FAILED
# Uses global LAST_CONNECTIVITY_RESULT instead of subshell capture to prevent:
#   - ERRORS variable mutations being lost in a subshell
#   - stdout pollution from log_info/log_error corrupting true/false comparison
# =============================================================================
LAST_CONNECTIVITY_RESULT=false

restart_with_connectivity() {
    local container="$1"
    local mode="$2"
    local wait_between="${3:-$CONNECTIVITY_WAIT_LONG}"
    local initial_wait="${4:-$CONNECTIVITY_WAIT_SHORT}"
    local attempt
    LAST_CONNECTIVITY_RESULT=false

    log_section "Restart loop: $container (mode: $mode)"

    for attempt in $(seq 1 "$MAX_RETRIES"); do
        log_info "Restart attempt $attempt of $MAX_RETRIES: $container"
        start_and_log "$container" "restart"

        log_info "Waiting ${initial_wait}s before connectivity check..."
        sleep "$initial_wait"

        if check_container_connectivity "$container" "$mode"; then
            LAST_CONNECTIVITY_RESULT=true
            log_info "Connectivity established for $container (attempt $attempt)"
            return 0
        fi

        log_info "Connectivity failed on attempt $attempt for $container"
        if [ "$attempt" -lt "$MAX_RETRIES" ]; then
            log_info "Waiting ${wait_between}s before retry..."
            sleep "$wait_between"
        fi
    done

    start_and_log "$container" "stop"
    log_error "Failed connectivity for $container after $MAX_RETRIES attempts — container stopped"
    return 1
}

# =============================================================================
# DRIVE DETACH
# =============================================================================
detach_offsite_drive() {
    log_section "Detaching offsite drive"
    log_info "Waiting ${DETACH_WAIT}s before detach..."
    sleep "$DETACH_WAIT"

    local detach_target
    detach_target=$(realpath "/dev/disk/by-id/${DISKID}" 2>/dev/null | sed 's|.*/||')

    if [ -z "$detach_target" ]; then
        log_error "Could not resolve disk ID to device: $DISKID"
        return 1
    fi

    log_info "Resolved disk target: $detach_target"

    if /usr/local/emhttp/plugins/unassigned.devices/scripts/rc.unassigned 'detach' "$detach_target"; then
        log_info "Offsite drive detached: $detach_target"
    else
        log_error "Failed to detach offsite drive: $detach_target"
        return 1
    fi

    log_info "Waiting ${DETACH_WAIT}s after detach..."
    sleep "$DETACH_WAIT"
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

    # Clear and open log
    > "$LOG_FILE"
    log_info "===== Script started: $(date +'%m-%d-%Y %I:%M:%S %p') ====="

    # --- Detach drive ---
    if ! detach_offsite_drive; then
        log_error "Drive detach failed — aborting"
        exit 1
    fi

    # --- PostgreSQL17 ---
    restart_with_connectivity "postgresql17" "pg_isready" "$CONNECTIVITY_WAIT_LONG" 15

    if $LAST_CONNECTIVITY_RESULT; then
        log_section "Starting PostgreSQL-dependent containers"
        for container in prowlarr autobrr bazarr radarr sonarr; do
            start_and_log "$container" "restart"
        done
    else
        log_info "Skipping PostgreSQL-dependent containers due to postgresql17 failure"
    fi

    # --- Base (VPN/network container) ---
    restart_with_connectivity "base" "ping" "$CONNECTIVITY_WAIT_BASE" "$CONNECTIVITY_WAIT_SHORT"

    if $LAST_CONNECTIVITY_RESULT; then
        log_section "Starting base-dependent containers"
        for container in plex qbittorrent firefox qui; do
            start_and_log "$container" "restart"
        done
    else
        log_info "Skipping plex/qbittorrent/firefox/qui due to base connectivity failure"
    fi

    # --- MariaDB-NC ---
    restart_with_connectivity "mariadb-nc" "mariadb-admin" "$CONNECTIVITY_WAIT_LONG" 15

    if $LAST_CONNECTIVITY_RESULT; then
        log_section "Starting Nextcloud"
        start_and_log "nextcloud" "restart"
    else
        log_info "Skipping nextcloud due to mariadb-nc failure"
    fi

    # --- Standalone containers ---
    log_section "Restarting standalone containers"
    for container in recyclarr tdarr unpackerr; do
        start_and_log "$container" "restart"
    done

    # --- Second-pass plex/qbittorrent/firefox ---
    log_section "Second-pass restart: plex / qbittorrent / firefox"
    for container in plex qbittorrent firefox; do
        start_and_log "$container" "restart"
    done

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

    # --- Final notifications ---
    if [ -n "$ERRORS" ]; then
        send_discord_error "$(printf 'Errors during run:\n%s\nCheck log: %s' "$ERRORS" "$LOG_FILE")"
    else
        :
    fi
}

main "$@"```
