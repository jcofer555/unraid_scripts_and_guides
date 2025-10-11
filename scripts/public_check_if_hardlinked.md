```bash
#!/bin/bash

# === CONFIGURATION ===
SEARCH_DIR="/mnt/user/appdata"
LOG_NOT_HARDLINKED="$SEARCH_DIR/files_not_hardlinked.log"
JDUPE_LOG="$SEARCH_DIR/jdupes_hardlinking.log"

RUN_JDUPES="no"               # Set to "yes" if you want jdupes to run against what is found to be not hardlinked
DRY_RUN="no"                  # Set to "yes" if you want to do a test run
INSTALL_JDUPES_PACKAGES="yes" # Set to "yes" to install jdupes/libjodycode if missing

#### DON'T CHANGE ANYTHING BELOW HERE ####

# === VALIDATE INSTALL VARIABLE ===
if [[ "$INSTALL_JDUPES_PACKAGES" != "yes" && "$INSTALL_JDUPES_PACKAGES" != "no" ]]; then
    echo "❌ Invalid value for INSTALL_JDUPES_PACKAGES: $INSTALL_JDUPES_PACKAGES"
    echo "Please set it to 'yes' or 'no'"
    exit 1
fi

# === VALIDATE INSTALL VARIABLE ===
if [[ "$SKIP_DUPES" != "yes" && "$SKIP_JDUPES" != "no" ]]; then
    echo "❌ Invalid value for SKIP_JDUPES: $SKIP_JDUPES"
    echo "Please set it to 'yes' or 'no'"
    exit 1
fi

# === VALIDATE INSTALL VARIABLE ===
if [[ "$DRY_RUN" != "yes" && "$DRY_RUN" != "no" ]]; then
    echo "❌ Invalid value for DRY_RUN: $DRY_RUN"
    echo "Please set it to 'yes' or 'no'"
    exit 1
fi

echo
echo "=== Starting scan for non-hardlinked files in $SEARCH_DIR ==="
[ "$DRY_RUN" = "yes" ] && echo "🧪 DRY RUN ENABLED: No scanning, logging, or file operations will occur."

# === INSTALL FUNCTIONS ===
get_latest_github_pkg_name() {
    local prefix="$1"
    local suffix=".tgz"
    local api_url="https://api.github.com/repos/jcofer555/unraid_packages/contents/?ref=main"
    curl -s "$api_url" | jq -r \
        ".[] | select(.name | startswith(\"$prefix\")) | select(.name | endswith(\"$suffix\")) | .name" \
        | sort -V | tail -n1
}

install_package() {
    local pkg_name="$1"
    local pkg_url="$2"
    local check_cmd="$3"
    local slack_pkg_name="$4"
    local display_name="$5"
    local pkg_path="/boot/extra/$pkg_name"

    echo
    echo "### Installing $display_name ###"

    if [ "$DRY_RUN" = "yes" ]; then
        echo "DRY_RUN: Would check if $display_name is installed using: $check_cmd"
        echo "DRY_RUN: Would download $pkg_url to $pkg_path"
        echo "DRY_RUN: Would run installpkg $pkg_path"
        return 0
    fi

    [ ! -d "/boot/extra" ] && mkdir -p "/boot/extra"

    if ! eval "$check_cmd" >/dev/null 2>&1; then
        echo "$display_name not installed. Proceeding with install..."
        wget -q -O "$pkg_path" "$pkg_url"
        installpkg "$pkg_path" >/dev/null 2>&1 && echo "✅ Installed $display_name"
    else
        echo "$display_name already installed."
    fi
}

# === OPTIONAL INSTALL ===
if [ "$INSTALL_JDUPES_PACKAGES" = "yes" ]; then
    pkg_name="$(get_latest_github_pkg_name "jdupes-")"
    pkg_url="https://github.com/jcofer555/unraid_packages/raw/refs/heads/main/$pkg_name"
    pkg_check="ls /var/log/packages | grep -q '^jdupes-'"
    install_package "$pkg_name" "$pkg_url" "$pkg_check" "jdupes" "jdupes"

    pkg_name="$(get_latest_github_pkg_name "libjodycode-")"
    pkg_url="https://github.com/jcofer555/unraid_packages/raw/refs/heads/main/$pkg_name"
    pkg_check="ldconfig -p | grep -q libjodycode"
    install_package "$pkg_name" "$pkg_url" "$pkg_check" "libjodycode" "libjodycode"
else
    echo "Skipping installation of jdupes and libjodycode due to INSTALL_JDUPES_PACKAGES=$INSTALL_JDUPES_PACKAGES"
fi

# === SCAN FOR NON-HARDLINKED FILES ===
if [ "$DRY_RUN" = "yes" ]; then
    echo
    echo "DRY_RUN: Skipping scan of $SEARCH_DIR"
    echo "DRY_RUN: No log file ($LOG_NOT_HARDLINKED) will be created"
else
    echo
    echo "Scanning for non-hardlinked files in $SEARCH_DIR..."
    echo "=== jdupes results ===" > "$JDUPE_LOG"
    > "$LOG_NOT_HARDLINKED"

    ALL_FILES=$(find "$SEARCH_DIR" -type f \
        ! -path '*/.*' \
        ! -iname '.ds_store' \
        ! -iname 'thumbs.db')

    nonlinked_count=0

    while IFS= read -r file; do
        link_count=$(stat --format="%h" "$file")
        if [ "$link_count" -eq 1 ]; then
            echo "$file" >> "$LOG_NOT_HARDLINKED"
            ((nonlinked_count++))
        fi
    done <<< "$ALL_FILES"

    echo "Scan complete."
    echo "$nonlinked_count non-hardlinked files saved to: $LOG_NOT_HARDLINKED"
    echo
fi

# === RUN JDUPES ===
if [ "$RUN_JDUPES" = "yes" ] && command -v jdupes >/dev/null 2>&1; then
    if [ "$DRY_RUN" = "yes" ]; then
        echo "DRY_RUN: Skipping jdupes execution and log creation"
    else
        echo "Running jdupes to deduplicate and hardlink files..."
        xargs -a "$LOG_NOT_HARDLINKED" jdupes -r -L --no-hidden 2>/dev/null >> "$JDUPE_LOG" \
            && echo "jdupes deduplication complete. Log saved to: $JDUPE_LOG" \
            || echo "jdupes hardlinking failed"
    fi
else
    echo "Skipping jdupes hardlinking step."
fi

```
