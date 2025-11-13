#!/bin/bash
# active_users.sh - Find active users with date range support
# Usage: ./active_users.sh [START_DATE] [END_DATE]
# Example: ./active_users.sh 2024-09-01 2024-11-01

# Default to last 3 months if no dates provided
START_DATE="${1:-$(date -d '3 months ago' +%Y-%m-%d)}"
END_DATE="${2:-$(date +%Y-%m-%d)}"

# Calculate days ago from today
START_DAYS_AGO=$(( ($(date +%s) - $(date -d "$START_DATE" +%s)) / 86400 ))
END_DAYS_AGO=$(( ($(date +%s) - $(date -d "$END_DATE" +%s)) / 86400 ))

echo "spydur: Finding active users between $START_DATE and $END_DATE"
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
        return 0
    fi
    # If can't verify, include if username looks valid (starts with letter)
    [[ "$username" =~ ^[a-z] ]] && return 0
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
for homedir in /home/*; do
    [ ! -d "$homedir" ] && continue
    username=$(basename "$homedir")
    ((checked++))
    [ $((checked % 100)) -eq 0 ] && echo "   ...checked $checked"
    is_valid_user "$username" || continue
    
    # Find most recent file in date range (follow symlinks with -L)
    recent_file=$(find -L "$homedir" -type f -newermt "$START_DATE" ! -newermt "$END_DATE 23:59:59" \
                  -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1)
    
    if [ ! -z "$recent_file" ]; then
        timestamp=$(echo "$recent_file" | cut -d' ' -f1 | cut -d'.' -f1)
        active_users[$username]="${active_users[$username]:+${active_users[$username]},}home"
        update_last_activity "$username" "$timestamp"
    fi
done
echo "   Total: ${#active_users[@]} users with home activity"

# Method 3: /scratch directories
echo "3. Checking /scratch directories..."
checked=0
for scratchdir in /scratch/*; do
    [ ! -d "$scratchdir" ] && continue
    username=$(basename "$scratchdir")
    ((checked++))
    [ $((checked % 100)) -eq 0 ] && echo "   ...checked $checked"
    is_valid_user "$username" || continue
    
    # Find most recent file in date range (follow symlinks with -L)
    recent_file=$(find -L "$scratchdir" -type f -newermt "$START_DATE" ! -newermt "$END_DATE 23:59:59" \
                  -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1)
    
    if [ ! -z "$recent_file" ]; then
        timestamp=$(echo "$recent_file" | cut -d' ' -f1 | cut -d'.' -f1)
        active_users[$username]="${active_users[$username]:+${active_users[$username]},}scratch"
        update_last_activity "$username" "$timestamp"
    fi
done

echo ""
echo "===================================================================="
echo "Total Active Users: ${#active_users[@]}"
echo ""

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
