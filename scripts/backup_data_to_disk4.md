```bash
#!/bin/bash
# =============================================================================
# backup_data_to_disk4
# Deterministic, atomic, auditable rsync backup script.
# Skill: unified-jonathan-weighted-skill (Bash Module)
# =============================================================================
# DEVIATION NOTE: set -e is NOT used globally because rsync, sync, and du
# may return non-zero on benign conditions.
# set -uo pipefail is used instead for unbound variable and pipe safety.
set -uo pipefail

# =============================================================================
# CONSTANTS
# =============================================================================
readonly SCRIPT_NAME="backup_data_to_disk4"
readonly WEBHOOK_URL="https://discord.com/api/webhooks/1389372076502028442/CN_Oo7nk1ZpKwT0zzNB7MB77mnxcUXBP3vLI0g3W6pJXbkVz4_E73mLVHElcjFvWSPIF"
readonly MOUNT_POINT="/mnt/user/disk4_backups"
readonly RSYNC_SRC="/mnt/user/data/"
readonly RSYNC_DEST="/mnt/user/disk4_backups/data/"
readonly LOG_FILE="/mnt/user/data/computer/unraidstuff/userscript_logs/${SCRIPT_NAME}.log"
readonly ARCHIVE_DIR="/mnt/user/data/computer/unraidstuff/userscript_logs/old_logs/${SCRIPT_NAME}"
readonly LOG_OWNER="jcofer555:users"
readonly LOG_RETENTION=7
readonly LOCK_DIR="/tmp/scriptsrunning"
readonly LOCK_FILE="${LOCK_DIR}/${SCRIPT_NAME}"
readonly POST_SYNC_WAIT=120

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
    send_discord_message "BACKUP DATA TO DISK4 ERROR" "$1" 15158332
}

send_discord_success() {
    send_discord_message "BACKUP DATA TO DISK4" "$1" 3447003
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
# HUMAN READABLE SIZE
# Converts bytes to a human-friendly string with optional +/- sign prefix.
# =============================================================================
human_readable_size() {
    local size_bytes="$1"
    local include_sign="${2:-false}"
    local abs_size=$(( size_bytes < 0 ? -size_bytes : size_bytes ))
    local sign=""

    if [ "$include_sign" = "true" ]; then
        if (( size_bytes > 0 )); then
            sign="+"
        elif (( size_bytes < 0 )); then
            sign="-"
        fi
    fi

    if (( abs_size >= 1024*1024*1024*1024 )); then
        echo "${sign}$(awk "BEGIN {printf \"%.1fTB\", $abs_size / (1024*1024*1024*1024)}")"
    elif (( abs_size >= 1024*1024*1024 )); then
        echo "${sign}$(awk "BEGIN {printf \"%.1fGB\", $abs_size / (1024*1024*1024)}")"
    elif (( abs_size >= 1024*1024 )); then
        echo "${sign}$(awk "BEGIN {printf \"%.1fMB\", $abs_size / (1024*1024)}")"
    elif (( abs_size >= 1024 )); then
        echo "${sign}$(awk "BEGIN {printf \"%.1fKB\", $abs_size / 1024}")"
    else
        echo "${sign}${abs_size}B"
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

    # --- Ensure backup destination exists ---
    log_section "Preparing backup destination"
    if [ ! -d "$MOUNT_POINT" ]; then
        log_info "Backup destination does not exist, creating: $MOUNT_POINT"
        if mkdir -p "$MOUNT_POINT"; then
            log_info "Created backup destination: $MOUNT_POINT"
        else
            log_error "Failed to create backup destination: $MOUNT_POINT"
        fi
    else
        log_info "Backup destination exists: $MOUNT_POINT"
    fi

    if chown -R "$LOG_OWNER" "$MOUNT_POINT"; then
        log_info "Ownership set: $MOUNT_POINT"
    else
        log_error "Failed to set ownership: $MOUNT_POINT"
    fi

    # --- Pre-backup size ---
    local used_before_bytes used_before
    used_before_bytes=$(du -sb "$MOUNT_POINT" 2>/dev/null | awk '{print $1}')
    used_before=$(human_readable_size "$used_before_bytes" "false")
    log_info "Size before backup: $used_before"

    # --- Start notification ---
    log_section "Starting backup"
    send_discord_message "BACKUP DATA TO DISK4" "Backup has started — pre-backup size: ${used_before}" 3066993

    # --- Rsync ---
    log_info "Running rsync: $RSYNC_SRC → $RSYNC_DEST"
    if rsync -a --size-only "$RSYNC_SRC" "$RSYNC_DEST" --delete-after 2>&1 | tee -a "$LOG_FILE"; then
        log_info "Rsync completed successfully"
    else
        log_error "Rsync failed: $RSYNC_SRC → $RSYNC_DEST"
    fi

    # --- Flush and wait ---
    log_section "Flushing buffers"
    if sync; then
        log_info "Filesystem buffers flushed"
    else
        log_error "Failed to flush filesystem buffers"
    fi
    log_info "Waiting ${POST_SYNC_WAIT}s after sync..."
    sleep "$POST_SYNC_WAIT"

    # --- Post-backup size and summary ---
    local used_after_bytes used_after data_changed data_changed_human duration_msg
    used_after_bytes=$(du -sb "$MOUNT_POINT" 2>/dev/null | awk '{print $1}')
    used_after=$(human_readable_size "$used_after_bytes" "false")
    data_changed=$(( used_after_bytes - used_before_bytes ))
    data_changed_human=$(human_readable_size "$data_changed" "true")

    local end_time duration
    end_time=$(date +%s)
    duration=$(( end_time - START_TIME ))
    duration_msg=$(format_duration "$duration")

    log_info "Script completed in $duration_msg"

    local backup_summary
    backup_summary=$(printf 'Backup finished\n**STARTING SIZE:** %s\n**FINISHED SIZE:** %s\n**AMOUNT MOVED:** %s\n**DURATION:** %s' \
        "$used_before" "$used_after" "$data_changed_human" "$duration_msg")

    log_info "$backup_summary"
    send_discord_success "$backup_summary"

    # --- Ownership on log ---
    if chown "$LOG_OWNER" "$LOG_FILE" 2>/dev/null; then
        log_info "Ownership set on log: $LOG_FILE"
    else
        log_error "Failed to set ownership on log: $LOG_FILE"
    fi

    # --- Error report ---
    if [ -n "$ERRORS" ]; then
        send_discord_error "$(printf 'Errors during run:\n%s\nCheck log: %s' "$ERRORS" "$LOG_FILE")"
    fi
}

main "$@"```
