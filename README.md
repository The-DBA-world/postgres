# PostgreSQL Replication Status Checker

## Overview

`check_postgres_replication.sh` is a Bash script designed to monitor and display the replication status of a PostgreSQL cluster. It provides **detailed information** about the primary (master) and standby (slave) nodes, including cluster configuration, replication lag, WAL (Write-Ahead Log) status, and recovery state. The script is intended for database administrators to quickly assess the health and synchronization of PostgreSQL replication setups.

This script supports both primary and standby nodes, dynamically detecting the role of the node it runs on and tailoring the output accordingly. It includes a formatted **"Cluster Information"** table and detailed status sections specific to the node’s role.

## Features

- **Dynamic Role Detection**: Identifies whether the script is running on a primary (`master`) or standby (`slave`) node using `pg_is_in_recovery()`.
- **Cluster Information Table**: Displays a table with details about all nodes in the cluster:
  - `Database Host` (e.g., `192.168.1.101:5432`)
  - `IP Address`
  - `Hostname` (resolved via DNS or static mapping)
  - `Sync Status` (e.g., `async`, `N/A`)
  - `Role Name` (e.g., `Primary (Master)`, `Standby (Slave)`)
  - `Application Name` (e.g., `walreceiver`, `N/A`)
- **Primary Node Output**:
  - Current WAL file
  - List of connected slaves with detailed replication metrics (sent lag, write lag, flush lag, replay lag)
- **Standby Node Output**:
  - Current WAL LSN (Log Sequence Number)
  - Replication lag (in seconds and bytes)
  - Last replay time
  - Received WAL LSN
  - Next archive to apply
  - Recovery status
- **Hostname Resolution**: Resolves IP addresses to hostnames using the `host` command (DNS) with a fallback to a static mapping.
- **Color-Coded Output**: Uses ANSI colors for better readability (green for status headers, red for errors in the script output).
- **Flexible Configuration**: Supports command-line arguments and environment variables for database connection settings.

## Prerequisites

- **PostgreSQL**: A running PostgreSQL instance (version 9.6 or later recommended for full compatibility with replication functions).
- **Bash**: A Unix-like environment with Bash installed.
- **psql**: The PostgreSQL command-line client must be installed and in the PATH.
- **Network Access**: The script must be able to connect to the PostgreSQL instance (local or remote) using the specified host and port.
- **Optional DNS**: For hostname resolution, a working DNS setup is preferred (requires the `host` command). If DNS is unavailable, the script uses a static IP-to-hostname mapping.

## Installation

1. **Copy the Script**: Extract the script from the code block below and save it as `check_postgres_replication.sh`.
2. **Make it Executable**:
   ```bash
   chmod +x check_postgres_replication.sh


## Usage

Run the script on either the primary or standby node. By default, it detects the local IP and connects to the PostgreSQL instance running on that node.

### Basic Execution
- On the primary node (`myhost1`):
  ```bash
  ./check_postgres_replication.sh

### Script Output:
- On the primary node (`myhost1`):
  ![image](https://github.com/user-attachments/assets/0e3f39db-0d69-4bdc-b0ad-7afeb7b28549)

- On the standby node (`myhost2`):
  ![image](https://github.com/user-attachments/assets/e285acef-29a7-4d51-865d-88d0baa9a050)

  
