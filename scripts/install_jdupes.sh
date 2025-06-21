#!/bin/bash

# === CONFIGURATION ===
REMOVE_EXISTING_INSTALL=false  # Set to true to remove existing jdupes and libjodycode packages before install
DRY_RUN=false                  # Set to true to simulate actions without making changes

# DON'T CHANGE ANYTHING BELOW HERE

# === DRY RUN NOTICE ===
if [ "$DRY_RUN" = true ]; then
    echo "🧪 DRY_RUN ENABLED: No changes will be made. Commands will be echoed but not executed 🧪"
fi

# === INSTALLATION FUNCTION ===
manage_package() {
    local pkg_name="$1"
    local pkg_url="$2"
    local check_cmd="$3"
    local slack_pkg_name="$4"
    local display_name="$5"

    local pkg_path="/boot/extra/$pkg_name"
    display_name="${display_name:-$pkg_name}"
    slack_pkg_name="${slack_pkg_name:-$display_name}"

    # Ensure /boot/extra exists
    echo "Checking if /boot/extra exists on the flash drive"
    if [ -d "/boot/extra" ]; then
        echo "Extra folder already exists on the flash drive"
    else
        echo "Extra folder does not exist, attempting to create it"
        if [ "$DRY_RUN" = true ]; then
            echo "Successfully created the extra folder on the flash drive"
        elif mkdir -p "/boot/extra"; then
            echo "Successfully created the extra folder on the flash drive"
        else
            echo "Failed to create the extra folder on the flash drive"
            exit 1
        fi
    fi

    # Check for existing install
    if eval "$check_cmd"; then
        echo "$display_name is already installed"

        if [ "$REMOVE_EXISTING_INSTALL" = true ]; then
            echo "Removing existing $display_name installation"
            if [ "$DRY_RUN" = true ]; then
                echo "Successfully removed $display_name"
            elif removepkg "$slack_pkg_name" >/dev/null 2>&1; then
                echo "Successfully removed $display_name"
            else
                echo "Failed to remove $display_name"
            fi
        else
            echo "REMOVE_EXISTING_INSTALL is set to false, skipping removal"
            echo "Skipping installation of $display_name since it is already installed"
            return 0
        fi
    else
        echo "$display_name is not currently installed"
    fi

    # Download package if not present
    if [ -f "$pkg_path" ]; then
        echo "Package $pkg_name already exists in /boot/extra, skipping download"
    else
        echo "Downloading $pkg_name"
        if [ "$DRY_RUN" = true ]; then
            echo "Successfully downloaded $pkg_name to the flash drive"
        elif wget -q -O "$pkg_path" "$pkg_url"; then
            echo "Successfully downloaded $pkg_name to the flash drive"
        else
            echo "Failed to download $pkg_name from $pkg_url"
            return 1
        fi
    fi

    # Check for empty file
    if [ ! -s "$pkg_path" ]; then
        echo "Error: $pkg_name exists but is empty. Redownloading"
        [ "$DRY_RUN" = false ] && rm -f "$pkg_path"
        if [ "$DRY_RUN" = true ]; then
            echo "Successfully re-downloaded $pkg_name"
        elif wget -q -O "$pkg_path" "$pkg_url"; then
            echo "Successfully re-downloaded $pkg_name"
        else
            echo "Failed to re-download $pkg_name"
            return 1
        fi
    else
        echo "Package $pkg_name is valid"
    fi

    # Verify file format
    if file "$pkg_path" | grep -q 'XZ compressed data\|gzip compressed data'; then
        echo "Package $pkg_name format is correct"
    else
        echo "Error: $pkg_name is not a valid Slackware package. Redownloading"
        [ "$DRY_RUN" = false ] && rm -f "$pkg_path"
        if [ "$DRY_RUN" = true ]; then
            echo "Successfully re-downloaded $pkg_name"
        elif wget -q -O "$pkg_path" "$pkg_url"; then
            echo "Successfully re-downloaded $pkg_name"
        else
            echo "Failed to re-download $pkg_name"
            return 1
        fi
    fi

    # Install package
    echo "Installing $display_name"
    if [ "$DRY_RUN" = true ]; then
        echo "$pkg_name has been successfully installed"
    elif installpkg "$pkg_path" >/dev/null 2>&1; then
        echo "$pkg_name has been successfully installed"
    else
        echo "Failed to install $pkg_name"
        return 1
    fi
}

# === LIBJODYCODE ===
pkg_name="libjodycode-3.1.1-x86_64-2_SBo.tgz"
pkg_url="https://github.com/jcofer555/unraid_packages/raw/refs/heads/main/$pkg_name"
pkg_check="ldconfig -p | grep -q libjodycode.so.3"
slack_pkg_id="libjodycode"
display_name="libjodycode"

manage_package "$pkg_name" "$pkg_url" "$pkg_check" "$slack_pkg_id" "$display_name"

# === JDUPES ===
pkg_name="jdupes-1.28.0-x86_64-2_SBo.tgz"
pkg_url="https://github.com/jcofer555/unraid_packages/raw/refs/heads/main/$pkg_name"
pkg_check="which jdupes >/dev/null 2>&1"
slack_pkg_id="jdupes"
display_name="jdupes"

manage_package "$pkg_name" "$pkg_url" "$pkg_check" "$slack_pkg_id" "$display_name"