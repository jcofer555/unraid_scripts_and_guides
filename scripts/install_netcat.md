```bash
#!/bin/bash

# === CONFIGURATION ===
ALLOW_INSTALL=true                            # Set to false to prevent new installations
ALLOW_UPGRADE=true                            # Set to false to prevent upgrades

FORCE_REINSTALL=false                         # Set to true to reinstall regardless of the above settings # To upgrade both ALLOW_INSTALL and ALLOW_UPGRADE need to be true
DRY_RUN=false                                 # Set to true to simulate actions without making changes

        #### DON'T CHANGE ANYTHING BELOW HERE ####

# === CONFIG SUMMARY ===
echo
echo "=== CONFIGURATION USED ==="
echo "  ALLOW_INSTALL:     $ALLOW_INSTALL"
echo "  ALLOW_UPGRADE:     $ALLOW_UPGRADE"
echo "  FORCE_REINSTALL:   $FORCE_REINSTALL"
echo "  DRY_RUN:           $DRY_RUN"

# === DRY RUN NOTICE ===
if [ "$DRY_RUN" = true ]; then
    echo
    echo "🧪 DRY_RUN ENABLED: No changes will be made. Commands will be echoed but not executed 🧪"
fi

# === FUNCTION TO FETCH LATEST PACKAGE FROM GITHUB ===
get_latest_github_pkg_name() {
    local prefix="$1"
    local suffix=".txz"
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
    local new_version=$(echo "$pkg_name" | sed "s/^$slack_pkg_name-//" | sed 's/\.txz//')

    echo
    echo "### $display_name ###"
    echo

    # Ensure /boot/extra exists
    if [ ! -d "/boot/extra" ]; then
        echo "/boot/extra not found, creating it"
        if [ "$DRY_RUN" = true ]; then
            echo "DRY_RUN: mkdir -p /boot/extra"
        elif ! mkdir -p "/boot/extra"; then
            echo "Failed to create /boot/extra"
            return 1
        fi
    fi

    # Check if installed
    local is_installed=false
    if eval "$check_cmd" >/dev/null 2>&1; then
        is_installed=true
        echo "$display_name is currently installed"
    else
        echo "$display_name is not currently installed"
    fi

    # Download if not present
    if [ ! -f "$pkg_path" ]; then
        echo "File is not in /boot/extra, downloading $pkg_name to /boot/extra"
        if [ "$DRY_RUN" = true ]; then
            echo "DRY_RUN: wget -O $pkg_path $pkg_url"
        elif ! wget -q -O "$pkg_path" "$pkg_url"; then
            echo "❌ Failed to download $pkg_name"
            return 1
        fi
    fi

    # Check file integrity
    if [ ! -s "$pkg_path" ]; then
        echo "Package $pkg_name is empty. Attempting redownload"
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
        echo "Package format invalid. Attempting redownload"
        [ "$DRY_RUN" = false ] && rm -f "$pkg_path"
        if [ "$DRY_RUN" = true ]; then
            echo "DRY_RUN: wget -O $pkg_path $pkg_url"
        elif ! wget -q -O "$pkg_path" "$pkg_url"; then
            echo "❌ Failed to re-download $pkg_name"
            return 1
        fi
    fi

    if [ "$is_installed" = true ]; then
        local installed_version=$(ls /var/log/packages | grep "^$slack_pkg_name-" | sed "s/^$slack_pkg_name-//" | sed 's/\.txz//')
        echo "Installed version: $installed_version"
        echo "Available version: $new_version"

        if [ "$FORCE_REINSTALL" = true ]; then
            echo "FORCE_REINSTALL is true"
            if [ "$DRY_RUN" = true ]; then
                echo "DRY_RUN: upgradepkg --install-new $pkg_path"
            elif removepkg "$slack_pkg_name" >/dev/null 2>&1 && upgradepkg --install-new "$pkg_path" >/dev/null 2>&1; then
                echo "✅ Reinstalled $display_name version: $new_version"
            else
                echo "❌ Failed to reinstall $display_name"
                return 1
            fi
        elif [ "$installed_version" != "$new_version" ]; then
            echo "Version mismatch detected: $installed_version → $new_version"

            if [ "$ALLOW_UPGRADE" = true ] && [ "$ALLOW_INSTALL" = true ]; then
                if [ "$DRY_RUN" = true ]; then
                    echo "DRY_RUN: upgradepkg --install-new $pkg_path"
                elif removepkg "$slack_pkg_name" >/dev/null 2>&1 && upgradepkg --install-new "$pkg_path" >/dev/null 2>&1; then
                    echo "✅ Upgraded $display_name from $installed_version to $new_version"
                else
                    echo "❌ Failed to upgrade $display_name"
                    return 1
                fi
            else
                echo "⚠️ Upgrade blocked due to configuration:"
                [ "$ALLOW_UPGRADE" != true ] && echo "   - ALLOW_UPGRADE is set to false"
                [ "$ALLOW_INSTALL" != true ] && echo "   - ALLOW_INSTALL is set to false which is required for upgrade"
            fi
        else
            echo "✅ $display_name is up to date"
            if [ "$ALLOW_UPGRADE" = true ]; then
                echo "ℹ️  No action taken: installed version matches available version"
            elif [ "$ALLOW_INSTALL" = false ] && [ "$ALLOW_UPGRADE" = false ] && [ "$FORCE_REINSTALL" = false ]; then
                echo "⚠️ No action taken: $display_name is installed, but all actions are disabled by configuration"
                echo "💡 Set FORCE_REINSTALL to true if you want to reinstall the package"
            fi
        fi
    else
        if [ "$ALLOW_INSTALL" = true ]; then
            if [ "$DRY_RUN" = true ]; then
                echo "DRY_RUN: installpkg $pkg_path"
            elif installpkg "$pkg_path" >/dev/null 2>&1; then
                echo "Installing $display_name version: $new_version"
                echo "✅ Successfully installed $display_name version: $new_version"
            else
                echo "❌ Failed to install $display_name"
                return 1
            fi
        else
            if [ "$ALLOW_UPGRADE" != true ] && [ "$ALLOW_INSTALL" = true ]; then
                echo "⚠️ ALLOW_INSTALL is set to false so skipping install"
            elif [ "$ALLOW_UPGRADE" = true ] && [ "$ALLOW_INSTALL" != true ]; then
                echo "ℹ️  ALLOW_UPGRADE doesn't apply so ignoring"
                echo "⚠️ ALLOW_INSTALL is set to false so skipping install"
            elif [ "$ALLOW_UPGRADE" != true ] && [ "$ALLOW_INSTALL" != true ]; then
                echo "⚠️ No options set to true in configuration. Set ALLOW_INSTALL or FORCE_REINSTALL to true to install"
            fi
        fi
    fi
}

# === NETCAT ===
pkg_name="$(get_latest_github_pkg_name "netcat-openbsd-")"
if [ -z "$pkg_name" ]; then
    echo "❌ Could not find netcat-openbsd package"
    exit 1
fi
pkg_url="https://github.com/jcofer555/unraid_packages/raw/refs/heads/main/$pkg_name"
pkg_check="ls /var/log/packages | grep -q '^netcat-openbsd-'"
slack_pkg_id="netcat-openbsd"
display_name="Netcat-openbsd"

manage_package "$pkg_name" "$pkg_url" "$pkg_check" "$slack_pkg_id" "$display_name" || {
    echo "❌ Aborting: netcat-openbsd failed. libmd will not be processed."
    exit 1
}

# === LIBMD ===
pkg_name="$(get_latest_github_pkg_name "libmd-")"
if [ -z "$pkg_name" ]; then
    echo "❌ Could not find libmd package"
    exit 1
fi
pkg_url="https://github.com/jcofer555/unraid_packages/raw/refs/heads/main/$pkg_name"
pkg_check="ldconfig -p | grep -q libmd.so.0"
slack_pkg_id="libmd"
display_name="Libmd"

manage_package "$pkg_name" "$pkg_url" "$pkg_check" "$slack_pkg_id" "$display_name"
```
