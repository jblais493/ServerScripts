#!/bin/bash
set -e

cat << "EOF"
╔════════════════════════════════════════════╗
║        PostgreSQL Server Setup Script      ║
║            By Joshua Blais                 ║
╚════════════════════════════════════════════╝
This script will:
- Install PostgreSQL 17
- Configure for performance
- Set up WAL-G for backups
- Install pgBouncer
- Configure monitoring
EOF

# Remove the read prompt and directly continue
# Since we want non-interactive

if [[ $EUID -ne 0 ]]; then
  echo "Error: This script must be run as root"
  exit 1
fi

# Add PostgreSQL repository
echo "Adding PostgreSQL 17 repository..."
sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg

# Install PostgreSQL and related packages
echo "Installing PostgreSQL 17..."
apt update
apt install -y postgresql-17 postgresql-client-17 pgbouncer postgresql-contrib

# Stop PostgreSQL to modify configuration
systemctl stop postgresql

# Configure PostgreSQL
echo "Configuring PostgreSQL..."
PG_CONF="/etc/postgresql/17/main/postgresql.conf"
PG_HBA="/etc/postgresql/17/main/pg_hba.conf"

# Calculate memory settings based on total RAM
TOTAL_MEM=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
SHARED_BUFFERS=$(($TOTAL_MEM * 25 / 100000))  # 25% of RAM
EFFECTIVE_CACHE=$(($TOTAL_MEM * 75 / 100000))  # 75% of RAM

# Backup original configs
cp $PG_CONF "${PG_CONF}.bak"
cp $PG_HBA "${PG_HBA}.bak"

# Update postgresql.conf
cat >> $PG_CONF << EOF
# Memory Configuration
shared_buffers = ${SHARED_BUFFERS}MB
effective_cache_size = ${EFFECTIVE_CACHE}MB
maintenance_work_mem = 2GB
work_mem = 32MB

# Connection Settings
max_connections = 1000
listen_addresses = '*'

# WAL Configuration
wal_level = replica
archive_mode = on
archive_command = 'test ! -f /var/lib/postgresql/17/main/archive/%f && cp %p /var/lib/postgresql/17/main/archive/%f'

# Query Tuning
random_page_cost = 1.1
effective_io_concurrency = 200

# Logging
log_destination = 'csvlog'
logging_collector = on
log_directory = 'log'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_statement = 'mod'
log_min_duration_statement = 1000

# Autovacuum
autovacuum = on
autovacuum_max_workers = 4
autovacuum_naptime = 1min
EOF

# Update pg_hba.conf for security
cat > $PG_HBA << EOF
# TYPE  DATABASE        USER            ADDRESS                 METHOD
local   all            postgres                                peer
local   all            all                                     peer
host    all            all             127.0.0.1/32           scram-sha-256
host    all            all             ::1/128                 scram-sha-256
EOF

# Create archive directory
mkdir -p /var/lib/postgresql/17/main/archive
chown postgres:postgres /var/lib/postgresql/17/main/archive

# Configure pgBouncer
echo "Configuring pgBouncer..."
cat > /etc/pgbouncer/pgbouncer.ini << EOF
[databases]
* = host=127.0.0.1 port=5432

[pgbouncer]
listen_port = 6432
listen_addr = *
auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt
pool_mode = transaction
max_client_conn = 1000
default_pool_size = 20
EOF

# Start services
echo "Starting services..."
systemctl start postgresql
systemctl enable postgresql
systemctl start pgbouncer
systemctl enable pgbouncer

# Set up monitoring user and extensions
echo "Setting up monitoring..."
su - postgres -c "psql -c \"CREATE USER monitoring WITH PASSWORD 'monitor123' SUPERUSER;\""
su - postgres -c "psql -c \"CREATE EXTENSION pg_stat_statements;\""

# Final instructions
cat << EOF
✅ PostgreSQL Setup Complete!

Important Details:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PostgreSQL port: 5432
pgBouncer port: 6432
Monitoring user created: monitoring
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Next steps:
1. Update the monitoring user password
2. Add your application users and databases
3. Configure backup strategy with WAL-G
4. Set up Prometheus/Grafana monitoring

Logs are in: /var/log/postgresql/
Configuration: /etc/postgresql/17/main/postgresql.conf
EOF
