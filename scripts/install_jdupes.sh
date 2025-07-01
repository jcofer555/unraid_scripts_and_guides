#!/bin/bash

# === CONFIGURATION ===
ALLOW_INSTALL_OR_UPGRADE=true               # Set to false to prevent install/upgrade/reinstall actions
FORCE_REINSTALL=false                       # Set to true to reinstall even if a current version is installed
DRY_RUN=false                               # Set to true to simulate actions without making changes

        ### DON'T CHANGE ANYTHING BELOW HERE ###

# === DRY RUN NOTICE ===
if [ "$DRY_RUN" = true ]; then
    echo "🧪 DRY_RUN ENABLED: No changes will be made. Commands will be echoed but not executed 🧪"
fi

# === FUNCTION TO FETCH LATEST PACKAGE FROM GITHUB ===
get_latest_github_pkg_name() {
    local prefix="$1"
    local suffix=".tgz"
    local api_url="https://api.github.com/repos/jcofer555/unraid_packages/contents/?ref=main"

    curl -s "$api_url" | jq -r \
        ".[] | select(.name | startswith(\"$prefix\")) | select(.name | endswith(\"$suffix\")) | .name" \
        | sort -V | tail -n1
}

# === MAIN PACKAGE MANAGEMENT FUNCTION ===
manage_package() {
    local pkg_name="$1"
    local pkg_url="$2"
    local check_cmd="$3"
    local slack_pkg_name="$4"
    local display_name="$5"
    local pkg_path="/boot/extra/$pkg_name"

    echo
    echo "### $display_name ###"
    echo

    # Ensure /boot/extra exists
    if [ ! -d "/boot/extra" ]; then
        echo "/boot/extra not found, creating it..."
        if [ "$DRY_RUN" = true ]; then
            echo "DRY_RUN: mkdir -p /boot/extra"
        elif ! mkdir -p "/boot/extra"; then
            echo "Failed to create /boot/extra"
            return 1
        fi
    fi

    # Check if installed
    local is_installed=false
    if eval "$check_cmd"; then
        is_installed=true
        echo "$display_name is currently installed"
    else
        echo "$display_name is not currently installed"
    fi

    # Download if not present
    if [ ! -f "$pkg_path" ]; then
        echo "File is not in /boot/extra, downloading $pkg_name to /boot/extra..."
        if [ "$DRY_RUN" = true ]; then
            echo "DRY_RUN: wget -O $pkg_path $pkg_url"
        elif ! wget -q -O "$pkg_path" "$pkg_url"; then
            echo "❌ Failed to download $pkg_name"
            return 1
        fi
    fi

    # Check file integrity
    if [ ! -s "$pkg_path" ]; then
        echo "Package $pkg_name is empty. Attempting redownload..."
        [ "$DRY_RUN" = false ] && rm -f "$pkg_path"
        if [ "$DRY_RUN" = true ]; then
            echo "DRY_RUN: wget -O $pkg_path $pkg_url"
        elif ! wget -q -O "$pkg_path" "$pkg_url"; then
            echo "❌ Failed to re-download $pkg_name"
            return 1
        fi
    fi

    # Verify package format
    if ! file "$pkg_path" | grep -q 'XZ compressed data\|gzip compressed data'; then
        echo "Package format invalid. Attempting redownload..."
        [ "$DRY_RUN" = false ] && rm -f "$pkg_path"
        if [ "$DRY_RUN" = true ]; then
            echo "DRY_RUN: wget -O $pkg_path $pkg_url"
        elif ! wget -q -O "$pkg_path" "$pkg_url"; then
            echo "❌ Failed to re-download $pkg_name"
            return 1
        fi
    fi

    # Compare versions
    local installed_version=""
    local new_version=$(echo "$pkg_name" | sed "s/^$slack_pkg_name-//" | sed 's/\.tgz//')

    if [ "$is_installed" = true ]; then
        installed_version=$(ls /var/log/packages | grep "^$slack_pkg_name-" | sed "s/^$slack_pkg_name-//" | sed 's/\.tgz//')
        echo "Installed version: $installed_version"
        echo "Available version: $new_version"

        if [ "$FORCE_REINSTALL" = true ]; then
            if [ "$ALLOW_INSTALL_OR_UPGRADE" != true ]; then
                echo "⚠️ FORCE_REINSTALL is true, but ALLOW_INSTALL_OR_UPGRADE is false. Skipping reinstall of $display_name."
                return 0
            fi
            echo "FORCE_REINSTALL is true. Reinstalling $display_name..."
            if [ "$DRY_RUN" = true ]; then
                echo "DRY_RUN: upgradepkg --install-new $pkg_path"
            elif upgradepkg --install-new "$pkg_path" >/dev/null 2>&1; then
                echo "✅ Reinstalled $display_name (version: $new_version)"
            else
                echo "❌ Failed to reinstall $display_name"
                return 1
            fi
        elif [ "$installed_version" != "$new_version" ]; then
            echo "Version mismatch detected: $installed_version → $new_version"
            if [ "$ALLOW_INSTALL_OR_UPGRADE" = true ]; then
                echo "Upgrading $display_name..."
                if [ "$DRY_RUN" = true ]; then
                    echo "DRY_RUN: upgradepkg --install-new $pkg_path"
                elif upgradepkg --install-new "$pkg_path" >/dev/null 2>&1; then
                    echo "✅ Upgraded $display_name from $installed_version to $new_version"
                else
                    echo "❌ Failed to upgrade $display_name"
                    return 1
                fi
            else
                echo "⚠️ Upgrade available, but ALLOW_INSTALL_OR_UPGRADE is false. Skipping."
            fi
        else
            echo "✅ $display_name is up to date (version: $installed_version)"
        fi
    else
        if [ "$ALLOW_INSTALL_OR_UPGRADE" = true ]; then
            echo "Installing $display_name (version: $new_version)..."
            if [ "$DRY_RUN" = true ]; then
                echo "DRY_RUN: installpkg $pkg_path"
            elif installpkg "$pkg_path" >/dev/null 2>&1; then
                echo "✅ Successfully installed $display_name (version: $new_version)"
            else
                echo "❌ Failed to install $display_name"
                return 1
            fi
        else
            echo "⚠️ ALLOW_INSTALL_OR_UPGRADE is false. Skipping installation of $display_name"
        fi
    fi
}

# === JDUPES ===
pkg_name="$(get_latest_github_pkg_name "jdupes-")"
if [ -z "$pkg_name" ]; then
    echo "❌ Could not find jdupes package"
    exit 1
fi
pkg_url="https://github.com/jcofer555/unraid_packages/raw/refs/heads/main/$pkg_name"
pkg_check="ls /var/log/packages | grep -q '^jdupes-'"
slack_pkg_id="jdupes"
display_name="Jdupes"

manage_package "$pkg_name" "$pkg_url" "$pkg_check" "$slack_pkg_id" "$display_name" || {
    echo "❌ Aborting: jdupes failed. libjodycode will not be processed."
    exit 1
}

# === LIBJODYCODE ===
pkg_name="$(get_latest_github_pkg_name "libjodycode-")"
if [ -z "$pkg_name" ]; then
    echo "❌ Could not find libjodycode package"
    exit 1
fi
pkg_url="https://github.com/jcofer555/unraid_packages/raw/refs/heads/main/$pkg_name"
pkg_check="ldconfig -p | grep -q libjodycode"
slack_pkg_id="libjodycode"
display_name="Libjodycode"

manage_package "$pkg_name" "$pkg_url" "$pkg_check" "$slack_pkg_id" "$display_name"