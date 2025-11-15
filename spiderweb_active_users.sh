#!/bin/bash
# spiderweb_active_users.sh - Find active users on web computing server
# Usage: ./spiderweb_active_users.sh [START_DATE] [END_DATE]
# Example: ./spiderweb_active_users.sh 2024-09-01 2024-11-01

# Default to last 3 months if no dates provided
START_DATE="${1:-$(date -d '3 months ago' +%Y-%m-%d)}"
END_DATE="${2:-$(date +%Y-%m-%d)}"

# Calculate days ago from today
START_DAYS_AGO=$(( ($(date +%s) - $(date -d "$START_DATE" +%s)) / 86400 ))
END_DAYS_AGO=$(( ($(date +%s) - $(date -d "$END_DATE" +%s)) / 86400 ))
DAYS_SPAN=$(( START_DAYS_AGO - END_DAYS_AGO ))

echo "spiderweb: Finding active users between $START_DATE and $END_DATE"
echo "           (from $START_DAYS_AGO days ago to $END_DAYS_AGO days ago, spanning $DAYS_SPAN days)"
echo "===================================================================="

# Associative array to track active users
declare -A active_users
declare -A user_last_activity

# Counters
checked=0
skipped=0
errors=0
active_count=0

# Check /home directories
echo "Checking /home directories..."

for homedir in /home/*; do
    [ ! -d "$homedir" ] && continue
    username=$(basename "$homedir")
    
    # Skip lost+found
    [[ "$username" == "lost+found" ]] && continue
    
    ((checked++))
    
    # Progress every 50 users
    if [ $((checked % 50)) -eq 0 ]; then
        echo "   ...checked $checked, skipped $skipped already active, $errors errors"
    fi
    
    # Check if user exists
    if ! id "$username" &>/dev/null; then
        ((skipped++))
        continue
    fi
    
    # Use sudo to run as the user (so we can read their files)
    # -n flag: non-interactive, fails if password needed
    # Calculate DAYS_AGO for -mtime (from today to START_DATE)
    DAYS_AGO=$(( ($(date +%s) - $(date -d "$START_DATE" +%s)) / 86400 ))
    
    result=$(sudo -n -u "$username" bash -c "timeout 10 find -L '$homedir' -type f -mtime -$DAYS_AGO -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1" 2>/dev/null)
    
    # Check sudo exit code
    if [ $? -eq 1 ]; then
        # Password required, skip this user
        ((errors++))
        continue
    fi
    
    if [ ! -z "$result" ]; then
        timestamp=$(echo "$result" | cut -d' ' -f1 | cut -d'.' -f1)
        date_str=$(date -d "@$timestamp" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "unknown")
        active_users[$username]="$timestamp|$date_str"
        ((active_count++))
    fi
done

echo "   Checked: $checked, Skipped: $skipped (user doesn't exist), Errors: $errors, Total active: $active_count"

echo ""
echo "===================================================================="
echo "Total Active Users: $active_count"
echo ""

# Create output file with timestamps
TEMP_FILE="/tmp/active_users_detailed.txt"
> "$TEMP_FILE"

for user in "${!active_users[@]}"; do
    IFS='|' read timestamp date_str <<< "${active_users[$user]}"
    echo "$timestamp|$user|$date_str|home"
done | sort -n > "$TEMP_FILE"

if [ $active_count -gt 0 ]; then
    echo "FIRST 5 USERS TO BECOME ACTIVE (earliest activity):"
    echo "---------------------------------------------------"
    head -5 "$TEMP_FILE" | while IFS='|' read ts user date methods; do
        printf "%-20s %s (via: %s)\n" "$user" "$date" "$methods"
    done
    
    echo ""
    echo "LAST 5 USERS TO BECOME ACTIVE (most recent activity):"
    echo "------------------------------------------------------"
    tail -5 "$TEMP_FILE" | while IFS='|' read ts user date methods; do
        printf "%-20s %s (via: %s)\n" "$user" "$date" "$methods"
    done
    
    echo ""
fi

# Save results
cut -d'|' -f2 "$TEMP_FILE" > /tmp/active_users.txt

echo "Full list saved to:"
echo "  /tmp/active_users.txt (usernames only)"
echo "  /tmp/active_users_detailed.txt (with timestamps and methods)"
