#!/bin/bash

# Script: check_postgres_replication.sh
# Purpose: Check detailed PostgreSQL replication status for master and slave databases with cluster info
# Author: Anilkumar Sonawane
# Date: April 08, 2025
#
# Execution Examples:
#   On Master: ./check_postgres_replication.sh -h 192.168.1.101 -p 5432 -U postgres -d postgres
#   On Slave:  ./check_postgres_replication.sh -h 192.168.1.102 -p 5432 -U postgres -d postgres
#
# With Password (if required):
#   - Using -W: ./check_postgres_replication.sh -h 192.168.1.101 -p 5432 -U postgres -d postgres -W your_password
#   - Using PGPASSWORD: export PGPASSWORD='your_password'; ./check_postgres_replication.sh -h 192.168.1.101 -p 5432 -U postgres -d postgres
#   - Using .pgpass: echo "192.168.1.101:5432:postgres:postgres:your_password" > ~/.pgpass; chmod 600 ~/.pgpass

# Default PostgreSQL connection parameters as variables
MASTER_HOST="192.168.1.101"    # Master database host
SLAVE_HOST="192.168.1.102"     # Slave database host
DEFAULT_PORT="5432"            # Default database port
DEFAULT_USER="postgres"        # Default database user
DEFAULT_DB="postgres"          # Default database name

# Determine local IP dynamically unless overridden
LOCAL_IP=$(ip addr show | grep -o "inet 192.168.1.[0-9]\+" | awk '{print $2}' | cut -d'/' -f1 | head -n 1)
PGHOST="${PGHOST:-$LOCAL_IP}"  # Default to local IP instead of MASTER_HOST
PGPORT="${PGPORT:-$DEFAULT_PORT}"  # Database port
PGUSER="${PGUSER:-$DEFAULT_USER}"  # Database user
PGDATABASE="${PGDATABASE:-$DEFAULT_DB}"  # Database name
PGPASSWORD="${PGPASSWORD:-}"     # Database password (optional)

# ANSI color codes for output formatting
GREEN='\033[0;32m'  # Green text
RED='\033[0;31m'    # Red text
NC='\033[0m'        # No color (reset)

# Function: check_psql
# Purpose: Verify if psql client is installed and available
check_psql() {
    if ! command -v psql &> /dev/null; then
        echo -e "${RED}Error: psql is not installed or not in PATH${NC}"
        exit 1
    fi
}

# Function: test_connection
# Purpose: Test database connectivity with provided parameters
test_connection() {
    PGPASSWORD="$PGPASSWORD" psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -c "SELECT 1" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Cannot connect to database${NC}"
        echo "Host: $PGHOST, Port: $PGPORT, User: $PGUSER, Database: $PGDATABASE"
        exit 1
    fi
}

# Function: get_role
# Purpose: Get the current role of the database (master/standby)
get_role() {
    IS_IN_RECOVERY=$(PGPASSWORD="$PGPASSWORD" psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -t -A -c "SELECT pg_is_in_recovery();" 2>/dev/null | tr -d '[:space:]')
    if [ "$IS_IN_RECOVERY" = "f" ]; then
        echo "Primary (Master)"
    else
        echo "Standby (Slave)"
    fi
}

# Function: get_hostname
# Purpose: Get the full hostname for a given IP using DNS or static mapping
get_hostname() {
    local host_ip="$1"
    # Try DNS resolution with 'host' command
    if command -v host >/dev/null 2>&1; then
        hostname=$(host "$host_ip" 2>/dev/null | grep "domain name pointer" | awk '{print $NF}' | sed 's/\.$//')
        if [ -n "$hostname" ]; then
            echo "$hostname"
            return
        fi
    fi
    # Fallback to static mapping if DNS fails or 'host' is unavailable
    case "$host_ip" in
        "192.168.1.101") echo "myhost1.testmachine.com";;
        "192.168.1.102") echo "myhost2.testmachine.com";;
        *) echo "$host_ip";;
    esac
}

# Function: check_replication_status
# Purpose: Display detailed replication status for master and slaves with cluster info
check_replication_status() {
    IS_MASTER=$(PGPASSWORD="$PGPASSWORD" psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -t -A -c "SELECT pg_is_in_recovery();" 2>/dev/null | tr -d '[:space:]')
    CURRENT_ROLE=$(get_role)
    CURRENT_HOSTNAME=$(get_hostname "$PGHOST")

    # Print cluster information table
    echo "Cluster Information:"
    printf "%-25s | %-15s | %-25s | %-15s | %-20s | %-20s\n" "Database Host" "IP Address" "Hostname" "Sync Status" "Role Name" "Application Name"
    printf "%-25s | %-15s | %-25s | %-15s | %-20s | %-20s\n" "-------------------------" "---------------" "-------------------------" "---------------" "--------------------" "--------------------"

    # Always show master in cluster info
    MASTER_HOSTNAME=$(get_hostname "$MASTER_HOST")
    printf "%-25s | %-15s | %-25s | %-15s | %-20s | %-20s\n" "$MASTER_HOST:$PGPORT" "$MASTER_HOST" "$MASTER_HOSTNAME" "N/A" "Primary (Master)" "N/A"

    if [ "$IS_MASTER" = "f" ]; then
        # Master database
        CURRENT_WAL=$(PGPASSWORD="$PGPASSWORD" psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -t -A -c "SELECT pg_walfile_name(pg_current_wal_lsn());" 2>/dev/null | tr -d '[:space:]')
        
        # Add current node (master) and slaves to cluster info
        printf "%-25s | %-15s | %-25s | %-15s | %-20s | %-20s\n" "$PGHOST:$PGPORT" "$PGHOST" "$CURRENT_HOSTNAME" "N/A" "$CURRENT_ROLE" "N/A"

        REPLICATION_INFO=$(PGPASSWORD="$PGPASSWORD" psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -t -A -F"," -c "
            SELECT 
                client_addr,
                state,
                sync_state,
                application_name,
                pg_wal_lsn_diff(pg_current_wal_lsn(), sent_lsn) AS sent_lag,
                pg_wal_lsn_diff(pg_current_wal_lsn(), write_lsn) AS write_lag,
                pg_wal_lsn_diff(pg_current_wal_lsn(), flush_lsn) AS flush_lag,
                pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS replay_lag,
                pg_walfile_name(replay_lsn) AS current_wal_slave
            FROM pg_stat_replication;" 2>/dev/null)

        if [ -n "$REPLICATION_INFO" ]; then
            echo "$REPLICATION_INFO" | while IFS=',' read -r client_addr state sync_state app_name sent_lag write_lag flush_lag replay_lag current_wal_slave; do
                if [ -n "$client_addr" ]; then
                    SLAVE_HOSTNAME=$(get_hostname "$client_addr")
                    printf "%-25s | %-15s | %-25s | %-15s | %-20s | %-20s\n" "$client_addr:$PGPORT" "$client_addr" "$SLAVE_HOSTNAME" "$sync_state" "Standby (Slave)" "$app_name"
                fi
            done
        fi

        # Master status output
        echo -e "\n${GREEN}This is a MASTER database${NC}"
        echo "Host: $PGHOST:$PGPORT (Primary node in the cluster)"
        echo "Current Role: $CURRENT_ROLE"
        echo "Current WAL File: ${CURRENT_WAL:-N/A}"
        echo "Checking connected slaves..."

        if [ -z "$REPLICATION_INFO" ]; then
            echo "No slaves currently connected"
        else
            echo -e "\nDetailed Slave Replication Status:"
            printf "%-15s | %-10s | %-12s | %-17s | %-12s | %-12s | %-12s | %-12s | %-24s\n" \
                "Client Address" "State" "Sync State" "Application Name" "Sent Lag" "Write Lag" "Flush Lag" "Replay Lag" "Current WAL"
            printf "%-15s | %-10s | %-12s | %-17s | %-12s | %-12s | %-12s | %-12s | %-24s\n" \
                "---------------" "----------" "------------" "-----------------" "------------" "------------" "------------" "------------" "------------------------"
            echo "$REPLICATION_INFO" | while IFS=',' read -r client_addr state sync_state app_name sent_lag write_lag flush_lag replay_lag current_wal_slave; do
                [ -n "$client_addr" ] && printf "%-15s | %-10s | %-12s | %-17s | %-12s | %-12s | %-12s | %-12s | %-24s\n" \
                    "$client_addr" "$state" "$sync_state" "$app_name" "$sent_lag" "$write_lag" "$flush_lag" "$replay_lag" "$current_wal_slave"
            done
        fi
    else
        # Standby database
        CURRENT_WAL=$(PGPASSWORD="$PGPASSWORD" psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -t -A -c "SELECT pg_last_wal_receive_lsn();" 2>/dev/null | tr -d '[:space:]')
        if [ -n "$CURRENT_WAL" ]; then
            CURRENT_WAL="LSN: $CURRENT_WAL"
        else
            CURRENT_WAL="N/A"
        fi

        # Add current node (slave) to cluster info
        printf "%-25s | %-15s | %-25s | %-15s | %-20s | %-20s\n" "$PGHOST:$PGPORT" "$PGHOST" "$CURRENT_HOSTNAME" "N/A" "$CURRENT_ROLE" "walreceiver"

        echo -e "\n${GREEN}This is a STANDBY database${NC}"
        echo "Host: $PGHOST:$PGPORT (Replicating from $MASTER_HOST:$PGPORT)"
        echo "Current Role: $CURRENT_ROLE"
        echo "Current WAL: $CURRENT_WAL"

        SLAVE_INFO=$(PGPASSWORD="$PGPASSWORD" psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -t -A -F"," -c "
            SELECT 
                CASE WHEN pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn() 
                    THEN 0 
                    ELSE EXTRACT(EPOCH FROM now() - pg_last_xact_replay_timestamp()) 
                END AS lag_seconds,
                pg_wal_lsn_diff(pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn()) AS lag_bytes,
                pg_last_xact_replay_timestamp() AS last_replay_time,
                pg_last_wal_receive_lsn() AS received_wal,
                (SELECT min(dir) 
                 FROM pg_ls_dir('pg_wal/archive_status') AS dir 
                 WHERE dir LIKE '%ready') AS next_archive;" 2>/dev/null)

        IFS=',' read -r lag_seconds lag_bytes last_replay_time received_wal next_archive <<< "$SLAVE_INFO"

        echo -e "\nReplication Status:"
        printf "%-25s : %s\n" "Lag (seconds)" "${lag_seconds:-0}"
        printf "%-25s : %s\n" "Lag (bytes)" "${lag_bytes:-0}"
        printf "%-25s : %s\n" "Last Replay Time" "${last_replay_time:-N/A}"
        printf "%-25s : %s\n" "Received WAL LSN" "${received_wal:-N/A}"
        printf "%-25s : %s\n" "Next Archive to Apply" "${next_archive:-N/A}"

        RECOVERY_STATUS=$(PGPASSWORD="$PGPASSWORD" psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -t -A -c "SELECT pg_is_in_recovery();" 2>/dev/null | tr -d '[:space:]')
        printf "%-25s : %s\n" "Recovery Status" "$( [ "$RECOVERY_STATUS" = "t" ] && echo "In recovery" || echo "Not in recovery" )"
    fi
}

# Function: usage
# Purpose: Display script usage information
usage() {
    echo "Usage: $0 [-h host] [-p port] [-U user] [-d database] [-W password]"
    echo "Options:"
    echo "  -h    Database host (default: local IP, Master: $MASTER_HOST, Slave: $SLAVE_HOST)"
    echo "  -p    Database port (default: $DEFAULT_PORT)"
    echo "  -U    Database user (default: $DEFAULT_USER)"
    echo "  -d    Database name (default: $DEFAULT_DB)"
    echo "  -W    Database password (optional, or use PGPASSWORD env var)"
    echo "Environment variables PGHOST, PGPORT, PGUSER, PGDATABASE, PGPASSWORD can also be used"
    echo "Examples:"
    echo "  Master: $0 -h $MASTER_HOST -p $DEFAULT_PORT -U $DEFAULT_USER -d $DEFAULT_DB"
    echo "  Slave:  $0 -h $SLAVE_HOST -p $DEFAULT_PORT -U $DEFAULT_USER -d $DEFAULT_DB"
    exit 1
}

# Parse command-line arguments
while getopts "h:p:U:d:W:" opt; do
    case $opt in
        h) PGHOST="$OPTARG";;
        p) PGPORT="$OPTARG";;
        U) PGUSER="$OPTARG";;
        d) PGDATABASE="$OPTARG";;
        W) PGPASSWORD="$OPTARG";;
        ?) usage;;
    esac
done

# Main execution
echo "PostgreSQL Replication Status Checker"
echo "===================================="

check_psql
test_connection
check_replication_status

exit 0
