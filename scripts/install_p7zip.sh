#!/bin/bash

# Ensure extra folder on flash drive exists
echo "Checking if extra exists on the flash drive"
if [ -d "/boot/extra" ]; then
    echo "Extra folder already exists on the flash drive"
else
    echo "Extra folder does not exist, Attempting to create it on the flash drive"
    if mkdir -p "/boot/extra"; then
        echo "Successfully created the extra folder on the flash drive"
    else
        echo "Failed to create the extra folder on the flash drive"
        exit 1
    fi
fi

# Function to download a package if it doesn't already exist
download_package() {
    local pkg_name=$1
    local pkg_url=$2
    local pkg_path="/boot/extra/$pkg_name"

    if [ -f "$pkg_path" ]; then
        echo "Package $pkg_name already exists in /boot/extra, skipping download"
    else
        echo "Downloading $pkg_name"
        if wget -q -O "$pkg_path" "$pkg_url"; then
            echo "Successfully downloaded $pkg_name to the flash drive extra folder"
        else
            echo "Failed to download $pkg_name from $pkg_url"
            return 1
        fi
    fi
}

# Function to install a package after verifying it exists and format is correct
install_package() {
    local pkg_name=$1
    local pkg_url=$2
    local pkg_path="/boot/extra/$pkg_name"
    local check_cmd=$3

    # Ensure the package exists before checking installation status
    if [ -f "$pkg_path" ]; then
        echo "Package $pkg_name already exists in /boot/extra"
    else
        echo "Package $pkg_name not found in /boot/extra/, attempting to download"
        if ! download_package "$pkg_name" "$pkg_url"; then
            echo "Failed to retrieve $pkg_name, aborting installation"
            return 1
        fi
    fi

    # Check if the file is empty. If empty delete and redownload
    if [ ! -s "$pkg_path" ]; then
        echo "Error: $pkg_name exists but is empty. Deleting and redownloading"
        rm -f "$pkg_path"
        if ! download_package "$pkg_name" "$pkg_url"; then
            echo "Failed to re-download $pkg_name, aborting installation"
            return 1
        fi
    else
        echo "Package $pkg_name is valid"
    fi

    # Verify the package format. If incorrect format delete and redownload
    if file "$pkg_path" | grep -q 'XZ compressed data\|gzip compressed data'; then
        echo "Package $pkg_name format is correct"
    else
        echo "Error: $pkg_name does not appear to be a valid Slackware package. Deleting and redownloading"
        rm -f "$pkg_path"
        if ! download_package "$pkg_name" "$pkg_url"; then
            echo "Failed to re-download $pkg_name, aborting installation"
            return 1
        fi
    fi

    # Check if package is already installed before proceeding
    if eval "$check_cmd"; then
        echo "$pkg_name is already installed, skipping installation"
        return 0
    fi

    # Attempt installation
    echo "Installing $pkg_name"
    if installpkg "$pkg_path" >/dev/null 2>&1; then
        echo "$pkg_name has been successfully installed"
    else
        echo "Failed to install $pkg_name"
        return 1
    fi
}

# Define package variables
pkg_name="p7zip-17.05-x86_64-3cf.txz"
pkg_url="https://github.com/jcofer555/unraid_packages/raw/refs/heads/main/$pkg_name"
pkg_path="/boot/extra/$pkg_name"
pkg_check="command -v 7z >/dev/null 2>&1"

# Install p7zip if missing
install_package "$pkg_name" "$pkg_url" "$pkg_check"
