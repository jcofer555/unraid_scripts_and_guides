```bash
#!/bin/bash
# =============================================================================
# desktop_appdata_sync_weekly
# Deterministic, atomic, auditable weekly desktop appdata backup via SMB.
# Skill: unified-jonathan-weighted-skill (Bash Module)
# =============================================================================
# DEVIATION NOTE: set -e is NOT used globally because rsync may return
# non-zero on partial transfers which are logged but non-fatal.
# set -uo pipefail is used instead for unbound variable and pipe safety.
set -uo pipefail

# =============================================================================
# CONSTANTS
# =============================================================================
readonly SCRIPT_NAME="desktop_appdata_sync_weekly"
readonly WEBHOOK_URL="https://discord.com/api/webhooks/1389372076502028442/CN_Oo7nk1ZpKwT0zzNB7MB77mnxcUXBP3vLI0g3W6pJXbkVz4_E73mLVHElcjFvWSPIF"
readonly MOUNT_POINT="/mnt/user/data/computer/backups/vms appdata/1-weekly"
readonly DESKTOP_MOUNT="/mnt/remotes/desktopos"
readonly DESKTOP_SMB="//10.100.10.32/os"
readonly DESKTOP_APPDATA="/mnt/remotes/desktopos/Users/Administrator/AppData"
readonly TDARR_SRC="/mnt/remotes/desktopos/Program Files/Tdarr"
readonly TDARR_DEST="/mnt/user/data/computer/tdarr"
readonly UMOUNT_TIMEOUT=45
readonly POST_SYNC_WAIT=120
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
    send_discord_message "DESKTOP APPDATA SYNC WEEKLY ERROR" "$1" 15158332
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
# MOUNT HELPERS
# =============================================================================
mount_desktop() {
    log_section "Mounting desktop OS share"
    if mountpoint -q "$DESKTOP_MOUNT"; then
        log_info "$DESKTOP_MOUNT already mounted, skipping"
        return 0
    fi

    if /usr/local/sbin/rc.unassigned mount "$DESKTOP_SMB" >/dev/null 2>&1; then
        log_info "Mounted: $DESKTOP_SMB"
        sleep 5
        return 0
    fi

    log_error "Failed to mount desktop OS share: $DESKTOP_SMB"
    return 1
}

unmount_desktop() {
    log_section "Unmounting desktop OS share"

    if sync; then
        log_info "Filesystem buffers flushed"
    else
        log_error "Failed to flush filesystem buffers"
    fi

    log_info "Waiting ${POST_SYNC_WAIT}s before unmount..."
    sleep "$POST_SYNC_WAIT"

    log_info "Attempting unmount (timeout: ${UMOUNT_TIMEOUT}s): $DESKTOP_SMB"
    local i
    for (( i=0; i<UMOUNT_TIMEOUT; i++ )); do
        if /usr/local/sbin/rc.unassigned umount "$DESKTOP_SMB" >/dev/null 2>&1; then
            log_info "Unmounted: $DESKTOP_SMB"
            return 0
        fi
        sleep 1
    done

    log_error "Unmount timed out after ${UMOUNT_TIMEOUT}s: $DESKTOP_SMB"
    return 1
}

# =============================================================================
# RSYNC APP BACKUP HELPER
# DEVIATION NOTE: rsync exit code 24 ("some files vanished before transfer")
# is treated as success. This is expected for active apps like Discord whose
# LevelDB/cache files are written and deleted while rsync is running.
# Exit code is captured via a tmpfile because pipefail would otherwise use
# tee's exit code instead of rsync's.
# =============================================================================
backup_app() {
    local source="$1"
    local dest="$2"
    local name="$3"
    local extra_args="${4:-}"

    log_info "Starting backup: $name"

    if [ ! -d "$source" ]; then
        log_info "Source not found, skipping: $name ($source)"
        return 0
    fi

    local rsync_exitfile rsync_exit
    rsync_exitfile=$(mktemp)

    ( rsync -a $extra_args "$source" "$dest" --delete-after 2>&1; echo $? > "$rsync_exitfile" ) \
        | tee -a "$LOG_FILE"

    rsync_exit=$(cat "$rsync_exitfile")
    rm -f "$rsync_exitfile"

    if [ "$rsync_exit" -eq 0 ] || [ "$rsync_exit" -eq 24 ]; then
        [ "$rsync_exit" -eq 24 ] && log_info "Backup completed with vanished files (code 24, non-fatal): $name"
        [ "$rsync_exit" -eq 0  ] && log_info "Backup completed: $name"
        if chown -R "$LOG_OWNER" "$dest"; then
            log_info "Ownership set: $dest"
        else
            log_error "Failed to set ownership: $dest"
        fi
    else
        log_error "Backup failed (rsync exit $rsync_exit): $name ($source → $dest)"
    fi
}

# =============================================================================
# SINGLE FILE BACKUP HELPER
# =============================================================================
backup_file() {
    local src_file="$1"
    local dest_dir="$2"
    local name="$3"

    log_info "Starting file backup: $name"

    if [ ! -f "$src_file" ]; then
        log_info "Source file not found, skipping: $name ($src_file)"
        return 0
    fi

    mkdir -p "$dest_dir"
    local dest_file
    dest_file="${dest_dir}/$(basename "$src_file")"
    rm -f "$dest_file"

    if cp "$src_file" "$dest_dir"; then
        log_info "File backup completed: $name"
        chown -R "$LOG_OWNER" "$dest_dir" 2>/dev/null || true
    else
        log_error "File backup failed: $name ($src_file → $dest_dir)"
    fi
}

# =============================================================================
# TDARR BACKUP
# Full wipe-and-replace since Tdarr config is not rsync-safe (db files).
# Guards rm -rf with explicit non-empty path check.
# =============================================================================
backup_tdarr() {
    log_section "Tdarr backup"

    if [ ! -d "$TDARR_SRC" ]; then
        log_error "Tdarr source not found: $TDARR_SRC"
        return 1
    fi

    if [ -z "$TDARR_DEST" ]; then
        log_error "TDARR_DEST is empty — refusing to rm -rf"
        return 1
    fi

    if [ -d "$TDARR_DEST" ]; then
        log_info "Removing old Tdarr backup: $TDARR_DEST"
        if ! rm -rf "$TDARR_DEST"; then
            log_error "Failed to remove old Tdarr backup: $TDARR_DEST"
            return 1
        fi
    fi

    if rsync -a "$TDARR_SRC/" "$TDARR_DEST/" 2>&1 | tee -a "$LOG_FILE"; then
        log_info "Tdarr backup completed: $TDARR_DEST"
        if chown -R "$LOG_OWNER" "$TDARR_DEST"; then
            log_info "Ownership set: $TDARR_DEST"
        else
            log_error "Failed to set ownership: $TDARR_DEST"
        fi
    else
        log_error "Tdarr rsync failed: $TDARR_SRC → $TDARR_DEST"
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

    # --- Prepare local backup destination ---
    log_section "Preparing local backup destination"
    if [ ! -d "$MOUNT_POINT" ]; then
        log_info "Creating: $MOUNT_POINT"
        if mkdir -p "$MOUNT_POINT"; then
            log_info "Created: $MOUNT_POINT"
        else
            log_error "Failed to create: $MOUNT_POINT"
        fi
    else
        log_info "Exists: $MOUNT_POINT"
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

    # --- Mount desktop share ---
    if ! mount_desktop; then
        send_discord_error "$(printf 'Failed to mount desktop share — aborting.\nCheck log: %s' "$LOG_FILE")"
        exit 1
    fi

    if ! mountpoint -q "$DESKTOP_MOUNT"; then
        log_error "Mount point not active after mount attempt: $DESKTOP_MOUNT"
        send_discord_error "$(printf 'Desktop mount not active — aborting.\nCheck log: %s' "$LOG_FILE")"
        exit 1
    fi

    # --- App backups ---
    log_section "Starting app backups"

    backup_app \
        "${DESKTOP_APPDATA}/Roaming/discord/" \
        "${MOUNT_POINT}/discord backup/" \
        "Discord" \
        "--exclude=Network/Cookies --exclude=Network/Cookies-journal"

    log_info "Cleaning Discord cache directories"
    for cache_dir in Cache "Code Cache" component_crx_cache DawnCache DawnGraphiteCache DawnWebGPUCache GPUCache; do
        rm -rf "${MOUNT_POINT}/discord backup/${cache_dir}" 2>/dev/null || true
    done
    log_info "Discord cache directories cleaned"

    backup_app \
        "${DESKTOP_APPDATA}/Local/Microsoft/Edge/User Data/" \
        "${MOUNT_POINT}/edge backup/" \
        "Edge" \
        "--exclude=Default/Network/Cookies --exclude=Default/Network/Cookies-journal"

    backup_app \
        "${DESKTOP_APPDATA}/Roaming/Emby-Theater/" \
        "${MOUNT_POINT}/emby backup/" \
        "Emby"

    backup_app \
        "${DESKTOP_APPDATA}/Roaming/Mozilla/Firefox/" \
        "${MOUNT_POINT}/firefox backup/" \
        "Firefox" \
        "--exclude=Profiles/hh7efm9i.default-release-1/parent.lock"

    backup_app \
        "${DESKTOP_APPDATA}/Roaming/Notepad++/" \
        "${MOUNT_POINT}/notepadplusplus backup/" \
        "Notepad++"

    backup_app \
        "${DESKTOP_APPDATA}/Local/Plex/" \
        "${MOUNT_POINT}/plex backup/" \
        "Plex"

    backup_app \
        "${DESKTOP_APPDATA}/Roaming/vlc/" \
        "${MOUNT_POINT}/vlc backup/" \
        "VLC"

backup_app \
    "${DESKTOP_APPDATA}/Roaming/RustDesk/config/" \
    "${MOUNT_POINT}/rustdesk backup/" \
    "RustDesk"

    # --- Tdarr backup ---
    backup_tdarr

    backup_file \
        "${DESKTOP_APPDATA}/Local/Xanasoft/Sandboxie-Plus/Sandboxie-Plus.ini" \
        "${MOUNT_POINT}/sandboxie backup/" \
        "Sandboxie"

    # --- Unmount ---
    unmount_desktop

    # --- Post-backup size and summary ---
    local used_after_bytes used_after data_changed data_changed_human
    used_after_bytes=$(du -sb "$MOUNT_POINT" 2>/dev/null | awk '{print $1}')
    used_after=$(human_readable_size "$used_after_bytes" "false")
    data_changed=$(( used_after_bytes - used_before_bytes ))
    data_changed_human=$(human_readable_size "$data_changed" "true")

    local end_time duration duration_msg
    end_time=$(date +%s)
    duration=$(( end_time - START_TIME ))
    duration_msg=$(format_duration "$duration")
    log_info "Script completed in $duration_msg"

    log_info "$backup_summary"

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
