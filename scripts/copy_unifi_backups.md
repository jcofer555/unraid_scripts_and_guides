```bash
#!/bin/bash
# =============================================================================
# copy_unifi_backups
# Deterministic, atomic, auditable UniFi backup copy script via SSH/SCP.
# Skill: unified-jonathan-weighted-skill (Bash Module)
# =============================================================================
# DEVIATION NOTE: set -e is NOT used globally because sshpass/scp may return
# non-zero on individual file failures which are logged but non-fatal.
# set -uo pipefail is used instead for unbound variable and pipe safety.
set -uo pipefail

# =============================================================================
# CONSTANTS
# =============================================================================
readonly SCRIPT_NAME="copy_unifi_backups"
readonly WEBHOOK_URL="https://discord.com/api/webhooks/1389372076502028442/CN_Oo7nk1ZpKwT0zzNB7MB77mnxcUXBP3vLI0g3W6pJXbkVz4_E73mLVHElcjFvWSPIF"
readonly REMOTE_USER="root"
readonly REMOTE_SERVER="10.100.10.1"
readonly REMOTE_DIR="/usr/lib/unifi/data/backup/autobackup"
readonly LOCAL_PATH="/mnt/user/data/computer/networking/jons unifi/cloud ultra/autobackups/"
readonly BACKUP_COUNT=15
readonly SSH_OPTS="-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
readonly LOG_FILE="/mnt/user/data/computer/unraidstuff/userscript_logs/${SCRIPT_NAME}.log"
readonly ARCHIVE_DIR="/mnt/user/data/computer/unraidstuff/userscript_logs/old_logs/${SCRIPT_NAME}"
readonly LOG_OWNER="jcofer555:users"
readonly LOG_RETENTION=7
readonly LOCK_DIR="/tmp/scriptsrunning"
readonly LOCK_FILE="${LOCK_DIR}/${SCRIPT_NAME}"

# DEVIATION NOTE: REMOTE_PASSWORD not marked readonly as sshpass requires it
# as a plain variable. Exported only for sshpass child process scope.
REMOTE_PASSWORD="Scjb8489!Scjb8489!"

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
    send_discord_message "COPY UNIFI BACKUPS ERROR" "$1" 15158332
}

send_discord_success() {
    send_discord_message "COPY UNIFI BACKUPS" "$1" 3066993
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
# PREPARE LOCAL DIRECTORY
# Guards rm -rf with an explicit non-empty path check before wiping.
# =============================================================================
prepare_local_dir() {
    log_section "Preparing local backup directory: $LOCAL_PATH"

    if [ -z "$LOCAL_PATH" ]; then
        log_error "LOCAL_PATH is empty — refusing to rm -rf"
        exit 1
    fi

    if rm -rf "$LOCAL_PATH"; then
        log_info "Cleared: $LOCAL_PATH"
    else
        log_error "Failed to clear: $LOCAL_PATH"
    fi

    if mkdir -p "$LOCAL_PATH"; then
        log_info "Created: $LOCAL_PATH"
    else
        log_error "Failed to create: $LOCAL_PATH"
        exit 1
    fi

    if chown -R "$LOG_OWNER" "$LOCAL_PATH"; then
        log_info "Ownership set: $LOCAL_PATH"
    else
        log_error "Failed to set ownership: $LOCAL_PATH"
    fi
}

# =============================================================================
# FETCH REMOTE FILE LIST
# Returns newest N backup filenames via null-delimited SSH output.
# Uses a tmpfile to avoid subshell scoping issues with mapfile.
# =============================================================================
fetch_remote_file_list() {
    local -n _result=$1
    local tmpfile tmpfile_filtered
    tmpfile=$(mktemp)
    tmpfile_filtered=$(mktemp)

    log_info "Retrieving latest ${BACKUP_COUNT} backup files from ${REMOTE_USER}@${REMOTE_SERVER}:${REMOTE_DIR}"

    # DEVIATION NOTE: stderr is redirected to the log separately (2>> LOG_FILE)
    # rather than merged into stdout (2>&1). SSH/sshpass emit advisory warnings
    # (known hosts, PQ key exchange) on stderr that must not pollute the stdout
    # file list. Additionally, stdout is filtered through grep to keep only
    # absolute paths (lines starting with '/'), stripping any warnings that
    # leak into stdout before mapfile processes them as filenames.
    if sshpass -p "${REMOTE_PASSWORD}" ssh $SSH_OPTS \
        "${REMOTE_USER}@${REMOTE_SERVER}" \
        "find ${REMOTE_DIR} -type f -name 'autobackup*' -print0 | xargs -0 ls -t | head -n ${BACKUP_COUNT}" \
        > "$tmpfile" 2>> "$LOG_FILE"; then

        grep -E '^/' "$tmpfile" > "$tmpfile_filtered" || true
        mapfile -t _result < "$tmpfile_filtered"
        log_info "Retrieved ${#_result[@]} file(s) from remote"
    else
        log_error "Failed to retrieve file list from ${REMOTE_USER}@${REMOTE_SERVER}:${REMOTE_DIR}"
        _result=()
    fi

    rm -f "$tmpfile" "$tmpfile_filtered"
}

# =============================================================================
# COPY REMOTE FILES
# =============================================================================
copy_backup_files() {
    local -n _files=$1
    local copied=0
    local failed=0

    log_section "Copying ${#_files[@]} file(s) from remote to: $LOCAL_PATH"

    for file in "${_files[@]}"; do
        log_info "Copying: $file"
        if sshpass -p "${REMOTE_PASSWORD}" scp $SSH_OPTS \
            "${REMOTE_USER}@${REMOTE_SERVER}:${file}" "${LOCAL_PATH}" 2>> "$LOG_FILE"; then
            log_info "Copied: $(basename "$file")"
            (( copied++ )) || true
        else
            log_error "Failed to copy: $file"
            (( failed++ )) || true
        fi
    done

    log_info "Copy complete — succeeded: $copied | failed: $failed"
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    acquire_lock
    rotate_logs

    > "$LOG_FILE"
    log_info "===== Script started: $(date +'%m-%d-%Y %I:%M:%S %p') ====="
    log_info "Remote: ${REMOTE_USER}@${REMOTE_SERVER}:${REMOTE_DIR}"
    log_info "Local:  ${LOCAL_PATH}"

    # --- Prepare local directory ---
    prepare_local_dir

    # --- Fetch remote file list ---
    declare -a backup_files=()
    fetch_remote_file_list backup_files

    if [ ${#backup_files[@]} -eq 0 ]; then
        log_error "No backup files found on remote — nothing to copy"
        send_discord_error "$(printf 'No backup files found on remote.\nCheck log: %s' "$LOG_FILE")"
        exit 1
    fi

    # --- Copy files ---
    copy_backup_files backup_files

    # --- Final ownership pass on local dir ---
    log_section "Final ownership pass"
    if chown -R "$LOG_OWNER" "$LOCAL_PATH"; then
        log_info "Final ownership set: $LOCAL_PATH"
    else
        log_error "Failed final ownership set: $LOCAL_PATH"
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
