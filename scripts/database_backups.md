```bash
#!/bin/bash
# =============================================================================
# database_backups
# Deterministic, atomic, auditable PostgreSQL17 and MariaDB backup script.
# Skill: unified-jonathan-weighted-skill (Bash Module)
#
# RESTORE INSTRUCTIONS:
#   PostgreSQL17:
#     1. Copy backup file into postgresql17's appdata folder
#     2. Use container console:
#        psql -U jcofer555 -d postgres -f /var/lib/postgresql/data/full_backup_<timestamp>.sql
#
#   MariaDB:
#     1. Copy backup file into mariadb-nc's appdata folder
#     2. Use container console:
#        /usr/bin/mariadb -u root -p nextcloud < full_backup_<timestamp>.sql
# =============================================================================
# DEVIATION NOTE: set -e is NOT used globally because docker exec dump commands
# may return non-zero on warnings that do not indicate a failed backup.
# set -uo pipefail is used instead for unbound variable and pipe safety.
set -uo pipefail

# =============================================================================
# CONSTANTS
# =============================================================================
readonly SCRIPT_NAME="database_backups"
readonly WEBHOOK_URL="https://discord.com/api/webhooks/1389372076502028442/CN_Oo7nk1ZpKwT0zzNB7MB77mnxcUXBP3vLI0g3W6pJXbkVz4_E73mLVHElcjFvWSPIF"
readonly POSTGRESQL17_MOUNT_POINT="/mnt/user/data/computer/backups/database_backups/postgresql17"
readonly MARIADB_MOUNT_POINT="/mnt/user/data/computer/backups/database_backups/mariadb"
readonly DB_BACKUP_RETENTION=7
readonly LOG_FILE="/mnt/user/data/computer/unraidstuff/userscript_logs/${SCRIPT_NAME}.log"
readonly ARCHIVE_DIR="/mnt/user/data/computer/unraidstuff/userscript_logs/old_logs/${SCRIPT_NAME}"
readonly LOG_OWNER="jcofer555:users"
readonly LOG_RETENTION=7
readonly LOCK_DIR="/tmp/scriptsrunning"
readonly LOCK_FILE="${LOCK_DIR}/${SCRIPT_NAME}"

# DEVIATION NOTE: MARIADB_PASSWORD exported for docker exec child process.
export MARIADB_PASSWORD="Scjb8489!"

# =============================================================================
# STATE
# Timestamp is captured once at start so both backup filenames are identical.
# =============================================================================
ERRORS=""
START_TIME=$(date +%s)
RUN_TIMESTAMP=$(date +'%m-%d-%Y_%I-%M-%S_%p')

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
    send_discord_message "DATABASE BACKUPS ERROR" "$1" 15158332
}

send_discord_success() {
    send_discord_message "DATABASE BACKUPS" "$1" 3066993
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
# PREPARE BACKUP DIRECTORY
# Creates dir and sets ownership. Does NOT wipe — backups are retained.
# =============================================================================
prepare_backup_dir() {
    local dir="$1"

    if [ -z "$dir" ]; then
        log_error "prepare_backup_dir called with empty path"
        return 1
    fi

    if [ ! -d "$dir" ]; then
        log_info "Creating backup directory: $dir"
        if mkdir -p "$dir"; then
            log_info "Created: $dir"
        else
            log_error "Failed to create: $dir"
            return 1
        fi
    else
        log_info "Backup directory exists: $dir"
    fi

    if chown -R "$LOG_OWNER" "$dir"; then
        log_info "Ownership set: $dir"
    else
        log_error "Failed to set ownership: $dir"
    fi
}

# =============================================================================
# PRUNE OLD BACKUPS
# Keeps the N most recent full_backup_*.sql files in a given directory.
# Uses find+sort rather than ls globbing to handle filenames safely.
# =============================================================================
prune_old_backups() {
    local dir="$1"
    local label="$2"
    local retention="$3"

    log_info "Pruning old $label backups (keeping latest $retention) in: $dir"

    # Collect backup files sorted newest-first by modification time
    local -a all_backups=()
    while IFS= read -r f; do
        all_backups+=("$f")
    done < <(find "$dir" -maxdepth 1 -type f -name "full_backup_*.sql" -printf '%T@ %p\n' \
        | sort -rn | awk '{print $2}')

    local total=${#all_backups[@]}

    if [ "$total" -le "$retention" ]; then
        log_info "Found $total $label backup(s) — no pruning needed"
        return 0
    fi

    local excess=$(( total - retention ))
    log_info "Found $total $label backup(s) — pruning $excess oldest"

    for (( idx=retention; idx<total; idx++ )); do
        local file="${all_backups[$idx]}"
        if rm -f "$file"; then
            log_info "Pruned: $file"
        else
            log_error "Failed to prune: $file"
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
    log_info "Run timestamp: $RUN_TIMESTAMP"

    # Derive backup filenames from the single captured timestamp
    local pg_backup_file="${POSTGRESQL17_MOUNT_POINT}/full_backup_${RUN_TIMESTAMP}.sql"
    local mariadb_backup_file="${MARIADB_MOUNT_POINT}/full_backup_${RUN_TIMESTAMP}.sql"

    # --- Prepare backup directories ---
    log_section "Preparing backup directories"
    prepare_backup_dir "$POSTGRESQL17_MOUNT_POINT"
    prepare_backup_dir "$MARIADB_MOUNT_POINT"

    # --- PostgreSQL17 backup ---
    log_section "PostgreSQL17 backup"
    log_info "Target: $pg_backup_file"

    if ! docker ps -q -f name=postgresql17 | grep -q .; then
        log_error "Container postgresql17 is not running — skipping backup"
    else
        # DEVIATION NOTE: docker exec -t allocates a pseudo-TTY which can inject
        # carriage returns into the SQL dump. Using -i (no TTY) for clean output.
        if docker exec -i postgresql17 pg_dumpall -U jcofer555 > "$pg_backup_file" 2>&1; then
            log_info "PostgreSQL17 backup created: $pg_backup_file"
        else
            log_error "PostgreSQL17 backup failed: $pg_backup_file"
            rm -f "$pg_backup_file"
        fi
    fi

    prune_old_backups "$POSTGRESQL17_MOUNT_POINT" "postgresql17" "$DB_BACKUP_RETENTION"

    # --- MariaDB-NC backup ---
    log_section "MariaDB-NC backup"
    log_info "Target: $mariadb_backup_file"

    if ! docker ps -q -f name=mariadb-nc | grep -q .; then
        log_error "Container mariadb-nc is not running — skipping backup"
    else
        # DEVIATION NOTE: -i instead of -t for same reason as above.
        if docker exec -i mariadb-nc /usr/bin/mariadb-dump \
            -u root -p"$MARIADB_PASSWORD" --all-databases > "$mariadb_backup_file" 2>&1; then
            log_info "MariaDB-NC backup created: $mariadb_backup_file"
        else
            log_error "MariaDB-NC backup failed: $mariadb_backup_file"
            rm -f "$mariadb_backup_file"
        fi
    fi

    prune_old_backups "$MARIADB_MOUNT_POINT" "mariadb-nc" "$DB_BACKUP_RETENTION"

    # --- Final ownership pass ---
    log_section "Final ownership pass"
    for dir in "$POSTGRESQL17_MOUNT_POINT" "$MARIADB_MOUNT_POINT"; do
        if chown -R "$LOG_OWNER" "$dir"; then
            log_info "Ownership set: $dir"
        else
            log_error "Failed to set ownership: $dir"
        fi
    done

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
