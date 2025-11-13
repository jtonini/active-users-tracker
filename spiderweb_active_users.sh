#!/bin/bash
# active_users_count.sh - Quick count of active users with date range
# Usage: ./active_users_count.sh [START_DATE] [END_DATE]
# Example: ./active_users_count.sh 2024-09-01 2024-11-01

# Default to last 3 months if no dates provided
START_DATE="${1:-$(date -d '3 months ago' +%Y-%m-%d)}"
END_DATE="${2:-$(date +%Y-%m-%d)}"

echo "Checking file activity between $START_DATE and $END_DATE"
echo "=============================================================="

# Temporary file for results
TEMP_FILE="/tmp/active_users_quick_$$.txt"
> "$TEMP_FILE"

# Get real users and check for recent files in date range
getent passwd | awk -F: '$3 >= 1000 && $3 != 65534 {print $1":"$6}' | while IFS=: read user home; do
    [ ! -d "$home" ] && continue
    
    # Find most recent file in date range
    recent_file=$(find "$home" -type f -newermt "$START_DATE" ! -newermt "$END_DATE 23:59:59" \
                  -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1)
    
    if [ ! -z "$recent_file" ]; then
        timestamp=$(echo "$recent_file" | cut -d' ' -f1 | cut -d'.' -f1)
        date_str=$(date -d "@$timestamp" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "unknown")
        echo "$timestamp|$user|$date_str"
    fi
done | sort -n > "$TEMP_FILE"

echo ""
echo "Total active users: $(wc -l < "$TEMP_FILE")"
echo ""

if [ $(wc -l < "$TEMP_FILE") -gt 0 ]; then
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
cp "$TEMP_FILE" /tmp/active_users_detailed.txt

echo "Lists saved to:"
echo "  /tmp/active_users.txt (usernames only)"
echo "  /tmp/active_users_detailed.txt (with timestamps)"
