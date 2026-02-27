#!/usr/bin/env bash
# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║                                                                           ║
# ║   cPanel TMP Manager v1.0.0                                               ║
# ║                                                                           ║
# ╠═══════════════════════════════════════════════════════════════════════════╣
# ║   Autor:   Percio Castelo                                                 ║
# ║   Contato: percio@evolya.com.br | contato@perciocastelo.com.br            ║
# ║   Web:     https://perciocastelo.com.br                                   ║
# ║                                                                           ║
# ║   Função:  Monitor, resize, and secure /tmp on cPanel servers             ║
# ║                                                                           ║
# ╚═══════════════════════════════════════════════════════════════════════════╝

# Ensure the script is running as root
if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root."
   exit 1
fi

# Configuration
TMP_ALERT_ENABLED=true
ALERT_THRESHOLD=80
VAR_TMP="/var/tmp"
TMP_DIR="/tmp"
TMP_DSK="/usr/tmpDSK"
LOG_FILE="/var/log/tmp-manager.log"

# Get /tmp information reliably
# We use --output to ensure consistent columns regardless of disk name length
read TMP_SOURCE TMP_SIZE TMP_USED TMP_AVAIL TMP_PERCENT TMP_TYPE <<< $(df -h --output=source,size,used,avail,pcent,fstype "$TMP_DIR" | tail -1)

# Remove % for numeric comparison
PERCENT_VAL=${TMP_PERCENT%\%}

echo "--- Partition Info ---"
echo "Mount Point: $TMP_DIR ($TMP_SOURCE)"
echo "FS Type:     $TMP_TYPE"
echo "Usage:       $TMP_USED / $TMP_SIZE ($TMP_PERCENT)"
echo "-----------------------"

# Check threshold
SHOULD_FIX=false
if [[ "$TMP_ALERT_ENABLED" == true ]]; then
    if (( PERCENT_VAL >= ALERT_THRESHOLD )); then
        echo "⚠️  ALERT: /tmp usage is above ${ALERT_THRESHOLD}%!"
        SHOULD_FIX=true
    else
        echo "✅ /tmp usage is within safe limits."
    fi
fi

# Ask for user confirmation
if [[ "$SHOULD_FIX" == "true" ]]; then
    read -p "High usage detected. Start optimization procedure? [y/N]: " START_FIX
    if [[ ! "$START_FIX" =~ ^[Yy]$ ]]; then
        echo "Operation cancelled by user."
        exit 0
    fi
else
    # Allow manual override if user just wants to resize
    read -p "Do you want to manually trigger the resize/fix process? [y/N]: " MANUAL_FIX
    if [[ ! "$MANUAL_FIX" =~ ^[Yy]$ ]]; then
        exit 0
    fi
fi

echo "Step 1: Cleaning files older than 12 hours..."
if command -v tmpwatch &> /dev/null; then
    tmpwatch --mtime 12 "$VAR_TMP" >> "$LOG_FILE" 2>&1
    echo "Files removed. Check $LOG_FILE for details."
else
    echo "⚠️  tmpwatch not found. Skipping cleanup."
fi

# Backup procedure if using tmpfs (RAM)
if [[ "$TMP_TYPE" == "tmpfs" ]]; then
    BACKUP_DIR="/root/tmp_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    cp -a /tmp/* "$BACKUP_DIR/" 2>/dev/null || true
    echo "✅ Backup created at $BACKUP_DIR"
fi

# Service management: MySQL/MariaDB often locks /tmp
DB_SERVICE=$(systemctl list-units --type=service | grep -E 'mariadb|mysql' | awk '{print $1}' | head -1)
if [[ -n "$DB_SERVICE" ]]; then
    echo "Stopping $DB_SERVICE to release file locks..."
    systemctl stop "$DB_SERVICE"
fi

# Unmounting procedure
echo "Unmounting partitions..."
for target in "$VAR_TMP" "$TMP_DIR"; do
    if mountpoint -q "$target"; then
        umount -l "$target" || echo "⚠️  Could not unmount $target (lazy unmount initiated)"
    fi
done

# Handle physical loopback file if exists
if [[ -f "$TMP_DSK" ]]; then
    echo "Removing old loopback file: $TMP_DSK"
    rm -f "$TMP_DSK"
fi

# Resize Logic
if [[ "$TMP_TYPE" == "tmpfs" ]]; then
    read -p "Enter new size for tmpfs (e.g., 4096M): " NEW_SIZE
    mount -o remount,size=$NEW_SIZE "$TMP_DIR"
    echo "✅ tmpfs resized to $NEW_SIZE"
    
    # Restore backup
    if [[ -d "$BACKUP_DIR" ]]; then
        cp -a "$BACKUP_DIR"/* /tmp/ 2>/dev/null || true
        echo "✅ Backup files restored."
    fi
else
    echo "Running cPanel securetmp script..."
    /scripts/securetmp --auto
fi

# Restart Database
if [[ -n "$DB_SERVICE" ]]; then
    echo "Restarting $DB_SERVICE..."
    systemctl start "$DB_SERVICE"
fi

systemctl daemon-reload
echo "✨ Procedure complete."