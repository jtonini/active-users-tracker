#!/bin/bash
# spiderweb_active_users.sh - Find active users on Spiderweb (web-based computing server)
# Streamlined for systems with only home directories (no SSH logs or scratch)
# Usage: ./spiderweb_active_users.sh [START_DATE] [END_DATE]
# Example: ./spiderweb_active_users.sh 2024-09-01 2024-11-01
#
# Set DEBUG=1 to see detailed error messages:
#   DEBUG=1 ./spiderweb_active_users.sh 2024-09-01 2024-11-01

# Debug mode
DEBUG="${DEBUG:-0}"

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

# Associative arrays for tracking
declare -A active_users        # username -> detection method
declare -A user_last_activity  # username -> timestamp of last activity

# Function to check if valid username
is_valid_user() {
    local username=$1
    # Skip if all numeric
    [[ "$username" =~ ^[0-9]+$ ]] && return 1
    # Skip known non-users
    case "$username" in
        dataset_*|test_*|tmp_*|backup_*|lost+found|root|bin|daemon|sync|halt)
            return 1
            ;;
    esac
    # Check if user exists in system (even if LDAP)
    if id "$username" &>/dev/null; then
        # Additional check: user should have UID >= 1000 (not a system user)
        uid=$(id -u "$username" 2>/dev/null)
        if [ ! -z "$uid" ] && [ "$uid" -ge 1000 ]; then
            return 0
        fi
    fi
    # Don't include users that don't exist
    return 1
}

# Function to update last activity timestamp
update_last_activity() {
    local user=$1
    local timestamp=$2
    
    # If no timestamp recorded yet, or this one is newer
    if [ -z "${user_last_activity[$user]}" ] || [ "$timestamp" -gt "${user_last_activity[$user]}" ]; then
        user_last_activity[$user]=$timestamp
    fi
}

# Check /home directories
echo "Checking file activity between $START_DATE and $END_DATE"
echo "=============================================================="

checked=0
skipped=0
errors=0
error_users=()

# Get all users from passwd database
while IFS=: read -r username _ uid _; do
    # Skip system users (UID < 1000)
    [ "$uid" -lt 1000 ] && continue
    
    ((checked++))
    [ $((checked % 50)) -eq 0 ] && echo "  Progress: $checked checked, ${#active_users[@]} active, $skipped skipped, $errors errors"
    
    is_valid_user "$username" || continue
    
    # Skip if user already found active
    if [ ! -z "${active_users[$username]}" ]; then
        ((skipped++))
        continue
    fi
    
    homedir="/home/$username"
    [ ! -d "$homedir" ] && continue
    
    # Show which user we're checking (useful for debugging hangs)
    [ $DEBUG -eq 1 ] && echo "  DEBUG: Checking /home for user: $username"
    
    # Find any file in the date range, stop immediately when found
    # Timeout after 10 seconds to prevent hanging on problematic directories
    found_file=$(timeout 10 find -L "$homedir" -type f -newermt "$START_DATE" ! -newermt "$END_DATE 23:59:59" \
                  -print -quit 2>/dev/null)
    find_exit=$?
    
    # If we got a file path, user is active
    if [ ! -z "$found_file" ]; then
        # User is active - we found at least one file
        # Use END_DATE as timestamp since we don't know exact time
        timestamp=$(date -d "$END_DATE" +%s)
        active_users[$username]="home"
        update_last_activity "$username" "$timestamp"
    elif [ $find_exit -eq 124 ]; then
        # Timeout - directory too large or hung filesystem
        [ $DEBUG -eq 1 ] && echo "  DEBUG: User $username timed out (directory too large or NFS issue)"
        ((errors++))
        error_users+=("$username (timeout)")
    elif [ $find_exit -ne 0 ] && [ $find_exit -ne 1 ]; then
        # Other error (not timeout, not normal -quit exit)
        ((errors++))
        error_users+=("$username")
        [ $DEBUG -eq 1 ] && echo "  DEBUG: User $username failed with exit code $find_exit"
    fi
    # If no file and exit 0 or 1 = user just not active in this period (normal)
done < <(getent passwd | sort -t: -k3 -n)

echo ""
echo "=============================================================="
echo "RESULTS"
echo "=============================================================="
echo "Total checked: $checked"
echo "Skipped (user doesn't exist): $skipped"
echo "Skipped (errors/timeouts): $errors"
echo "Active users: ${#active_users[@]}"

if [ ${#error_users[@]} -gt 0 ]; then
    echo ""
    echo "Users with errors/timeouts:"
    printf '%s\n' "${error_users[@]}" | head -10
    echo ""
fi

# Create sorted list with timestamps
> /tmp/active_users_detailed.txt
for user in "${!active_users[@]}"; do
    last_activity="${user_last_activity[$user]}"
    last_activity_date=$(date -d "@$last_activity" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "unknown")
    echo "$last_activity|$user|$last_activity_date|${active_users[$user]}"
done | sort -n > /tmp/active_users_detailed.txt

# Extract just usernames sorted by activity
cut -d'|' -f2 /tmp/active_users_detailed.txt > /tmp/active_users.txt

echo "FIRST 5 USERS (earliest activity):"
echo "-----------------------------------"
head -5 /tmp/active_users_detailed.txt | while IFS='|' read ts user date methods; do
    printf "%-20s %s\n" "$user" "$date"
done

echo ""
echo "LAST 5 USERS (most recent activity):"
echo "-------------------------------------"
tail -5 /tmp/active_users_detailed.txt | while IFS='|' read ts user date methods; do
    printf "%-20s %s\n" "$user" "$date"
done

echo ""
echo "Lists saved to:"
echo "  /tmp/active_users.txt (usernames only)"
echo "  /tmp/active_users_detailed.txt (with timestamps)"
