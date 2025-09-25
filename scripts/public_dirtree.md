```bash
#!/bin/sh

# Variables
MOUNT_POINT="/mnt/user/data/computer/unraidstuff/dirtree"

#### DON'T CHANGE ANYTHING BELOW HERE ####
#### REQUIRE PYTHON3 PLUGIN TO BE INSTALLED ####

# Check if python3 is installed
if ! command -v python3 >/dev/null 2>&1; then
    echo "Error: python3 is not installed. Please install the Python3 plugin from apps page by rysz and try again."
    exit 1
else
    echo "Python3 is installed."
fi

# Ensure disktree backup location exists
echo "Checking if backup destination exists $MOUNT_POINT"
if [ -d "$MOUNT_POINT" ]; then
    echo "Backup destination already exists $MOUNT_POINT"
else
    echo "Backup destination does not exist, Attempting to create $MOUNT_POINT"
    if mkdir -p "$MOUNT_POINT"; then
        echo "Successfully created backup destination $MOUNT_POINT"
    else
        echo "Failed to create backup destination $MOUNT_POINT"
        exit 1
    fi
fi

# Change ownership of the disktree backup directory
echo "Changing ownership of $MOUNT_POINT"
if chown -R jcofer555:users "$MOUNT_POINT"; then
    echo "Successfully changed ownership of $MOUNT_POINT"
    echo
else
    echo "Failed to change ownership of $MOUNT_POINT"
fi

# Function to check if a Python package is installed
check_python_package() {
    python3 -c "import $1" >/dev/null 2>&1
}

# Packages to check
packages=("pandas" "openpyxl")

for pkg in "${packages[@]}"; do
    echo "Checking for Python package: $pkg"
    if check_python_package "$pkg"; then
        echo "$pkg is already installed"
    else
        echo "$pkg not found, installing..."
        if pip install "$pkg"; then
            echo "Successfully installed $pkg"
        else
            echo "Failed to install $pkg via pip"
            exit 1
        fi
    fi
done
echo

# Run dirtree python script
echo "Starting dirtree python script"
chmod +x "/mnt/user/data/computer/unraidstuff/dirtree.py"
/usr/bin/python3 "/mnt/user/data/computer/unraidstuff/dirtree.py" 2>&1
echo "Dirtree python script finished"
echo

```
