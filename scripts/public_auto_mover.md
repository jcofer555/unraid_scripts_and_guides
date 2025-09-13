```bash
#!/bin/bash

# Configurable Variables
POOL_NAME="cache"      # Name of pool
THRESHOLD=5           # Threshold %
DRY_RUN="no"           # Set to "yes" to simulate without running mover

        #### DON'T CHANGE ANYTHING BELOW HERE ####

MOUNT_POINT="/mnt/${POOL_NAME}"

# Check if mover is already running
echo "🔍 Checking if mover is already running..."
if pgrep -x mover &>/dev/null; then
    echo "⏳ Mover detected. Sleeping 15s..."
    sleep 15
    if pgrep -x mover &>/dev/null; then
        echo "❌ Mover still running after 15s — exiting"
        exit 1
    else
        echo "✅ Mover has stopped — continuing"
    fi
else
    echo "✅ Mover not running — continuing"
fi

# Check disk usage
echo "🔍 Checking if $MOUNT_POINT is over ${THRESHOLD}% threshold"
USED=$(df -h --si "$MOUNT_POINT" | awk 'NR==2 {print $5}' | sed 's/%//')

# Validate USED is not empty
if [ -z "$USED" ]; then
    echo "❌ Failed to retrieve disk usage for $MOUNT_POINT — exiting"
    exit 1
fi

echo "📊 $POOL_NAME is currently ${USED}% full"

if [ "$USED" -le "$THRESHOLD" ]; then
    echo "🟢 Usage is under threshold — no action needed"
    exit 0
fi

echo "⚠️ $POOL_NAME is over threshold — mover trigger condition met"

# Dry run check
if [ "$DRY_RUN" = "yes" ]; then
    echo "🔧 Dry Run enabled — skipping mover start"
else
    echo "🛠️ Starting mover for $POOL_NAME..."
    mover start
fi

# After-action disk usage (optional)
USED2=$(df -h --si "$MOUNT_POINT" | awk 'NR==2 {print $5}' | sed 's/%//')
echo "📉 Post-trigger disk usage: ${USED2}% full"

echo "✅ Automover script completed"

```
