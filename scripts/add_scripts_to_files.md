```bash
#!/bin/bash
# =============================================================================
# add_scripts_to_files
# Deterministic, atomic, auditable script export and GitHub push script.
# Skill: unified-jonathan-weighted-skill (Bash Module)
# =============================================================================
set -uo pipefail

# =============================================================================
# CONSTANTS
# =============================================================================
readonly SCRIPT_NAME="add_scripts_to_files"
readonly WEBHOOK_URL="https://discord.com/api/webhooks/1389372076502028442/CN_Oo7nk1ZpKwT0zzNB7MB77mnxcUXBP3vLI0g3W6pJXbkVz4_E73mLVHElcjFvWSPIF"
readonly PRIVATE_MOUNT_POINT="/mnt/user/data/github_projects/unraid_private_scripts/scripts"
readonly DEV_MOUNT_POINT="/mnt/user/data/github_projects/unraid_private_scripts/devunraid_scripts"
readonly PUBLIC_MOUNT_POINT="/mnt/user/data/github_projects/unraid_scripts_and_guides/scripts"
readonly PRIVATE_REPO="/mnt/user/data/github_projects/unraid_private_scripts"
readonly PUBLIC_REPO="/mnt/user/data/github_projects/unraid_scripts_and_guides"
readonly PRIVATE_SAFE="safe.directory=/mnt/cache/data/github_projects/unraid_private_scripts"
readonly PUBLIC_SAFE="safe.directory=/mnt/cache/data/github_projects/unraid_scripts_and_guides"
readonly GIT_EMAIL="jcofer555@users.noreply.github.com"
readonly GIT_NAME="jcofer555"
readonly SSH_KEY="$HOME/.ssh/unraidbackup_id_ed25519"
readonly UMOUNT_TIMEOUT=45
readonly DEVUNRAID_MOUNT="/mnt/remotes/devunraid_flash"
readonly DEVUNRAID_SMB="//10.100.10.252/flash"
readonly LOG_FILE="/mnt/user/data/computer/unraidstuff/userscript_logs/${SCRIPT_NAME}.log"
readonly ARCHIVE_DIR="/mnt/user/data/computer/unraidstuff/userscript_logs/old_logs/${SCRIPT_NAME}"
readonly LOG_OWNER="jcofer555:users"
readonly LOG_RETENTION=7
readonly LOCK_DIR="/tmp/scriptsrunning"
readonly LOCK_FILE="${LOCK_DIR}/${SCRIPT_NAME}"
readonly USERSCRIPTS_BASE="/boot/config/plugins/user.scripts/scripts"
readonly DEV_USERSCRIPTS_BASE="/mnt/remotes/devunraid_flash/config/plugins/user.scripts/scripts"

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
    send_discord_message "ADD SCRIPTS TO FILES ERROR" "$1" 15158332
}

send_discord_success() {
    send_discord_message "Scripts Exported" "$1" 3066993
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
# LOG ROTATION
# =============================================================================
rotate_logs() {
    mkdir -p "$ARCHIVE_DIR"

    local timestamp
    timestamp=$(date +'%m-%d-%Y_%I-%M-%S_%p')
    local archive_log="${ARCHIVE_DIR}/${SCRIPT_NAME}_${timestamp}.log"

    if [ -s "$LOG_FILE" ]; then
        cp "$LOG_FILE" "$archive_log" && log_info "Archived previous log to: $archive_log"
    fi

    local num_logs
    num_logs=$(find "$ARCHIVE_DIR" -maxdepth 1 -type f -name "*.log" | wc -l)
    if [ "$num_logs" -gt "$LOG_RETENTION" ]; then
        local excess=$(( num_logs - LOG_RETENTION ))
        find "$ARCHIVE_DIR" -maxdepth 1 -type f -name "*.log" -printf '%T+ %p\n' \
            | sort | head -n "$excess" | awk '{print $2}' \
            | while IFS= read -r old_log; do
                rm -f "$old_log" && log_info "Pruned old log: $old_log"
            done
    fi

    chown -R "$LOG_OWNER" "$ARCHIVE_DIR" 2>/dev/null
}

# =============================================================================
# MOUNT HELPERS
# =============================================================================
mount_devunraid() {
    log_section "Mounting devunraid flash share"

    if mountpoint -q "$DEVUNRAID_MOUNT"; then
        log_info "$DEVUNRAID_MOUNT already mounted, skipping"
        return 0
    fi

    if /usr/local/sbin/rc.unassigned mount "$DEVUNRAID_SMB" >/dev/null 2>&1; then
        log_info "Mounted devunraid flash share: $DEVUNRAID_SMB"
        sleep 5
        return 0
    fi

    log_error "Failed to mount devunraid flash share: $DEVUNRAID_SMB"
    return 1
}

unmount_devunraid() {
    log_section "Unmounting devunraid flash share"

    sync && log_info "Filesystem buffers flushed"

    log_info "Waiting 10s before unmount..."
    sleep 10

    for (( i=0; i<UMOUNT_TIMEOUT; i++ )); do
        if /usr/local/sbin/rc.unassigned umount "$DEVUNRAID_SMB" >/dev/null 2>&1; then
            log_info "Unmounted devunraid flash share"
            return 0
        fi
        sleep 1
    done

    log_error "Unmount timed out after ${UMOUNT_TIMEOUT}s: $DEVUNRAID_SMB"
    return 1
}

# =============================================================================
# DIRECTORY PREPARE
# =============================================================================
prepare_dest_dir() {
    local dir="$1"

    log_info "Preparing destination dir: $dir"

    rm -rf "$dir" && log_info "Cleared: $dir"
    mkdir -p "$dir" && log_info "Created: $dir"
    chown -R "$LOG_OWNER" "$dir" || log_error "Failed to set ownership: $dir"
}

# =============================================================================
# SCRIPT EXPORT
# =============================================================================
export_script_as_md() {
    local src="$1"
    local dest="$2"
    local label
    label=$(basename "$dest")

    if [ ! -f "$src" ]; then
        log_error "Source script not found: $src"
        return 1
    fi

    {
        echo '```bash'
        cat "$src"
        echo '```'
    } > "$dest" && log_info "Exported: $label"
}

# =============================================================================
# DYNAMIC DISCOVERY + EXPORT + STALE CLEANUP
# =============================================================================
discover_scripts() {
    local base="$1"
    find "$base" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort
}

export_all_scripts() {
    local base="$1"
    local dest="$2"
    local label="$3"

    log_section "Exporting $label scripts"

    local scripts
    scripts=$(discover_scripts "$base")

    local expected_md=()

    while IFS= read -r script; do
        expected_md+=("${script}.md")
        export_script_as_md \
            "${base}/${script}/script" \
            "${dest}/${script}.md"
    done <<< "$scripts"

    for md in "$dest"/*.md; do
        local file
        file=$(basename "$md")
        if [[ ! " ${expected_md[*]} " =~ " ${file} " ]]; then
            log_info "Removing stale script: $file"
            rm -f "$md"
        fi
    done
}

# =============================================================================
# GIT HELPER (WITH PREFLIGHT + RETRY)
# =============================================================================
git_push_repo() {
    local repo="$1"
    local safe="$2"
    local label="$3"

    log_section "Git push: $label"

    local git_ssh="ssh -i $SSH_KEY -o IdentitiesOnly=yes"
    local git_base="git -c $safe -c user.email=$GIT_EMAIL -c user.name=$GIT_NAME"

    cd "$repo" || { log_error "Failed to cd into $label repo: $repo"; return 1; }

    log_info "Preflight: syncing $label repo with remote"

    GIT_SSH_COMMAND="$git_ssh" $git_base fetch origin
    GIT_SSH_COMMAND="$git_ssh" $git_base reset --hard origin/main && \
        log_info "Repo synced to origin/main for $label"

    GIT_SSH_COMMAND="$git_ssh" $git_base add .

    local has_changes=false
    if ! GIT_SSH_COMMAND="$git_ssh" $git_base diff --quiet; then has_changes=true; fi
    if ! GIT_SSH_COMMAND="$git_ssh" $git_base diff --cached --quiet; then has_changes=true; fi

    if $has_changes; then
        local commit_msg="Auto-update scripts $(date +'%m-%d-%Y %I:%M %p')"
        GIT_SSH_COMMAND="$git_ssh" $git_base commit -m "$commit_msg" && \
            log_info "Committed changes in $label repo"
    else
        log_info "No changes to commit in $label repo"
    fi

    local attempts=0
    local max_attempts=3

    while (( attempts < max_attempts )); do
        if GIT_SSH_COMMAND="$git_ssh" $git_base push origin main; then
            log_info "Pushed $label repo to GitHub"
            break
        fi
        attempts=$((attempts+1))
        log_error "Push failed for $label repo (attempt $attempts/$max_attempts)"
        sleep 3
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

    if ! mount_devunraid; then
        send_discord_error "Mount failed — aborting."
        exit 1
    fi

    if ! mountpoint -q "$DEVUNRAID_MOUNT"; then
        log_error "Mount point not active after mount attempt: $DEVUNRAID_MOUNT"
        send_discord_error "Mount point not active — aborting."
        exit 1
    fi

    log_section "Preparing destination directories"
    prepare_dest_dir "$PRIVATE_MOUNT_POINT"
    prepare_dest_dir "$DEV_MOUNT_POINT"
    prepare_dest_dir "$PUBLIC_MOUNT_POINT"

    export_all_scripts "$USERSCRIPTS_BASE" "$PRIVATE_MOUNT_POINT" "private"
    log_info "Copying private schedule.json"
    cat /boot/config/plugins/user.scripts/schedule.json > "${PRIVATE_MOUNT_POINT}/1-schedule.json"

    export_all_scripts "$DEV_USERSCRIPTS_BASE" "$DEV_MOUNT_POINT" "dev"
    log_info "Copying dev schedule.json"
    cat "${DEV_USERSCRIPTS_BASE}/../schedule.json" > "${DEV_MOUNT_POINT}/1-schedule.json"

    export_all_scripts "$USERSCRIPTS_BASE" "$PUBLIC_MOUNT_POINT" "public"

    unmount_devunraid

    log_section "Pushing to GitHub"
    git_push_repo "$PRIVATE_REPO" "$PRIVATE_SAFE" "private"
    git_push_repo "$PUBLIC_REPO"  "$PUBLIC_SAFE"  "public"

    chown "$LOG_OWNER" "$LOG_FILE" 2>/dev/null

    local end_time=$(date +%s)
    local duration=$(( end_time - START_TIME ))
    log_info "Script completed in $(format_duration "$duration")"

    if [ -n "$ERRORS" ]; then
        send_discord_error "Errors during run:\n$ERRORS"
    fi
}

main "$@"
```
