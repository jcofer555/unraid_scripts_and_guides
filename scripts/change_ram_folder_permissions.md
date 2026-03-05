```bash
#!/bin/bash
# =============================================================================
# change_ram_folder_permissions
# Deterministic, atomic, auditable Emby transcode RAM dir permission fix.
# Skill: unified-jonathan-weighted-skill (Bash Module)
# =============================================================================
# DEVIATION NOTE: set -e is NOT used globally because chown/chmod may return
# non-zero on permission edge cases that should be logged but not abort.
# set -uo pipefail is used instead for unbound variable and pipe safety.
set -uo pipefail

# =============================================================================
# CONSTANTS
# =============================================================================
readonly SCRIPT_NAME="change_ram_folder_permissions"
readonly WEBHOOK_URL="https://discord.com/api/webhooks/1389372076502028442/CN_Oo7nk1ZpKwT0zzNB7MB77mnxcUXBP3vLI0g3W6pJXbkVz4_E73mLVHElcjFvWSPIF"
readonly EMBY_MOUNT_POINT="/dev/shm/emby"
readonly EMBY_OWNER="jcofer555:users"
readonly EMBY_PERMS="777"
readonly LOG_FILE="/mnt/user/data/computer/unraidstuff/userscript_logs/${SCRIPT_NAME}.log"
readonly ARCHIVE_DIR="/mnt/user/data/computer/unraidstuff/userscript_logs/old_logs/${SCRIPT_NAME}"
readonly LOG_OWNER="jcofer555:users"
readonly LOG_RETENTION=7
readonly LOCK_DIR="/tmp/scriptsrunning"
readonly LOCK_FILE="${LOCK_DIR}/${SCRIPT_NAME}"

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
    send_discord_message "EMBY TRANSCODE FIX ERROR" "$1" 15158332
}

send_discord_success() {
    send_discord_message "EMBY TRANSCODE FIX" "$1" 3066993
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

    # --- Ensure Emby RAM dir exists ---
    log_section "Preparing Emby transcode dir: $EMBY_MOUNT_POINT"

    if [ ! -d "$EMBY_MOUNT_POINT" ]; then
        log_info "Directory does not exist, creating: $EMBY_MOUNT_POINT"
        if mkdir -p "$EMBY_MOUNT_POINT"; then
            log_info "Created: $EMBY_MOUNT_POINT"
        else
            log_error "Failed to create: $EMBY_MOUNT_POINT"
        fi
    else
        log_info "Directory exists: $EMBY_MOUNT_POINT"
    fi

    # --- Set ownership ---
    # DEVIATION NOTE: chown -R used for recursive ownership on first pass
    # to catch any subdirs, then a non-recursive chown on the dir itself
    # is redundant — consolidated into a single -R call.
    log_info "Setting ownership: $EMBY_MOUNT_POINT → $EMBY_OWNER"
    if chown -R "$EMBY_OWNER" "$EMBY_MOUNT_POINT"; then
        log_info "Ownership set: $EMBY_MOUNT_POINT"
    else
        log_error "Failed to set ownership: $EMBY_MOUNT_POINT"
    fi

    # --- Set permissions ---
    log_info "Setting permissions: $EMBY_MOUNT_POINT → $EMBY_PERMS"
    if chmod "$EMBY_PERMS" "$EMBY_MOUNT_POINT"; then
        log_info "Permissions set to $EMBY_PERMS: $EMBY_MOUNT_POINT"
    else
        log_error "Failed to set permissions on: $EMBY_MOUNT_POINT"
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
