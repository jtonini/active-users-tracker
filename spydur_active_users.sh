#!/bin/bash
# active_users.sh - Find active users with date range support
# Usage: ./active_users.sh [START_DATE] [END_DATE]
# Example: ./active_users.sh 2024-09-01 2024-11-01
#
# Set DEBUG=1 to see detailed error messages:
#   DEBUG=1 ./active_users.sh 2024-09-01 2024-11-01

# Debug mode
DEBUG="${DEBUG:-0}"

# Default to last 3 months if no dates provided
START_DATE="${1:-$(date -d '3 months ago' +%Y-%m-%d)}"
END_DATE="${2:-$(date +%Y-%m-%d)}"

# Calculate days ago from today
START_DAYS_AGO=$(( ($(date +%s) - $(date -d "$START_DATE" +%s)) / 86400 ))
END_DAYS_AGO=$(( ($(date +%s) - $(date -d "$END_DATE" +%s)) / 86400 ))
DAYS_SPAN=$(( START_DAYS_AGO - END_DAYS_AGO ))

echo "spydur: Finding active users between $START_DATE and $END_DATE"
echo "        (from $START_DAYS_AGO days ago to $END_DAYS_AGO days ago, spanning $DAYS_SPAN days)"
echo "===================================================================="

# Associative arrays for tracking
declare -A active_users        # username -> detection methods
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
    # Don't include users that don't exist - removed fallback for "looks valid"
    # This prevents treating non-user directories as users
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

# Method 1: SSH logs (for recent logins)
echo "1. Checking SSH logs..."
if [ -r /var/log/secure ]; then
    while read line; do
        user=$(echo "$line" | awk '{for(i=1;i<=NF;i++) if($i=="for") print $(i+1)}')
        timestamp=$(date -d "$(echo "$line" | awk '{print $1, $2, $3}')" +%s 2>/dev/null)
        
        [ -z "$user" ] || [ -z "$timestamp" ] && continue
        is_valid_user "$user" || continue
        
        # Check if timestamp is within range
        if [ "$timestamp" -ge "$(date -d "$START_DATE" +%s)" ] && \
           [ "$timestamp" -le "$(date -d "$END_DATE" +%s)" ]; then
            active_users[$user]="${active_users[$user]:+${active_users[$user]},}ssh"
            update_last_activity "$user" "$timestamp"
        fi
    done < <(zgrep -h "Accepted" /var/log/secure* 2>/dev/null)
    echo "   Found ${#active_users[@]} valid users via SSH"
fi

# Method 2: /home directories
echo "2. Checking /home directories..."
checked=0
skipped=0
password_required=0
password_required_users=()
for homedir in /home/*; do
    [ ! -d "$homedir" ] && continue
    username=$(basename "$homedir")
    ((checked++))
    [ $((checked % 50)) -eq 0 ] && echo "   ...checked $checked, skipped $skipped already active, $password_required errors"
    is_valid_user "$username" || continue
    
    # Skip if user already found active (optimization)
    if [ ! -z "${active_users[$username]}" ]; then
        ((skipped++))
        continue
    fi
    
    # Show which user we're checking (useful for debugging hangs)
    [ $DEBUG -eq 1 ] && echo "   DEBUG: Checking /home for user: $username"
    
    # OPTIMIZATION: Stop as soon as we find ANY file in the date range
    # Use -print -quit to stop immediately after finding first match
    # Run as installer user (has read access) rather than impersonating with sudo
    # Timeout after 10 seconds to prevent hanging on problematic directories
    found_file=$(timeout 10 find -L "$homedir" -type f -newermt "$START_DATE" ! -newermt "$END_DATE 23:59:59" \
                  -print -quit 2>/dev/null)
    find_exit=$?
    
    # If we got a file path, user is active (even if exit code is 1 from -quit)
    if [ ! -z "$found_file" ]; then
        # User is active - we found at least one file
        # Use END_DATE as timestamp since we don't know exact time
        timestamp=$(date -d "$END_DATE" +%s)
        active_users[$username]="home"
        update_last_activity "$username" "$timestamp"
    elif [ $find_exit -eq 124 ]; then
        # Timeout - directory too large or hung filesystem
        [ $DEBUG -eq 1 ] && echo "   DEBUG: User $username timed out (directory too large or NFS issue)"
        ((password_required++))
        password_required_users+=("$username (timeout)")
    elif [ $find_exit -ne 0 ] && [ $find_exit -ne 1 ]; then
        # Other error (not timeout, not normal -quit exit)
        ((password_required++))
        password_required_users+=("$username")
        [ $DEBUG -eq 1 ] && echo "   DEBUG: User $username failed with exit code $find_exit"
    fi
    # If no file and exit 0 or 1 = user just not active in this period (normal)
done
echo "   Checked: $checked, Skipped: $skipped already active, Errors/Timeouts: $password_required, Total active: ${#active_users[@]}"
if [ ${#password_required_users[@]} -gt 0 ]; then
    echo "   First 10 users with errors/timeouts (run with DEBUG=1 for details):"
    printf '   %s\n' "${password_required_users[@]}" | head -10
fi

# Method 3: /scratch directories
echo "3. Checking /scratch directories..."
checked=0
skipped=0
password_required=0
scratch_password_required_users=()
for scratchdir in /scratch/*; do
    [ ! -d "$scratchdir" ] && continue
    username=$(basename "$scratchdir")
    ((checked++))
    [ $((checked % 50)) -eq 0 ] && echo "   ...checked $checked, skipped $skipped already active, $password_required errors"
    is_valid_user "$username" || continue
    
    # Skip if user already found active (optimization)
    if [ ! -z "${active_users[$username]}" ]; then
        ((skipped++))
        continue
    fi
    
    # Show which user we're checking (useful for debugging hangs)
    [ $DEBUG -eq 1 ] && echo "   DEBUG: Checking /scratch for user: $username"
    
    # OPTIMIZATION: Stop as soon as we find ANY file in the date range
    # Use -print -quit to stop immediately after finding first match
    # Run as installer user (has read access) rather than impersonating with sudo
    # Timeout after 10 seconds to prevent hanging on problematic directories
    found_file=$(timeout 10 find -L "$scratchdir" -type f -newermt "$START_DATE" ! -newermt "$END_DATE 23:59:59" \
                  -print -quit 2>/dev/null)
    find_exit=$?
    
    # If we got a file path, user is active (even if exit code is 1 from -quit)
    if [ ! -z "$found_file" ]; then
        # User is active - we found at least one file
        # Use END_DATE as timestamp since we don't know exact time
        timestamp=$(date -d "$END_DATE" +%s)
        active_users[$username]="scratch"
        update_last_activity "$username" "$timestamp"
    elif [ $find_exit -eq 124 ]; then
        # Timeout - directory too large or hung filesystem
        [ $DEBUG -eq 1 ] && echo "   DEBUG: User $username timed out (directory too large or NFS issue)"
        ((password_required++))
        scratch_password_required_users+=("$username (timeout)")
    elif [ $find_exit -ne 0 ] && [ $find_exit -ne 1 ]; then
        # Other error (not timeout, not normal -quit exit)
        ((password_required++))
        scratch_password_required_users+=("$username")
        [ $DEBUG -eq 1 ] && echo "   DEBUG: User $username failed with exit code $find_exit"
    fi
    # If no file and exit 0 or 1 = user just not active in this period (normal)
done
echo "   Checked: $checked, Skipped: $skipped already active, Errors/Timeouts: $password_required"
if [ ${#scratch_password_required_users[@]} -gt 0 ]; then
    echo "   First 10 users with errors/timeouts (run with DEBUG=1 for details):"
    printf '   %s\n' "${scratch_password_required_users[@]}" | head -10
fi

echo ""
echo "===================================================================="
echo "Total Active Users: ${#active_users[@]}"
echo ""

# Save password-required users to file for review
if [ ${#password_required_users[@]} -gt 0 ] || [ ${#scratch_password_required_users[@]} -gt 0 ]; then
    > /tmp/spydur_password_required_users.txt
    printf '%s\n' "${password_required_users[@]}" "${scratch_password_required_users[@]}" | sort -u > /tmp/spydur_password_required_users.txt
    unique_count=$(wc -l < /tmp/spydur_password_required_users.txt)
    echo "Users with errors/timeouts: $unique_count (saved to /tmp/spydur_password_required_users.txt)"
    echo "Run with DEBUG=1 to see error details"
    echo ""
fi

# Create sorted list with timestamps
> /tmp/spydur_active_users_detailed.txt
for user in "${!active_users[@]}"; do
    last_activity="${user_last_activity[$user]}"
    last_activity_date=$(date -d "@$last_activity" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "unknown")
    echo "$last_activity|$user|$last_activity_date|${active_users[$user]}"
done | sort -n > /tmp/spydur_active_users_detailed.txt

# Extract just usernames sorted by activity
cut -d'|' -f2 /tmp/spydur_active_users_detailed.txt > /tmp/spydur_active_users.txt

echo "FIRST 5 USERS TO BECOME ACTIVE (earliest activity):"
echo "---------------------------------------------------"
head -5 /tmp/spydur_active_users_detailed.txt | while IFS='|' read ts user date methods; do
    printf "%-20s %s (via: %s)\n" "$user" "$date" "$methods"
done

echo ""
echo "LAST 5 USERS TO BECOME ACTIVE (most recent activity):"
echo "------------------------------------------------------"
tail -5 /tmp/spydur_active_users_detailed.txt | while IFS='|' read ts user date methods; do
    printf "%-20s %s (via: %s)\n" "$user" "$date" "$methods"
done

echo ""
echo "Full list saved to:"
echo "  /tmp/spydur_active_users.txt (usernames only)"
echo "  /tmp/spydur_active_users_detailed.txt (with timestamps and methods)"
