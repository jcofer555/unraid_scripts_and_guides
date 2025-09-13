```bash
#!/bin/sh

# Variables
SHARE_TREE_PATH="/mnt/user/data/sharestree"
DISK_TREE_PATH="/mnt/user/data/diskstree"
SHARES_TO_SCAN=(data mymedia)
DISKS_TO_SCAN=(disk1 disk2 disk3)

    #### DON'T CHANGE ANYTHING BELOW HERE ####

echo "****Starting scan for shares****"
echo
for share in "${SHARES_TO_SCAN[@]}"; do
    fullpath="/mnt/user/$share"
    echo "Scanning array tree for $fullpath"
    if tree -o "$SHARE_TREE_PATH/${share}.txt" "$fullpath"; then
        echo "Tree for $fullpath saved to $SHARE_TREE_PATH/${share}.txt"
        echo
    else
        echo "Failed to scan array tree for $fullpath"
    fi
done

echo "****Starting scan for disks****"
echo
for disk in "${DISKS_TO_SCAN[@]}"; do
    fullpath="/mnt/$disk"
    echo "Scanning disk tree for $fullpath"
    if mkdir -p "$DISK_TREE_PATH/$disk"; then
        echo "Directory created for $disk in $DISK_TREE_PATH"
    else
        echo "Failed to create directory for disk $disk"
    fi

    if tree -o "$DISK_TREE_PATH/$disk/disktree.txt" "$fullpath"; then
        echo "Tree for $fullpath saved to $DISK_TREE_PATH/$disk/disktree.txt"
        echo
    else
        echo "Failed to scan disk tree for $fullpath"
    fi
done```
