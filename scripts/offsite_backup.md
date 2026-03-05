```bash
#!/bin/bash
# =============================================================================
# offsite_backup
# Deterministic, atomic, auditable offsite USB drive backup script.
# Skill: unified-jonathan-weighted-skill (Bash Module)
# =============================================================================
# DEVIATION NOTE: set -e is NOT used globally because rsync may return
# non-zero on vanished files (code 24) and umount retries are expected to
# fail until the drive is ready. set -uo pipefail is used instead.
set -uo pipefail

# =============================================================================
# CONSTANTS
# =============================================================================
readonly SCRIPT_NAME="offsite_backup"
readonly WEBHOOK_URL="https://discord.com/api/webhooks/1389372076502028442/CN_Oo7nk1ZpKwT0zzNB7MB77mnxcUXBP3vLI0g3W6pJXbkVz4_E73mLVHElcjFvWSPIF"
readonly ATTACHID="ST5000LM000-2AN170_WCJ4SG6C"
readonly DISKID="ata-ST5000LM000-2AN170_WCJ4SG6C"
readonly PARTID="ata-ST5000LM000-2AN170_WCJ4SG6C-part1"
readonly MOUNT_POINT="/mnt/disks/offsite"
readonly SOURCE_DIR="/mnt/user/data"
readonly MOUNT_PERMS="775"
readonly ATTACH_WAIT=5
readonly MOUNT_WAIT=5
readonly POST_SYNC_WAIT=120
readonly DETACH_WAIT=5
readonly UMOUNT_TIMEOUT=45
readonly LOG_FILE="/mnt/user/data/computer/unraidstuff/userscript_logs/${SCRIPT_NAME}.log"
readonly ARCHIVE_DIR="/mnt/user/data/computer/unraidstuff/userscript_logs/old_logs/${SCRIPT_NAME}"
readonly LOG_OWNER="jcofer555:users"
readonly LOG_RETENTION=7
readonly LOCK_DIR="/tmp/scriptsrunning"
readonly LOCK_FILE="${LOCK_DIR}/${SCRIPT_NAME}"
readonly RC_UNASSIGNED="/usr/local/emhttp/plugins/unassigned.devices/scripts/rc.unassigned"

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
    send_discord_message "OFFSITE BACKUP ERROR" "$1" 15158332
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
# =============================================================================
human_readable_size() {
    local size_bytes="$1"
    local include_sign="${2:-false}"
    local abs_size=$(( size_bytes < 0 ? -size_bytes : size_bytes ))
    local sign=""

    if [ "$include_sign" = "true" ]; then
        if (( size_bytes > 0 )); then sign="+"; elif (( size_bytes < 0 )); then sign="-"; fi
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
# ATTACH DRIVE
# =============================================================================
attach_drive() {
    log_section "Attaching offsite drive: $ATTACHID"
    if "$RC_UNASSIGNED" attach "$ATTACHID" >/dev/null 2>&1; then
        log_info "Drive attached successfully"
        log_info "Waiting ${ATTACH_WAIT}s for device to settle..."
        sleep "$ATTACH_WAIT"
        return 0
    fi
    log_error "Failed to attach drive: $ATTACHID"
    return 1
}

# =============================================================================
# MOUNT DRIVE
# =============================================================================
mount_drive() {
    log_section "Mounting offsite drive"

    mkdir -p "$MOUNT_POINT"

    if mountpoint -q "$MOUNT_POINT"; then
        log_info "$MOUNT_POINT already mounted, skipping"
        return 0
    fi

    if /sbin/mount -t xfs -o rw,relatime,nodev,nosuid \
        "/dev/disk/by-id/${PARTID}" "$MOUNT_POINT" >/dev/null 2>&1; then
        log_info "Mounted: $MOUNT_POINT"
        log_info "Waiting ${MOUNT_WAIT}s for mount to settle..."
        sleep "$MOUNT_WAIT"
        return 0
    fi

    log_error "Failed to mount offsite drive: /dev/disk/by-id/${PARTID} → $MOUNT_POINT"
    return 1
}

# =============================================================================
# RUN RSYNC
# DEVIATION NOTE: rsync exit code 24 (vanished files) is treated as success —
# same pattern as desktop_appdata_sync. Exit code captured via tmpfile to
# avoid pipefail using tee's exit code instead of rsync's.
# =============================================================================
run_rsync() {
    log_section "Running rsync: $SOURCE_DIR → $MOUNT_POINT/data"

    mkdir -p "$MOUNT_POINT/data"

    local rsync_exitfile rsync_exit
    rsync_exitfile=$(mktemp)

    ( rsync -a --size-only "$SOURCE_DIR/" "$MOUNT_POINT/data" --delete-after 2>&1; \
        echo $? > "$rsync_exitfile" ) \
        | tee -a "$LOG_FILE"

    rsync_exit=$(cat "$rsync_exitfile")
    rm -f "$rsync_exitfile"

    if [ "$rsync_exit" -eq 0 ] || [ "$rsync_exit" -eq 24 ]; then
        [ "$rsync_exit" -eq 24 ] && log_info "Rsync completed with vanished files (code 24, non-fatal)"
        [ "$rsync_exit" -eq 0  ] && log_info "Rsync completed successfully"
    else
        log_error "Rsync failed (exit $rsync_exit)"
        return 1
    fi
}

# =============================================================================
# UNMOUNT DRIVE
# Retries umount up to UMOUNT_TIMEOUT seconds before giving up.
# DEVIATION NOTE: umount returns non-zero while drive is busy — retries are
# expected and non-fatal until timeout is reached.
# =============================================================================
unmount_drive() {
    log_section "Unmounting offsite drive"

    if sync; then
        log_info "Filesystem buffers flushed"
    else
        log_error "Failed to flush filesystem buffers"
    fi

    log_info "Waiting ${POST_SYNC_WAIT}s before unmount..."
    sleep "$POST_SYNC_WAIT"

    log_info "Attempting unmount (timeout: ${UMOUNT_TIMEOUT}s): $MOUNT_POINT"
    local i
    for (( i=UMOUNT_TIMEOUT; i>0; i-- )); do
        if /sbin/umount "$MOUNT_POINT" 2>/dev/null; then
            log_info "Unmounted: $MOUNT_POINT"
            sleep 5
            return 0
        fi
        sleep 1
    done

    log_error "Unmount timed out after ${UMOUNT_TIMEOUT}s: $MOUNT_POINT"
    return 1
}

# =============================================================================
# DETACH DRIVE
# Resolves the real device name from the disk-by-id symlink before detaching.
# =============================================================================
detach_drive() {
    log_section "Detaching offsite drive"

    local real_dev
    real_dev=$(realpath "/dev/disk/by-id/${DISKID}" 2>/dev/null | sed 's|.*/||')

    if [ -z "$real_dev" ]; then
        log_error "Could not resolve real device for: /dev/disk/by-id/${DISKID}"
        return 1
    fi

    log_info "Detaching device: $real_dev"
    if "$RC_UNASSIGNED" detach "$real_dev" >/dev/null 2>&1; then
        log_info "Drive detached successfully"
        sleep "$DETACH_WAIT"
        return 0
    fi

    log_error "Failed to detach drive: $real_dev"
    return 1
}

# =============================================================================
# REMOVE MOUNT POINT DIRECTORY
# Only removes if not currently mounted (safety check).
# =============================================================================
remove_mountpoint() {
    if mountpoint -q "$MOUNT_POINT"; then
        log_error "Mount point still active — refusing to remove: $MOUNT_POINT"
        return 1
    fi

    log_info "Removing mount point directory: $MOUNT_POINT"
    if rm -rf "$MOUNT_POINT"; then
        log_info "Mount point directory removed: $MOUNT_POINT"
    else
        log_error "Failed to remove mount point directory: $MOUNT_POINT"
        return 1
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
    log_info "Drive: $ATTACHID | Mount: $MOUNT_POINT | Source: $SOURCE_DIR"

    # --- Attach ---
    if ! attach_drive; then
        send_discord_error "$(printf 'Failed to attach offsite drive.\nCheck log: %s' "$LOG_FILE")"
        exit 1
    fi

    # --- Mount ---
    if ! mount_drive; then
        send_discord_error "$(printf 'Failed to mount offsite drive.\nCheck log: %s' "$LOG_FILE")"
        exit 1
    fi

    # --- Set permissions on mount point ---
    log_section "Setting mount point permissions"
    if chown -R "$LOG_OWNER" "$MOUNT_POINT"; then
        log_info "Ownership set: $MOUNT_POINT"
    else
        log_error "Failed to set ownership: $MOUNT_POINT"
    fi
    if chmod -R "$MOUNT_PERMS" "$MOUNT_POINT"; then
        log_info "Permissions set to $MOUNT_PERMS: $MOUNT_POINT"
    else
        log_error "Failed to set permissions: $MOUNT_POINT"
    fi

    # --- Pre-backup size ---
    local used_before_bytes used_before
    used_before_bytes=$(du -sb "$MOUNT_POINT" 2>/dev/null | awk '{print $1}')
    used_before=$(human_readable_size "$used_before_bytes" "false")
    log_info "Size before backup: $used_before"

    send_discord_message "OFFSITE BACKUP" "$(printf 'Backup has started — pre-backup size: %s' "$used_before")" 3066993

    # --- Confirm mount is live before proceeding ---
    if ! mountpoint -q "$MOUNT_POINT"; then
        log_error "Mount point not active: $MOUNT_POINT — aborting backup"
        send_discord_error "$(printf 'Mount point not active: %s\nCheck log: %s' "$MOUNT_POINT" "$LOG_FILE")"
        exit 1
    fi

    # --- Run rsync ---
    if ! run_rsync; then
        log_error "Rsync failed — backup may be incomplete"
    fi

    # --- Post-backup size (must be captured BEFORE unmount/remove_mountpoint wipes the dir) ---
    local used_after_bytes used_after data_changed data_changed_human
    used_after_bytes=$(du -sb "$MOUNT_POINT" 2>/dev/null | awk '{print $1}')
    used_after=$(human_readable_size "$used_after_bytes" "false")
    data_changed=$(( used_after_bytes - used_before_bytes ))
    data_changed_human=$(human_readable_size "$data_changed" "true")
    log_info "Size after backup: $used_after (change: $data_changed_human)"

    # --- Unmount ---
    if ! unmount_drive; then
        send_discord_error "$(printf 'Failed to unmount offsite drive.\nCheck log: %s' "$LOG_FILE")"
        exit 1
    fi

    # --- Detach ---
    if ! detach_drive; then
        log_error "Drive detach failed — drive may need manual intervention"
    fi

    # --- Remove mount point directory ---
    remove_mountpoint || true

    # --- Summary ---
    local end_time duration duration_msg
    end_time=$(date +%s)
    duration=$(( end_time - START_TIME ))
    duration_msg=$(format_duration "$duration")
    log_info "Script completed in $duration_msg"

    local backup_summary
    backup_summary=$(printf 'Backup finished\n**STARTING SIZE:** %s\n**FINISHED SIZE:** %s\n**AMOUNT MOVED:** %s\n**DURATION:** %s' \
        "$used_before" "$used_after" "$data_changed_human" "$duration_msg")

    log_info "$backup_summary"
    send_discord_message "OFFSITE BACKUP" "$backup_summary" 3447003

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
