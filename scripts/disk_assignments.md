```bash
#!/bin/bash
# =============================================================================
# disk_assignments
# Deterministic, atomic, auditable Unraid disk assignment report script.
# Skill: unified-jonathan-weighted-skill (Bash Module)
# =============================================================================
# DEVIATION NOTE: set -e is NOT used globally because the while-read loop
# parsing disks.ini may encounter blank/comment lines that produce non-zero
# case matches, which are non-fatal. set -uo pipefail is used instead.
set -uo pipefail

# =============================================================================
# CONSTANTS
# =============================================================================
readonly SCRIPT_NAME="disk_assignments"
readonly WEBHOOK_URL="https://discord.com/api/webhooks/1389372076502028442/CN_Oo7nk1ZpKwT0zzNB7MB77mnxcUXBP3vLI0g3W6pJXbkVz4_E73mLVHElcjFvWSPIF"
readonly DISKS_FILE="/var/local/emhttp/disks.ini"
readonly OUTPUT_FILE="/boot/config/disk_assignments.txt"
readonly MOUNT_POINT="/mnt/user/data/computer/unraidstuff"
readonly LOG_FILE="/mnt/user/data/computer/unraidstuff/userscript_logs/${SCRIPT_NAME}.log"
readonly ARCHIVE_DIR="/mnt/user/data/computer/unraidstuff/userscript_logs/old_logs/${SCRIPT_NAME}"
readonly LOG_OWNER="jcofer555:users"
readonly LOG_RETENTION=7
readonly LOCK_DIR="/tmp/scriptsrunning"
readonly LOCK_FILE="${LOCK_DIR}/${SCRIPT_NAME}"

readonly -a SKIP_DRIVES=(
    "parity"
    "parity2"
)

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
    send_discord_message "DISK ASSIGNMENTS ERROR" "$1" 15158332
}

send_discord_success() {
    send_discord_message "DISK ASSIGNMENTS" "$1" 3066993
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
# SKIP DRIVE CHECK
# Returns 0 (true) if the drive name is in the SKIP_DRIVES list.
# =============================================================================
is_skipped_drive() {
    local drive="$1"
    local skip
    for skip in "${SKIP_DRIVES[@]}"; do
        [[ "$drive" == "$skip" ]] && return 0
    done
    return 1
}

# =============================================================================
# PARSE AND WRITE DISK ASSIGNMENTS
# Two-pass approach: first pass determines column widths for aligned output.
# Uses parameter substitution instead of a tr subshell to strip quotes.
# State variables (disk_name, device_id, status) are reset on each 'name' key
# so stanzas never bleed into each other.
# =============================================================================
parse_and_write_disk_assignments() {
    log_section "Parsing: $DISKS_FILE"

    # --- First pass: determine max column widths ---
    local max_disk_len=0 max_device_len=0 max_status_len=0
    local disk_name="" device_id="" status=""

    while IFS='=' read -r key value; do
        # Strip surrounding quotes using parameter substitution (no subshell)
        value="${value//\"/}"
        case "$key" in
            name)
                disk_name="$value"
                device_id=""
                status=""
                ;;
            id)
                device_id="$value"
                ;;
            status)
                status="$value"
                is_skipped_drive "$disk_name" && continue
                (( ${#disk_name}  > max_disk_len   )) && max_disk_len=${#disk_name}
                (( ${#device_id}  > max_device_len )) && max_device_len=${#device_id}
                (( ${#status}     > max_status_len )) && max_status_len=${#status}
                ;;
        esac
    done < "$DISKS_FILE" || {
        log_error "Failed to parse $DISKS_FILE during column-width pass"
        return 1
    }

    log_info "Column widths — disk: $max_disk_len | device: $max_device_len | status: $max_status_len"

    # --- Write output file header ---
    echo "Disk Assignments as of $(date +'%m-%d-%Y %I:%M:%S %p')" > "$OUTPUT_FILE"

    # --- Second pass: write formatted rows ---
    local row_count=0
    disk_name="" ; device_id="" ; status=""

    while IFS='=' read -r key value; do
        value="${value//\"/}"
        case "$key" in
            name)
                disk_name="$value"
                device_id=""
                status=""
                ;;
            id)
                device_id="$value"
                ;;
            status)
                status="$value"
                is_skipped_drive "$disk_name" && continue

                if [[ -z "$disk_name" || -z "$device_id" || -z "$status" ]]; then
                    log_error "Incomplete disk entry — name='$disk_name' id='$device_id' status='$status'"
                    continue
                fi

                local row
                row=$(printf "DISK %-${max_disk_len}s  DEVICE %-${max_device_len}s  STATUS %-${max_status_len}s" \
                    "$disk_name" "$device_id" "$status")
                echo "$row" >> "$OUTPUT_FILE"
                log_info "$row"
                (( row_count++ )) || true
                ;;
        esac
    done < "$DISKS_FILE" || {
        log_error "Failed to parse $DISKS_FILE during output pass"
        return 1
    }

    log_info "Wrote $row_count disk assignment row(s) to: $OUTPUT_FILE"
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    acquire_lock
    rotate_logs

    > "$LOG_FILE"
    log_info "===== Script started: $(date +'%m-%d-%Y %I:%M:%S %p') ====="

    # --- Preflight: verify disks.ini exists ---
    log_section "Preflight checks"
    if [[ ! -f "$DISKS_FILE" ]]; then
        log_error "disks.ini not found: $DISKS_FILE"
        send_discord_error "disks.ini not found: $DISKS_FILE — aborting."
        exit 1
    fi
    log_info "disks.ini found: $DISKS_FILE"

    # --- Parse and generate report ---
    if ! parse_and_write_disk_assignments; then
        log_error "Disk assignment report generation failed — output may be incomplete"
    fi

    # --- Copy report to data dir ---
    log_section "Copying report to: $MOUNT_POINT"
    local dest_file="${MOUNT_POINT}/${SCRIPT_NAME}.txt"
    if cp "$OUTPUT_FILE" "$dest_file"; then
        log_info "Report copied to: $dest_file"
    else
        log_error "Failed to copy report to: $dest_file"
    fi

    # --- Ownership on output and mount point ---
    if chown "$LOG_OWNER" "$dest_file" 2>/dev/null; then
        log_info "Ownership set: $dest_file"
    else
        log_error "Failed to set ownership: $dest_file"
    fi

    if chown "$LOG_OWNER" "$MOUNT_POINT" 2>/dev/null; then
        log_info "Ownership set: $MOUNT_POINT"
    else
        log_error "Failed to set ownership: $MOUNT_POINT"
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
