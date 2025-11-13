# Active Users Tracker

Scripts to identify and track active users on HPC clusters by analyzing SSH logs, home directories, and scratch space file activity.

## What is an "Active User"?

An **active user** is defined as any user account that shows evidence of activity during the specified time period through one or more of the following:

1. **SSH Login Activity**: Successful SSH authentication recorded in system logs
2. **File Modifications**: Files created or modified in the user's home directory
3. **Scratch Space Usage**: Files created or modified in the user's scratch directory

A user is considered active if they meet ANY of these criteria during the date range specified. The system automatically excludes:
- System accounts (UID < 1000)
- Test/temporary accounts (prefixes like test_, tmp_, dataset_)
- Invalid or non-existent usernames

## Features

- **Date Range Support**: Find users active during specific time periods
- **Multiple Detection Methods**: Checks SSH logs, /home, and /scratch directories
- **Activity Timestamps**: Tracks the most recent activity for each user
- **First/Last Analysis**: Shows the earliest and most recent users to be active
- **LDAP Compatible**: Works with both local and LDAP users
- **Smart Filtering**: Excludes system accounts, test accounts, and invalid usernames

## Scripts

### 1. spydur_spydur_spydur_active_users.sh (For Spydur Cluster)

Comprehensive script designed for the Spydur HPC cluster with full infrastructure (SSH logs, /home, /scratch).

**Usage:**
```bash
./spydur_spydur_spydur_active_users.sh [START_DATE] [END_DATE]
```

**Examples:**
```bash
# Find users active in the last 3 months (default)
./spydur_spydur_spydur_active_users.sh

# Find users active between specific dates
./spydur_spydur_spydur_active_users.sh 2024-09-01 2024-11-01

# Find users active since September 2024 until now
./spydur_spydur_spydur_active_users.sh 2024-09-01

# Find users active in October 2024
./spydur_spydur_spydur_active_users.sh 2024-10-01 2024-10-31
```

**Detection Methods:**
1. **SSH Logs**: Scans `/var/log/secure*` for successful logins
2. **Home Directories**: Checks `/home/*` for recently modified files
3. **Scratch Space**: Checks `/scratch/*` for recently modified files

**Output:**
```
spydur: Finding active users between 2024-09-01 and 2024-11-13
====================================================================
1. Checking SSH logs...
   Found 45 valid users via SSH
2. Checking /home directories...
   Total: 52 users with home activity
3. Checking /scratch directories...

====================================================================
Total Active Users: 58

FIRST 5 USERS TO BECOME ACTIVE (earliest activity):
---------------------------------------------------
alice                2024-09-02 08:15:23 (via: ssh,home)
bob                  2024-09-03 14:22:11 (via: home,scratch)
...

LAST 5 USERS TO BECOME ACTIVE (most recent activity):
------------------------------------------------------
zelda                2024-11-12 16:45:33 (via: ssh,home,scratch)
...

Full list saved to:
  /tmp/spydur_active_users.txt (usernames only)
  /tmp/spydur_active_users_detailed.txt (with timestamps and methods)
```

### 2. spiderweb_spydur_spydur_active_users.sh (For Spiderweb Server)

Streamlined script designed for the Spiderweb server (workstation environment without cluster infrastructure).

**Usage:**
```bash
./spiderweb_spydur_spydur_active_users.sh [START_DATE] [END_DATE]
```

**Examples:**
```bash
# Quick count for last 3 months
./spiderweb_spydur_spydur_active_users.sh

# Quick count for specific date range
./spiderweb_spydur_spydur_active_users.sh 2024-09-01 2024-10-31
```

**Detection Methods:**
1. **Home Directories**: Checks `/home/*` for recently modified files (uses getent passwd for user enumeration)

**Output:**
```
Checking file activity between 2024-09-01 and 2024-11-13
==============================================================

Total active users: 48

FIRST 5 USERS (earliest activity):
-----------------------------------
alice                2024-09-02 08:15:23
bob                  2024-09-03 14:22:11
...

LAST 5 USERS (most recent activity):
-------------------------------------
zelda                2024-11-12 16:45:33
...

Lists saved to:
  /tmp/active_users.txt (usernames only)
  /tmp/active_users_detailed.txt (with timestamps)
```

## Installation

```bash
git clone <repository-url>
cd active-users-tracker
chmod +x spydur_spydur_active_users.sh spiderweb_spydur_active_users.sh
```

## Requirements

- Bash 4.0+ (for associative arrays)
- Standard Unix utilities: `find`, `awk`, `sort`, `date`, `grep`
- Read access to `/var/log/secure` (for SSH log analysis)
- Access to `/home` and `/scratch` directories

## Output Files

Both scripts generate output files in `/tmp`:

- **Simple list**: `/tmp/spydur_active_users.txt` or `/tmp/active_users.txt`
  - One username per line, sorted by last activity
  
- **Detailed list**: `/tmp/spydur_active_users_detailed.txt` or `/tmp/active_users_detailed.txt`
  - Format: `timestamp|username|date_string|detection_methods`
  - Sorted by activity timestamp (oldest to newest)

## User Filtering

The scripts automatically exclude:
- System accounts (UID < 1000)
- All-numeric usernames
- Test/temporary accounts (prefixes: `dataset_`, `test_`, `tmp_`, `backup_`)
- System users: `root`, `bin`, `daemon`, `sync`, `halt`
- `lost+found` directory

## Use Cases

### Monthly Active User Reports
```bash
# Generate report for last month
LAST_MONTH_START=$(date -d 'last month' +%Y-%m-01)
LAST_MONTH_END=$(date -d "$LAST_MONTH_START + 1 month - 1 day" +%Y-%m-%d)
./spydur_spydur_active_users.sh "$LAST_MONTH_START" "$LAST_MONTH_END" > monthly_report.txt
```

### Identify Inactive Users
```bash
# Find users who haven't been active in the last 6 months
# First get all active users in last 6 months
./spiderweb_spydur_active_users.sh "$(date -d '6 months ago' +%Y-%m-%d)"

# Compare against all users
comm -23 <(getent passwd | awk -F: '$3>=1000{print $1}' | sort) \
         <(sort /tmp/active_users.txt) > inactive_users.txt
```

### Track New User Onboarding
```bash
# See who became active this quarter
QUARTER_START=$(date -d '3 months ago' +%Y-%m-01)
./spydur_spydur_active_users.sh "$QUARTER_START" | head -n 30
```

## Performance Notes

- **spydur_spydur_active_users.sh**: Thorough but slower (~2-5 minutes for 100+ users)
  - Use for monthly reports or detailed analysis
  
- **spiderweb_spydur_active_users.sh**: Fast (~30-60 seconds)
  - Use for quick checks and regular monitoring

- The scripts use `timeout` to prevent hanging on unresponsive filesystems
- Progress indicators show every 100 directories checked

## Troubleshooting

### Permission Denied on /var/log/secure
```bash
# Run with sudo if needed for SSH log analysis
sudo ./spydur_spydur_active_users.sh
```

### No activity detected despite active users
- Check that date format is YYYY-MM-DD
- Verify filesystem timestamps are correct
- Check if NFS/network filesystems are mounted

### Script runs too slowly
- Use `spiderweb_spydur_active_users.sh` for faster results
- Reduce date range to check fewer days
- Check for hung/unmounted directories

## Technical Details

### Date Range Implementation
- Uses `find -newermt` for efficient date-based file searching
- Converts dates to Unix timestamps for comparison
- Handles timezone-aware date calculations

### Activity Tracking
- Maintains associative arrays for O(1) user lookups
- Tracks most recent activity timestamp per user
- Combines activity from multiple sources

### Sorting
- Users sorted by their most recent activity timestamp
- "First" = earliest activity in the date range
- "Last" = most recent activity in the date range

## License

MIT License - Feel free to use and modify for your cluster management needs.

## Contributing

Pull requests welcome! Particularly interested in:
- Support for additional activity sources (SLURM jobs, module usage, etc.)
- Performance optimizations
- Better handling of distributed filesystems
- Integration with existing cluster monitoring tools

## Authors

Developed for HPC cluster administration at academic institutions.
