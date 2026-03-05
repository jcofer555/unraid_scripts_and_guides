```bash
#!/bin/bash
# =============================================================================
# backup_to_cloud
# Deterministic, atomic, auditable rclone cloud backup script.
# Skill: unified-jonathan-weighted-skill (Bash Module)
# =============================================================================
# DEVIATION NOTE: set -e is NOT used globally because rclone may return
# non-zero on partial transfers which are logged but non-fatal.
# set -uo pipefail is used instead for unbound variable and pipe safety.
set -uo pipefail

# =============================================================================
# CONSTANTS
# =============================================================================
readonly SCRIPT_NAME="backup_to_cloud"
readonly WEBHOOK_URL="https://discord.com/api/webhooks/1389372076502028442/CN_Oo7nk1ZpKwT0zzNB7MB77mnxcUXBP3vLI0g3W6pJXbkVz4_E73mLVHElcjFvWSPIF"
readonly LOG_FILE="/mnt/user/data/computer/unraidstuff/userscript_logs/${SCRIPT_NAME}.log"
readonly ARCHIVE_DIR="/mnt/user/data/computer/unraidstuff/userscript_logs/old_logs/${SCRIPT_NAME}"
readonly LOG_OWNER="jcofer555:users"
readonly LOG_RETENTION=7
readonly LOCK_DIR="/tmp/scriptsrunning"
readonly LOCK_FILE="${LOCK_DIR}/${SCRIPT_NAME}"
readonly RCLONE_BOX_REMOTE="boxcrypt:"
readonly RCLONE_B2_REMOTE="b2crypt:"
readonly BOX_MAX_SIZE="249M"
readonly B2_SRC="/mnt/user/data"
readonly B2_EXCLUDE="computer/unraidstuff/userscript_logs/**"

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
    send_discord_message "BACKUP TO CLOUD ERROR" "$1" 15158332
}

send_discord_success() {
    send_discord_message "BACKUP TO CLOUD" "$1" 3066993
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
# PREFLIGHT: VERIFY RCLONE REMOTES
# Called after function definitions to avoid "command not found" on error paths.
# =============================================================================
check_remote() {
    local remote="$1"
    if ! rclone listremotes | grep -q "^${remote}"; then
        log_error "Required rclone remote not found: $remote"
        send_discord_error "Remote '${remote}' not configured in rclone — aborting."
        exit 1
    fi
    log_info "Rclone remote verified: $remote"
}

# =============================================================================
# RCLONE BACKUP HELPER
# =============================================================================
backup_rclone() {
    local src="$1"
    local dest="$2"
    local label="$3"
    local extra_args="${4:-}"

    log_info "Starting sync: $label ($src → $dest)"

    # DEVIATION NOTE: rclone exit code 9 (directory not found) and partial
    # transfers (exit 23/24) are treated as errors but do not abort the script.
    if rclone sync "$src" "$dest" --delete-after $extra_args 2>&1 | tee -a "$LOG_FILE"; then
        log_info "Sync completed: $label"
    else
        log_error "Sync failed: $label ($src → $dest)"
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

    # --- Preflight remote checks ---
    log_section "Preflight: verifying rclone remotes"
    check_remote "$RCLONE_BOX_REMOTE"
    check_remote "$RCLONE_B2_REMOTE"

    # --- Box backups (encrypted, 249M file size cap) ---
    log_section "Starting encrypted Box backups"

    backup_rclone "/mnt/user/data/computer/networking"                          "${RCLONE_BOX_REMOTE}networking"           "networking"           "--max-size ${BOX_MAX_SIZE}"
    backup_rclone "/mnt/user/data/computer/scripts"                             "${RCLONE_BOX_REMOTE}scripts"              "scripts"              "--max-size ${BOX_MAX_SIZE}"
    backup_rclone "/mnt/user/data/documentation"                                "${RCLONE_BOX_REMOTE}documentation"        "documentation"        "--max-size ${BOX_MAX_SIZE}"
    backup_rclone "/mnt/user/data/media - other"                                "${RCLONE_BOX_REMOTE}media - other"        "media - other"        "--max-size ${BOX_MAX_SIZE}"
    backup_rclone "/mnt/user/data/computer/drivers"                             "${RCLONE_BOX_REMOTE}drivers"              "drivers"              "--max-size ${BOX_MAX_SIZE}"
    backup_rclone "/mnt/user/data/computer/software"                            "${RCLONE_BOX_REMOTE}software"             "software"             "--max-size ${BOX_MAX_SIZE}"
    backup_rclone "/mnt/user/data/computer/unraidstuff"                         "${RCLONE_BOX_REMOTE}unraid stuff"         "unraid stuff"         "--max-size ${BOX_MAX_SIZE}"
    backup_rclone "/mnt/user/data/computer/mega stuff"                          "${RCLONE_BOX_REMOTE}mega stuff"           "mega stuff"           "--max-size ${BOX_MAX_SIZE}"
    backup_rclone "/mnt/user/data/computer/r00t stuff"                          "${RCLONE_BOX_REMOTE}r00t stuff"           "r00t stuff"           "--max-size ${BOX_MAX_SIZE}"
    backup_rclone "/mnt/user/data/nextcloud/jcofer555/files/opnsense-backup"    "${RCLONE_BOX_REMOTE}opnsense"             "opnsense"             "--max-size ${BOX_MAX_SIZE}"
    backup_rclone "/mnt/user/data/computer/backups/unraid_containers"           "${RCLONE_BOX_REMOTE}unraid_containers"    "unraid_containers"    "--max-size ${BOX_MAX_SIZE}"
    backup_rclone "/mnt/user/data/computer/backups/unraid_flash"                "${RCLONE_BOX_REMOTE}unraid_flash"         "unraid_flash"         "--max-size ${BOX_MAX_SIZE}"
    backup_rclone "/mnt/user/data/computer/backups/nasunraid_flash"             "${RCLONE_BOX_REMOTE}nasunraid_flash"      "nasunraid_flash"      "--max-size ${BOX_MAX_SIZE}"
    backup_rclone "/mnt/user/data/computer/backups/testunraid_flash"            "${RCLONE_BOX_REMOTE}testunraid_flash"     "testunraid_flash"     "--max-size ${BOX_MAX_SIZE}"
    backup_rclone "/mnt/user/data/computer/backups/backupunraid_flash"          "${RCLONE_BOX_REMOTE}backupunraid_flash"   "backupunraid_flash"   "--max-size ${BOX_MAX_SIZE}"

    # --- Backblaze backup (encrypted, full data, fast-list) ---
    log_section "Starting encrypted Backblaze backup"

    backup_rclone "$B2_SRC" "$RCLONE_B2_REMOTE" "backblaze-data" "--fast-list --exclude ${B2_EXCLUDE}"

    # --- Duration ---
    local end_time duration duration_msg
    end_time=$(date +%s)
    duration=$(( end_time - START_TIME ))
    duration_msg=$(format_duration "$duration")
    log_info "Script completed in $duration_msg"

    # --- Ownership on log ---
    if chown "$LOG_OWNER" "$LOG_FILE" 2>/dev/null; then
        log_info "Ownership set on log: $LOG_FILE"
    else
        log_error "Failed to set ownership on log: $LOG_FILE"
    fi

    # --- Final notification ---
    if [ -n "$ERRORS" ]; then
        send_discord_error "$(printf 'Errors during run:\n%s\nCheck log: %s' "$ERRORS" "$LOG_FILE")"
    else
        :
    fi
}

main "$@"```
