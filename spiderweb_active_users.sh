#!/bin/bash
# spiderweb_active_users.sh - Find active users on web computing server
# Usage: ./spiderweb_active_users.sh [START_DATE] [END_DATE]
# Example: ./spiderweb_active_users.sh 2024-09-01 2024-11-01

# Default to last 3 months if no dates provided
START_DATE="${1:-$(date -d '3 months ago' +%Y-%m-%d)}"
END_DATE="${2:-$(date +%Y-%m-%d)}"

# Calculate days ago for -mtime (from today to START_DATE)
DAYS_AGO=$(( ($(date +%s) - $(date -d "$START_DATE" +%s)) / 86400 ))

echo "spiderweb: Finding active users since $START_DATE ($DAYS_AGO days ago)"
echo "===================================================================="
echo ""

# Associative array to track active users
declare -A active_users
declare -A user_last_activity

# Counters
checked=0
skipped=0
active_count=0

# Check each directory in /home
for homedir in /home/*; do
    [ ! -d "$homedir" ] && continue
    username=$(basename "$homedir")
    
    # Skip lost+found
    [[ "$username" == "lost+found" ]] && continue
    
    ((checked++))
    
    # Progress every 50 users
    if [ $((checked % 50)) -eq 0 ]; then
        echo "  Progress: $checked checked, $active_count active, $skipped skipped"
    fi
    
    # Check if user exists
    if ! id "$username" &>/dev/null; then
        ((skipped++))
        continue
    fi
    
    # Find most recent file since START_DATE (using -mtime for better performance)
    # Use timeout to avoid hanging on problematic directories
    recent_file=$(timeout 5 find -L "$homedir" -type f -mtime -$DAYS_AGO \
                  -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1)
    
    if [ ! -z "$recent_file" ]; then
        timestamp=$(echo "$recent_file" | cut -d' ' -f1 | cut -d'.' -f1)
        date_str=$(date -d "@$timestamp" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "unknown")
        active_users[$username]="$timestamp|$date_str"
        ((active_count++))
    fi
done

echo ""
echo "===================================================================="
echo "RESULTS"
echo "===================================================================="
echo "Total checked: $checked"
echo "Skipped (user doesn't exist): $skipped"
echo "Active users: $active_count"
echo ""

# Create output file with timestamps
TEMP_FILE="/tmp/active_users_detailed.txt"
> "$TEMP_FILE"

for user in "${!active_users[@]}"; do
    IFS='|' read timestamp date_str <<< "${active_users[$user]}"
    echo "$timestamp|$user|$date_str"
done | sort -n > "$TEMP_FILE"

if [ $active_count -gt 0 ]; then
    echo "FIRST 5 USERS (earliest activity):"
    echo "-----------------------------------"
    head -5 "$TEMP_FILE" | while IFS='|' read ts user date; do
        printf "%-20s %s\n" "$user" "$date"
    done
    
    echo ""
    echo "LAST 5 USERS (most recent activity):"
    echo "-------------------------------------"
    tail -5 "$TEMP_FILE" | while IFS='|' read ts user date; do
        printf "%-20s %s\n" "$user" "$date"
    done
    echo ""
fi

# Save results
cut -d'|' -f2 "$TEMP_FILE" > /tmp/active_users.txt

echo "Lists saved to:"
echo "  /tmp/active_users.txt (usernames only)"
echo "  /tmp/active_users_detailed.txt (with timestamps)"
