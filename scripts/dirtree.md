```bash
#!/bin/bash
# =============================================================================
# dirtree
# Deterministic, atomic, auditable directory tree report generation script.
# Skill: unified-jonathan-weighted-skill (Bash Module)
# =============================================================================
# DEVIATION NOTE: set -e is NOT used globally because pip install and python3
# may return non-zero on warnings that do not indicate fatal failures.
# set -uo pipefail is used instead for unbound variable and pipe safety.
#
# NOTE: Original script used #!/bin/sh but contained bash-specific syntax
# (local, $'\n', array [@] expansion). Corrected to #!/bin/bash.
set -uo pipefail

# =============================================================================
# CONSTANTS
# =============================================================================
readonly SCRIPT_NAME="dirtree"
readonly WEBHOOK_URL="https://discord.com/api/webhooks/1389372076502028442/CN_Oo7nk1ZpKwT0zzNB7MB77mnxcUXBP3vLI0g3W6pJXbkVz4_E73mLVHElcjFvWSPIF"
readonly MOUNT_POINT="/mnt/user/data/computer/unraidstuff/dirtree"
readonly DIRTREE_SCRIPT="/mnt/user/data/computer/unraidstuff/dirtree.py"
readonly MOUNT_POINT_PERMS="775"
readonly LOG_FILE="/mnt/user/data/computer/unraidstuff/userscript_logs/${SCRIPT_NAME}.log"
readonly ARCHIVE_DIR="/mnt/user/data/computer/unraidstuff/userscript_logs/old_logs/${SCRIPT_NAME}"
readonly LOG_OWNER="jcofer555:users"
readonly LOG_RETENTION=7
readonly LOCK_DIR="/tmp/scriptsrunning"
readonly LOCK_FILE="${LOCK_DIR}/${SCRIPT_NAME}"

readonly -a REQUIRED_PYTHON_PACKAGES=(
    "pandas"
    "openpyxl"
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
    send_discord_message "DIRTREE ERROR" "$1" 15158332
}

send_discord_success() {
    send_discord_message "DIRTREE" "$1" 3066993
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
# PYTHON PACKAGE CHECK + INSTALL
# Aborts if any required package cannot be installed.
# =============================================================================
ensure_python_packages() {
    log_section "Checking required Python packages"

    local pkg
    for pkg in "${REQUIRED_PYTHON_PACKAGES[@]}"; do
        if python3 -c "import ${pkg}" &>/dev/null; then
            log_info "Python package present: $pkg"
        else
            log_info "Python package missing, installing: $pkg"
            if pip install "$pkg" 2>&1 | tee -a "$LOG_FILE"; then
                log_info "Installed: $pkg"
            else
                log_error "Failed to install Python package: $pkg"
                return 1
            fi
        fi
    done
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

    # --- Prepare output directory ---
    log_section "Preparing output directory: $MOUNT_POINT"
    if [ ! -d "$MOUNT_POINT" ]; then
        log_info "Creating: $MOUNT_POINT"
        if mkdir -p "$MOUNT_POINT"; then
            log_info "Created: $MOUNT_POINT"
        else
            log_error "Failed to create: $MOUNT_POINT"
            exit 1
        fi
    else
        log_info "Exists: $MOUNT_POINT"
    fi

    if chown -R "$LOG_OWNER" "$MOUNT_POINT"; then
        log_info "Ownership set: $MOUNT_POINT"
    else
        log_error "Failed to set ownership: $MOUNT_POINT"
    fi

    # --- Ensure Python packages ---
    if ! ensure_python_packages; then
        log_error "Required Python packages could not be installed — aborting"
        exit 1
    fi

    # --- Verify dirtree script exists ---
    log_section "Running dirtree Python script"
    if [ ! -f "$DIRTREE_SCRIPT" ]; then
        log_error "Dirtree script not found: $DIRTREE_SCRIPT"
        exit 1
    fi

    # Ensure executable bit is set
    if ! chmod +x "$DIRTREE_SCRIPT"; then
        log_error "Failed to set executable bit on: $DIRTREE_SCRIPT"
    fi

    # --- Run dirtree script ---
    log_info "Executing: $DIRTREE_SCRIPT"
    if python3 "$DIRTREE_SCRIPT" 2>&1 | tee -a "$LOG_FILE"; then
        log_info "Dirtree script completed successfully"
    else
        log_error "Dirtree script exited with non-zero status"
    fi

    # --- Set final permissions and ownership on output ---
    log_section "Finalizing output directory permissions"

    if chmod -R "$MOUNT_POINT_PERMS" "$MOUNT_POINT"; then
        log_info "Permissions set to $MOUNT_POINT_PERMS: $MOUNT_POINT"
    else
        log_error "Failed to set permissions on: $MOUNT_POINT"
    fi

    if chown -R "$LOG_OWNER" "$MOUNT_POINT"; then
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
