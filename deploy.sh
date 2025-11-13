#!/bin/bash
# deploy.sh - Deploy active_users script with hostname-aware symlinks
#
# Usage: ./deploy.sh [--local|--system]
#   --local:  Create symlink in ~/bin (default)
#   --system: Create symlink in /usr/local/sw/bin (requires permissions)

set -e  # Exit on error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYMENT_MODE="${1:---local}"

# Detect hostname and determine which script to use
HOSTNAME=$(hostname -s)
case "$HOSTNAME" in
    spydur*|arachne*)
        # HPC cluster - use comprehensive script
        SOURCE_SCRIPT="$SCRIPT_DIR/spydur_active_users.sh"
        SCRIPT_TYPE="spydur (HPC cluster)"
        ;;
    spiderweb*)
        # Workstation server - use simpler script
        SOURCE_SCRIPT="$SCRIPT_DIR/spiderweb_active_users.sh"
        SCRIPT_TYPE="spiderweb (workstation)"
        ;;
    *)
        echo "ERROR: Unknown hostname '$HOSTNAME'"
        echo ""
        echo "This script only recognizes production servers:"
        echo "  - spydur* or arachne*  -> uses spydur_active_users.sh (HPC cluster)"
        echo "  - spiderweb*           -> uses spiderweb_active_users.sh (workstation)"
        echo ""
        echo "For development machines or other hosts, manually deploy:"
        echo ""
        echo "  For HPC cluster environment:"
        echo "    ln -s $SCRIPT_DIR/spydur_active_users.sh /usr/local/sw/bin/active_users"
        echo ""
        echo "  For workstation/server environment:"
        echo "    ln -s $SCRIPT_DIR/spiderweb_active_users.sh /usr/local/sw/bin/active_users"
        echo ""
        exit 1
        ;;
esac

# Verify source script exists
if [ ! -f "$SOURCE_SCRIPT" ]; then
    echo "ERROR: Source script not found: $SOURCE_SCRIPT"
    exit 1
fi

# Determine target directory based on deployment mode
case "$DEPLOYMENT_MODE" in
    --local)
        TARGET_DIR="$HOME/bin"
        mkdir -p "$TARGET_DIR"
        ;;
    --system)
        TARGET_DIR="/usr/local/sw/bin"
        if [ ! -d "$TARGET_DIR" ]; then
            echo "ERROR: System directory does not exist: $TARGET_DIR"
            echo "Please create it first or use --local for user installation"
            exit 1
        fi
        if [ ! -w "$TARGET_DIR" ]; then
            echo "ERROR: No write permission to $TARGET_DIR"
            echo "Try: sudo ./deploy.sh --system"
            exit 1
        fi
        ;;
    *)
        echo "ERROR: Invalid deployment mode: $DEPLOYMENT_MODE"
        echo "Usage: $0 [--local|--system]"
        exit 1
        ;;
esac

TARGET_LINK="$TARGET_DIR/active_users"

echo "========================================"
echo "Active Users Tracker - Deployment"
echo "========================================"
echo "Hostname:      $HOSTNAME"
echo "Detected as:   $SCRIPT_TYPE"
echo "Source script: $SOURCE_SCRIPT"
echo "Target link:   $TARGET_LINK"
echo "========================================"
echo ""

# Remove existing symlink if it exists
if [ -L "$TARGET_LINK" ]; then
    echo "Removing existing symlink: $TARGET_LINK"
    rm "$TARGET_LINK"
elif [ -e "$TARGET_LINK" ]; then
    echo "ERROR: $TARGET_LINK exists but is not a symlink"
    echo "Please remove it manually first"
    exit 1
fi

# Create the symlink
echo "Creating symlink..."
ln -s "$SOURCE_SCRIPT" "$TARGET_LINK"

# Verify symlink was created
if [ -L "$TARGET_LINK" ] && [ -e "$TARGET_LINK" ]; then
    echo "✓ Symlink created successfully"
    echo ""
    ls -lh "$TARGET_LINK"
    echo ""
else
    echo "ERROR: Failed to create symlink"
    exit 1
fi

# Check if target directory is in PATH
if [[ ":$PATH:" != *":$TARGET_DIR:"* ]]; then
    echo "WARNING: $TARGET_DIR is not in your PATH"
    echo ""
    echo "Add to your PATH by adding this to ~/.bashrc:"
    echo "  export PATH=\"$TARGET_DIR:\$PATH\""
    echo ""
    echo "Or run with full path:"
    echo "  $TARGET_LINK"
    echo ""
else
    echo "✓ $TARGET_DIR is in your PATH"
    echo ""
    echo "You can now run:"
    echo "  active_users"
    echo "  active_users 2024-09-01"
    echo "  active_users 2024-09-01 2024-10-31"
    echo ""
fi

echo "========================================"
echo "Deployment complete!"
echo "========================================"
