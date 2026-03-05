```bash
#!/bin/bash
# =============================================================================
# output_tv_and_movies_list
# Generates sorted TV show and movie lists with disk assignment annotations.
# Skill: unified-jonathan-weighted-skill (Bash Module)
# =============================================================================
# DEVIATION NOTE: set -e is NOT used because find_disk returning nothing for
# an unresolved path is non-fatal — the entry is still written with an
# [unknown disk] annotation. set -uo pipefail is used instead.
set -uo pipefail

# =============================================================================
# CONSTANTS
# =============================================================================
readonly SCRIPT_NAME="output_tv_and_movies_list"
readonly WEBHOOK_URL="https://discord.com/api/webhooks/1389372076502028442/CN_Oo7nk1ZpKwT0zzNB7MB77mnxcUXBP3vLI0g3W6pJXbkVz4_E73mLVHElcjFvWSPIF"

readonly TV_DIR="/mnt/user/mymedia/media/tv"
readonly TV_OUTPUT="/mnt/user/data/computer/unraidstuff/tv_shows_list.txt"

readonly MOVIES_ANIMATED_DIR="/mnt/user/mymedia/media/movies/animated"
readonly MOVIES_AZ_DIR="/mnt/user/mymedia/media/movies/a-z"
readonly MOVIES_MARVEL_DIR="/mnt/user/mymedia/media/movies/marvel-dc"
readonly MOVIES_OUTPUT="/mnt/user/data/computer/unraidstuff/movies_list.txt"

readonly MNTUSER="/mnt/user"
readonly OUTPUT_OWNER="jcofer555:users"

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
    send_discord_message "OUTPUT TV AND MOVIES LIST ERROR" "$1" 15158332
}

send_discord_success() {
    send_discord_message "OUTPUT TV AND MOVIES LIST" "$1" 3066993
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
# FIND DISK
# Resolves which physical disk a path lives on by checking /mnt/disk* symlinks.
# Returns disk name (e.g. "disk1") or empty string if not found.
# =============================================================================
find_disk() {
    local rel_path="$1"
    local disk
    for disk in /mnt/disk*; do
        if [ -e "${disk}/${rel_path}" ]; then
            basename "$disk"
            return 0
        fi
    done
    echo ""
}

# =============================================================================
# PROCESS DIRECTORIES
# Scans each source directory for immediate subdirectories, annotates each
# with its physical disk, writes to output file, then sorts in-place.
# =============================================================================
process_dirs() {
    local out="$1"
    shift
    local dirs=("$@")

    > "$out"

    local dir entry rel_path disk
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            log_error "Directory not found, skipping: $dir"
            continue
        fi

        log_info "Scanning: $dir"
        while IFS= read -r entry; do
            rel_path="${dir#${MNTUSER}/}/${entry}"
            disk=$(find_disk "$rel_path")

            if [[ -n "$disk" ]]; then
                echo "${entry} [${disk}]" >> "$out"
            else
                echo "${entry} [unknown disk]" >> "$out"
            fi
        done < <(find "$dir" -mindepth 1 -maxdepth 1 -type d -printf "%f\n" | sort)
    done

    sort -u "$out" -o "$out"

    local final_count
    final_count=$(wc -l < "$out")
    log_info "Saved: $out ($final_count entries after dedup)"

    if chown "$OUTPUT_OWNER" "$out" 2>/dev/null; then
        log_info "Ownership set: $out"
    else
        log_error "Failed to set ownership: $out"
    fi
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

    # --- TV shows ---
    log_section "Processing TV shows"
    process_dirs "$TV_OUTPUT" \
        "$TV_DIR"

    # --- Movies ---
    log_section "Processing Movies"
    process_dirs "$MOVIES_OUTPUT" \
        "$MOVIES_ANIMATED_DIR" \
        "$MOVIES_AZ_DIR" \
        "$MOVIES_MARVEL_DIR"

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
    local tv_count movies_count
    tv_count=$(wc -l < "$TV_OUTPUT" 2>/dev/null || echo "?")
    movies_count=$(wc -l < "$MOVIES_OUTPUT" 2>/dev/null || echo "?")

    if [ -n "$ERRORS" ]; then
        send_discord_error "$(printf 'Errors during run:\n%s\nCheck log: %s' "$ERRORS" "$LOG_FILE")"
    else
        :
    fi
}

main "$@"```
