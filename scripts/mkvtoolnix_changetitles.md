```bash
#!/bin/bash
# =============================================================================
# mkvtoolnix_changetitles
# Replicates the inner container script's traverse logic directly via
# docker exec per-file, adding processed-file tracking on top.
# Set REPROCESS_ALL=yes to reprocess all files regardless of tracking.
# Skill: unified-jonathan-weighted-skill (Bash Module)
# =============================================================================
# DEVIATION NOTE: set -e is NOT used because mkvpropedit returns non-zero
# on warnings that are non-fatal. set -uo pipefail is used instead.
set -uo pipefail

# =============================================================================
# USER CONFIGURATION
# =============================================================================
REPROCESS_ALL="no"   # Set to "yes" to reprocess all files, ignoring the processed list

# =============================================================================
# CONSTANTS
# =============================================================================
readonly SCRIPT_NAME="mkvtoolnix_changetitles"
readonly WEBHOOK_URL="https://discord.com/api/webhooks/1389372076502028442/CN_Oo7nk1ZpKwT0zzNB7MB77mnxcUXBP3vLI0g3W6pJXbkVz4_E73mLVHElcjFvWSPIF"
readonly DOCKER_CONTAINER="mkvtoolnix"
readonly MEDIA_PATH="/mnt/user/mymedia/media"
readonly MEDIA_PATH_INNER="/mymedia/media"
readonly PROCESSED_LIST="/mnt/user/data/computer/unraidstuff/mkvtoolnix_processed.txt"
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
TOTAL=0
PROCESSED=0
SKIPPED=0
FAILED=0

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
    send_discord_message "MKVTOOLNIX CHANGETITLES ERROR" "$1" 15158332
}

send_discord_success() {
    send_discord_message "MKVTOOLNIX CHANGETITLES" "$1" 3066993
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
# PROCESSED LIST HELPERS
# Keyed on the host-side absolute path.
# =============================================================================
is_processed() {
    grep -qxF "$1" "$PROCESSED_LIST" 2>/dev/null
}

mark_processed() {
    echo "$1" >> "$PROCESSED_LIST"
}

# =============================================================================
# TRAVERSE
# Mirrors the inner script's traverse() exactly:
#   - loop *.mkv files in the current dir
#   - recurse into subdirectories
# But wraps each mkvpropedit call with skip/track logic.
# Uses the HOST-side path for traversal (so bash glob works normally),
# then maps to the container path only for the mkvpropedit call by
# replacing MEDIA_PATH with MEDIA_PATH_INNER via simple string replacement.
# This is safe because we are constructing the container path from a known
# host path that already starts with MEDIA_PATH — no prefix-stripping needed.
# =============================================================================
traverse() {
    local host_dir="$1"

    # Process .mkv files in this directory
    for host_file in "$host_dir"/*.mkv; do
        [[ -f "$host_file" ]] || continue

        (( TOTAL++ )) || true

        if [ "$REPROCESS_ALL" = "no" ] && is_processed "$host_file"; then
            log_info "Skip: $(basename "$host_file")"
            (( SKIPPED++ )) || true
            continue
        fi

        local filename
        filename=$(basename "$host_file" .mkv)

        # Map host path → container path
        # Replace only the leading MEDIA_PATH prefix with MEDIA_PATH_INNER
        local container_file="${MEDIA_PATH_INNER}${host_file#${MEDIA_PATH}}"

        log_info "Processing: $(basename "$host_file")"

        if docker exec -i "$DOCKER_CONTAINER" \
            mkvpropedit "$container_file" --edit info --set "title=$filename" \
            2>&1 | tee -a "$LOG_FILE"; then
            mark_processed "$host_file"
            (( PROCESSED++ )) || true
        else
            log_error "Failed: $(basename "$host_file")"
            (( FAILED++ )) || true
        fi
    done

    # Recurse into subdirectories
    # Strip trailing slash before recursing so paths never accumulate double
    # slashes — the glob pattern "*/" always appends a slash to dir names.
    for host_subdir in "$host_dir"/*/; do
        [[ -d "$host_subdir" ]] || continue
        traverse "${host_subdir%/}"
    done
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    mkdir -p "$(dirname "$LOG_FILE")"
    acquire_lock
    rotate_logs

    > "$LOG_FILE"
    log_info "===== Script started: $(date +'%m-%d-%Y %I:%M:%S %p') ====="
    log_info "REPROCESS_ALL=$REPROCESS_ALL"
    log_info "Media path: $MEDIA_PATH"
    log_info "Processed list: $PROCESSED_LIST"

    # --- Validate REPROCESS_ALL ---
    if [[ "$REPROCESS_ALL" != "yes" && "$REPROCESS_ALL" != "no" ]]; then
        log_error "Invalid value for REPROCESS_ALL: '$REPROCESS_ALL' — must be 'yes' or 'no'"
        send_discord_error "Invalid REPROCESS_ALL value. Check log: $LOG_FILE"
        exit 1
    fi

    # --- Preflight: verify container is running ---
    log_section "Preflight check"
    if ! docker ps -q -f name="$DOCKER_CONTAINER" | grep -q .; then
        log_error "Container not running: $DOCKER_CONTAINER"
        send_discord_error "$(printf 'Container not running: %s\nCheck log: %s' "$DOCKER_CONTAINER" "$LOG_FILE")"
        exit 1
    fi
    log_info "Container is running: $DOCKER_CONTAINER"

    # --- Verify media path exists on host ---
    if [[ ! -d "$MEDIA_PATH" ]]; then
        log_error "Media path not found: $MEDIA_PATH"
        send_discord_error "$(printf 'Media path not found: %s\nCheck log: %s' "$MEDIA_PATH" "$LOG_FILE")"
        exit 1
    fi

    # --- Handle REPROCESS_ALL=yes ---
    if [ "$REPROCESS_ALL" = "yes" ]; then
        log_info "REPROCESS_ALL=yes — clearing processed list"
        > "$PROCESSED_LIST"
    fi

    mkdir -p "$(dirname "$PROCESSED_LIST")"
    touch "$PROCESSED_LIST"

    # --- Traverse and process ---
    log_section "Traversing: $MEDIA_PATH"
    traverse "$MEDIA_PATH"

    log_section "Run summary"
    log_info "Total MKV files found: $TOTAL"
    log_info "Processed this run:    $PROCESSED"
    log_info "Skipped (done before): $SKIPPED"
    log_info "Failed:                $FAILED"

    # --- Ownership ---
    chown "$LOG_OWNER" "$PROCESSED_LIST" 2>/dev/null || true

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
        send_discord_success "$(printf 'MKVToolNix title update complete in %s.\nProcessed: %s | Skipped: %s | Failed: %s\nLog: %s' \
            "$duration_msg" "$PROCESSED" "$SKIPPED" "$FAILED" "$LOG_FILE")"
    fi
}

main "$@"```
