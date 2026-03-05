```bash
#!/bin/bash
# =============================================================================
# swag_ip_update
# Updates the SWAG nginx IP allowlist when the WAN IP changes.
# Skill: unified-jonathan-weighted-skill (Bash Module)
# =============================================================================
# DEVIATION NOTE: set -e is NOT used because curl may return non-zero on
# timeout which is handled explicitly. set -uo pipefail is used instead.
set -uo pipefail

# =============================================================================
# CONSTANTS
# =============================================================================
readonly SCRIPT_NAME="swag_ip_update"
readonly WEBHOOK_URL="https://discord.com/api/webhooks/1389372076502028442/CN_Oo7nk1ZpKwT0zzNB7MB77mnxcUXBP3vLI0g3W6pJXbkVz4_E73mLVHElcjFvWSPIF"
readonly CONF="/mnt/user/appdata/swag/nginx/include/ip_access.conf"
readonly IP_LOOKUP_URL="ipv4.icanhazip.com"
readonly IP_TIMEOUT=3
readonly CONF_OWNER="jcofer555:users"
readonly LOG_FILE="/mnt/user/data/computer/unraidstuff/userscript_logs/${SCRIPT_NAME}.log"
readonly ARCHIVE_DIR="/mnt/user/data/computer/unraidstuff/userscript_logs/old_logs/${SCRIPT_NAME}"
readonly LOG_OWNER="jcofer555:users"
readonly LOG_RETENTION=7
readonly LOCK_DIR="/tmp/scriptsrunning"
readonly LOCK_FILE="${LOCK_DIR}/${SCRIPT_NAME}"

# Static IPs always allowed — these never change
readonly -a STATIC_ALLOWS=(
    "allow 10.100.10.0/24;"
    "allow 10.100.50.0/24;"
    "allow 10.0.10.0/24;"
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
    send_discord_message "SWAG IP UPDATE ERROR" "$1" 15158332
}

send_discord_success() {
    send_discord_message "SWAG IP UPDATE" "$1" 3066993
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
# FETCH WAN IP
# Returns the current WAN IP as "allow x.x.x.x;" or empty string on failure.
# Separated from the conf-writing logic so it can be validated before
# any writes occur — prevents wiping the conf with an empty/bad IP.
# =============================================================================
fetch_wan_ip() {
    local raw_ip
    raw_ip=$(curl -sL -m "$IP_TIMEOUT" --fail "$IP_LOOKUP_URL" 2>/dev/null | tr -d '[:space:]')

    if [[ -z "$raw_ip" ]]; then
        log_error "Failed to fetch WAN IP from $IP_LOOKUP_URL (empty response or timeout)"
        return 1
    fi

    # Basic sanity check — must look like an IPv4 address
    if ! [[ "$raw_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log_error "Fetched value does not look like an IPv4 address: '$raw_ip'"
        return 1
    fi

    echo "allow ${raw_ip};"
}

# =============================================================================
# WRITE CONF
# Atomically writes a new ip_access.conf using a tmpfile + mv pattern so
# nginx never sees a half-written file during the update.
# =============================================================================
write_conf() {
    local wan_entry="$1"
    local tmpfile
    tmpfile=$(mktemp "${CONF}.tmp.XXXXXX")

    {
        echo "# List of IPs to allow access"
        echo "# Updated: $(date +'%m-%d-%Y %I:%M:%S %p')"
        echo "$wan_entry"
        local entry
        for entry in "${STATIC_ALLOWS[@]}"; do
            echo "$entry"
        done
        echo ""
        echo "# Deny anything not on the list"
        echo "deny all;"
    } > "$tmpfile"

    if mv "$tmpfile" "$CONF"; then
        log_info "Conf updated atomically: $CONF"
    else
        log_error "Failed to move tmpfile to conf: $CONF"
        rm -f "$tmpfile"
        return 1
    fi

    if chown "$CONF_OWNER" "$CONF"; then
        log_info "Ownership set: $CONF"
    else
        log_error "Failed to set ownership: $CONF"
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
    log_info "Conf: $CONF"

    # --- Fetch current WAN IP ---
    log_section "Fetching current WAN IP"
    local wan_entry
    if ! wan_entry=$(fetch_wan_ip); then
        send_discord_error "$(printf 'Could not fetch WAN IP — conf not updated.\nCheck log: %s' "$LOG_FILE")"
        exit 1
    fi
    log_info "Current WAN IP entry: $wan_entry"

    # --- Check if conf needs updating ---
    log_section "Checking if conf needs updating"
    if [ -f "$CONF" ] && grep -qF "$wan_entry" "$CONF"; then
        log_info "No change required — conf already contains: $wan_entry"
    else
        log_info "WAN IP change detected — updating conf"
        if write_conf "$wan_entry"; then
            log_info "Conf updated successfully"
        else
            log_error "Failed to update conf"
        fi
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
