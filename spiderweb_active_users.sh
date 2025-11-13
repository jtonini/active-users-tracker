#!/bin/bash
# spiderweb_active_users.sh - Find active users on web computing server
# Usage: ./spiderweb_active_users.sh [START_DATE] [END_DATE]
# Example: ./spiderweb_active_users.sh 2024-09-01 2024-11-01

# Default to last 3 months if no dates provided
START_DATE="${1:-$(date -d '3 months ago' +%Y-%m-%d)}"
END_DATE="${2:-$(date +%Y-%m-%d)}"

echo "spiderweb: Finding active users between $START_DATE and $END_DATE"
echo "===================================================================="

# Temporary file for results
TEMP_FILE="/tmp/active_users_quick_$$.txt"
> "$TEMP_FILE"

# Counter for progress
checked=0
found=0

# Get real users and check for recent files in date range
getent passwd | awk -F: '$3 >= 1000 && $3 != 65534 {print $1":"$6}' | while IFS=: read user home; do
    [ ! -d "$home" ] && continue
    ((checked++))
    
    # Progress indicator every 10 users
    [ $((checked % 10)) -eq 0 ] && echo "   ...checked $checked users, found $found active" >&2
    
    # Find most recent file in date range (limit depth for performance)
    # Use -L to follow symlinks (faculty may share files via symlinks)
    # Use maxdepth 5 to avoid very deep searches, redirect errors
    recent_file=$(find -L "$home" -maxdepth 5 -type f -newermt "$START_DATE" ! -newermt "$END_DATE 23:59:59" \
                  -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1)
    
    if [ ! -z "$recent_file" ]; then
        ((found++))
        timestamp=$(echo "$recent_file" | cut -d' ' -f1 | cut -d'.' -f1)
        date_str=$(date -d "@$timestamp" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "unknown")
        echo "$timestamp|$user|$date_str"
    fi
done | sort -n > "$TEMP_FILE"

echo ""
echo "===================================================================="
echo "Checked: $checked users"
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
