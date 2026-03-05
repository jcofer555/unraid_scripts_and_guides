```bash
#!/bin/bash
# =============================================================================
# sonarr_missing_episodes
# Deterministic, atomic, auditable Sonarr missing episode report script.
# Skill: unified-jonathan-weighted-skill (Bash Module)
# =============================================================================
# DEVIATION NOTE: set -e is NOT used globally because jq/curl may return
# non-zero on empty result sets which are non-fatal (e.g. a show with no
# missing episodes). set -uo pipefail is used instead.
#
# DEVIATION NOTE: The main processing loop uses a subshell pipeline
# (jq | while read | while read >> TMPFILE) which means ERRORS mutations
# inside those loops do NOT propagate back to the parent shell. Errors inside
# the loop are written directly to the log and counted via a tmpfile counter
# rather than via the ERRORS global. Final Discord error notification is
# triggered if the error counter file is non-empty.
set -uo pipefail

# =============================================================================
# CONSTANTS
# =============================================================================
readonly SCRIPT_NAME="sonarr_missing_episodes"
readonly WEBHOOK_URL="https://discord.com/api/webhooks/1389372076502028442/CN_Oo7nk1ZpKwT0zzNB7MB77mnxcUXBP3vLI0g3W6pJXbkVz4_E73mLVHElcjFvWSPIF"
readonly APIKEY="7970f119864343e98ea6b1b1df6c20ea"
readonly SONARR_URL="http://10.100.10.250:8990/api/v3"
readonly OUTFILE="/mnt/user/data/missing_episodes.txt"
readonly SERIESFILE="/mnt/user/data/series.json"
readonly LOG_FILE="/mnt/user/data/computer/unraidstuff/userscript_logs/${SCRIPT_NAME}.log"
readonly ARCHIVE_DIR="/mnt/user/data/computer/unraidstuff/userscript_logs/old_logs/${SCRIPT_NAME}"
readonly LOG_OWNER="jcofer555:users"
readonly LOG_RETENTION=7
readonly LOCK_DIR="/tmp/scriptsrunning"
readonly LOCK_FILE="${LOCK_DIR}/${SCRIPT_NAME}"

# Shows to exclude entirely
readonly -a EXCLUDES=(
    "MythBusters"
)

# Specific episodes to exclude (format: "Show Title|SxxEyy")
readonly -a EXCLUDE_EPISODES=(
    "Family Guy|S08E20"
    "Family Guy|S09E18"
    "The Drew Carey Show|S04E10"
    "The Drew Carey Show|S07E01"
    "The Drew Carey Show|S07E02"
    "The Drew Carey Show|S08E17"
    "Unhappily Ever After|S04E19"
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
    send_discord_message "SONARR MISSING EPISODES ERROR" "$1" 15158332
}

send_discord_success() {
    send_discord_message "SONARR MISSING EPISODES" "$1" 3066993
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
# Removes lock file and all temp files on exit.
# =============================================================================
TMPFILE=""
LOOP_ERROR_FILE=""

cleanup() {
    local exit_code=$?
    [ -f "$LOCK_FILE"        ] && rm -f "$LOCK_FILE"
    [ -n "$TMPFILE"          ] && rm -f "$TMPFILE"
    [ -n "$LOOP_ERROR_FILE"  ] && rm -f "$LOOP_ERROR_FILE"
    [ -f "$SERIESFILE"       ] && rm -f "$SERIESFILE"
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
# SHOW EXCLUSION CHECK
# =============================================================================
is_excluded_show() {
    local show="$1"
    local skip
    for skip in "${EXCLUDES[@]}"; do
        [[ "$show" == "$skip" ]] && return 0
    done
    return 1
}

# =============================================================================
# EPISODE EXCLUSION CHECK
# =============================================================================
is_excluded_episode() {
    local key="$1"
    local skip
    for skip in "${EXCLUDE_EPISODES[@]}"; do
        [[ "$key" == "$skip" ]] && return 0
    done
    return 1
}

# =============================================================================
# FETCH SERIES LIST
# =============================================================================
fetch_series() {
    log_section "Fetching series list from Sonarr"
    > "$SERIESFILE"

    if curl -sf "${SONARR_URL}/series?apikey=${APIKEY}" -o "$SERIESFILE"; then
        local count
        count=$(jq 'length' "$SERIESFILE" 2>/dev/null || echo 0)
        log_info "Fetched $count series from Sonarr"
    else
        log_error "Failed to fetch series list from Sonarr: ${SONARR_URL}/series"
        return 1
    fi
}

# =============================================================================
# PROCESS SERIES
# Loops through all series IDs, fetches episodes, filters missing ones,
# and appends formatted lines to TMPFILE.
#
# DEVIATION NOTE: The outer loop runs inside a pipeline subshell
# (jq ... | while read sid). Variable mutations inside this loop
# (like ERRORS) are lost when the subshell exits. Loop-level errors are
# instead written to LOOP_ERROR_FILE, which is checked in main() after
# the loop completes.
# =============================================================================
process_series() {
    log_section "Processing series"
    local shows_processed=0
    local shows_skipped=0

    jq -r '.[].id' "$SERIESFILE" | while IFS= read -r sid; do
        local show
        show=$(jq -r ".[] | select(.id==$sid) | .title" "$SERIESFILE")

        # Skip excluded shows
        if is_excluded_show "$show"; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO]  Skipping excluded show: $show" | tee -a "$LOG_FILE"
            (( shows_skipped++ )) || true
            continue
        fi

        # Fetch episodes for this series
        local episodes
        episodes=$(curl -sf "${SONARR_URL}/episode?seriesId=${sid}&apikey=${APIKEY}") || {
            echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] Failed to fetch episodes for: $show (id=$sid)" \
                | tee -a "$LOG_FILE"
            echo "Failed to fetch episodes for: $show (id=$sid)" >> "$LOOP_ERROR_FILE"
            continue
        }

        # Find highest season number
        local last_season
        last_season=$(echo "$episodes" | jq '[.[].seasonNumber] | max')

        # Check if last season still has future air dates
        local has_future
        has_future=$(echo "$episodes" | jq --argjson last "$last_season" '
            [.[] | select(
                .seasonNumber==$last
                and .airDateUtc != null
                and (.airDateUtc | fromdateiso8601 > now)
            )] | length')

        local exclude_last
        [ "$has_future" -gt 0 ] && exclude_last=true || exclude_last=false

        echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO]  Processing: $show (last season: $last_season | exclude last: $exclude_last)" \
            | tee -a "$LOG_FILE"

        # Extract missing episodes as TSV and process each one
        echo "$episodes" \
            | jq -r --arg show "$show" \
                    --argjson last "$last_season" \
                    --argjson exclude "$exclude_last" '
                .[]
                | select(.hasFile==false)
                | select(.seasonNumber!=0)
                | select(if $exclude==true then .seasonNumber < $last else true end)
                | [.seasonNumber, .episodeNumber, .title]
                | @tsv' \
            | while IFS=$'\t' read -r season ep title; do
                local episode_key="${show}|S$(printf '%02d' "$season")E$(printf '%02d' "$ep")"

                # Skip excluded episodes
                # DEVIATION NOTE: log message written to LOG_FILE only (not stdout)
                # so it does not flow through the pipe into TMPFILE.
                if is_excluded_episode "$episode_key"; then
                    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO]  Skipping excluded episode: $episode_key"                         >> "$LOG_FILE"
                    continue
                fi

                printf "%s - S%02dE%02d - %s\n" "$show" "$season" "$ep" "$title"
            done >> "$TMPFILE"

        (( shows_processed++ )) || true
    done

    log_info "Series processed: $shows_processed | skipped (excluded): $shows_skipped"
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    acquire_lock
    rotate_logs

    > "$LOG_FILE"
    log_info "===== Script started: $(date +'%m-%d-%Y %I:%M:%S %p') ====="

    # Initialise temp files after log is open so cleanup trap can log removal
    TMPFILE=$(mktemp)
    LOOP_ERROR_FILE=$(mktemp)

    # --- Fetch series ---
    if ! fetch_series; then
        send_discord_error "Failed to fetch series from Sonarr — aborting."
        exit 1
    fi

    # --- Process and collect missing episodes ---
    process_series

    # --- Check for loop-level errors ---
    if [ -s "$LOOP_ERROR_FILE" ]; then
        while IFS= read -r loop_err; do
            log_error "$loop_err"
        done < "$LOOP_ERROR_FILE"
    fi

    # --- Sort and write final output ---
    log_section "Writing output"
    if sort "$TMPFILE" > "$OUTFILE"; then
        local missing_count
        missing_count=$(wc -l < "$OUTFILE")
        log_info "Missing episodes report written: $OUTFILE ($missing_count missing)"
    else
        log_error "Failed to sort/write output file: $OUTFILE"
    fi

    # --- Ownership on output ---
    if chown "$LOG_OWNER" "$OUTFILE" 2>/dev/null; then
        log_info "Ownership set: $OUTFILE"
    else
        log_error "Failed to set ownership: $OUTFILE"
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
    local missing_count
    missing_count=$(wc -l < "$OUTFILE" 2>/dev/null || echo "?")

    if [ -n "$ERRORS" ]; then
        send_discord_error "$(printf 'Errors during run:\n%s\nCheck log: %s' "$ERRORS" "$LOG_FILE")"
    else
        :
    fi
}

main "$@"```
