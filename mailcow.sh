#!/bin/bash

# Prevent script from running without root privileges
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run with sudo privileges"
    exit 1
fi

# Function to handle errors and provide meaningful feedback
check_step() {
    if [ $? -ne 0 ]; then
        echo "Error: $1 failed"
        exit 1
    fi
}

# Install required packages for Mailcow
echo "Installing essential dependencies..."
apt install -y \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release
check_step "Installing dependencies"

# Set up Docker repository
echo "Configuring Docker repository..."
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
check_step "Adding Docker GPG key"

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
check_step "Adding Docker repository"

# Update system and install Docker if needed
echo "Updating system packages..."
apt update && apt upgrade -y
check_step "Updating system"

# Configure firewall rules for mail services
echo "Configuring firewall rules for mail services..."
ufw default deny incoming
ufw default allow outgoing
ufw allow 25/tcp   # SMTP
ufw allow 465/tcp  # SMTPS
ufw allow 587/tcp  # Submission
ufw allow 143/tcp  # IMAP
ufw allow 993/tcp  # IMAPS
ufw allow 110/tcp  # POP3
ufw allow 995/tcp  # POP3S
ufw allow 80/tcp   # HTTP for Let's Encrypt
ufw allow 443/tcp  # HTTPS for web interface
check_step "Configuring firewall"

# Install Mailcow
echo "Preparing Mailcow installation..."
cd /opt || exit 1

# Handle existing installation
if [ -d "mailcow-dockerized" ]; then
    echo "Found existing Mailcow installation."
    read -p "Would you like to remove it and start fresh? (y/N): " remove_existing
    
    if [[ $remove_existing =~ ^[Yy]$ ]]; then
        echo "Creating backup before removal..."
        backup_date=$(date +%Y%m%d_%H%M%S)
        backup_dir="/opt/mailcow_backup_${backup_date}"
        cp -r mailcow-dockerized "${backup_dir}"
        
        echo "Stopping existing containers..."
        cd mailcow-dockerized && docker compose down -v
        cd ..
        rm -rf mailcow-dockerized
        echo "Previous installation removed."
    else
        echo "Installation cancelled. Please remove existing installation manually if needed."
        exit 1
    fi
fi

# Clone fresh copy of Mailcow
git clone https://github.com/mailcow/mailcow-dockerized
check_step "Cloning Mailcow repository"
cd mailcow-dockerized || exit 1

# Get domain information
read -p "Enter your mail server hostname (e.g., mail.example.com): " MAILCOW_HOSTNAME
while [[ -z "$MAILCOW_HOSTNAME" ]]; do
    read -p "Hostname cannot be empty. Please enter your mail server hostname: " MAILCOW_HOSTNAME
done

# Generate secure passwords
echo "Generating secure passwords..."
DB_ROOT_PASSWORD=$(openssl rand -hex 16)
DB_USER_PASSWORD=$(openssl rand -hex 16)
REDIS_PASSWORD=$(openssl rand -hex 16)

# Generate Mailcow configuration
echo "Creating Mailcow configuration..."
cat << EOF > mailcow.conf
# Basic Mailcow settings
MAILCOW_HOSTNAME=${MAILCOW_HOSTNAME}
SKIP_LETS_ENCRYPT=n
SKIP_CLAMD=n
SKIP_SOLR=y
SOLR_HEAP=1024
ENABLE_SSL_SNI=n
SKIP_IP_CHECK=n
ADDITIONAL_SAN=

# Time zone configuration
TZ=UTC
MAILCOW_TZ=UTC

# Database configuration
DBNAME=mailcow
DBUSER=mailcow
DBPASS=${DB_USER_PASSWORD}
DBROOT=${DB_ROOT_PASSWORD}

# Redis configuration
REDISPASS=${REDIS_PASSWORD}

# Additional security settings
SKIP_INET_CHECK=n
SKIP_KNOWN_IP_CHECK=n
SKIP_SOGO=n
SKIP_SYSLOG=n
EOF
check_step "Creating configuration file"

# Save credentials securely
echo "Saving credentials..."
mkdir -p data/conf
cat << EOF > data/conf/installation_info.txt
Installation Date: $(date)
Hostname: ${MAILCOW_HOSTNAME}
Database Name: mailcow
Database User: mailcow
Database Root Password: ${DB_ROOT_PASSWORD}
Database User Password: ${DB_USER_PASSWORD}
Redis Password: ${REDIS_PASSWORD}

IMPORTANT: Keep this information secure!
EOF
chmod 600 data/conf/installation_info.txt

# Start Mailcow services
echo "Starting Mailcow services..."
docker compose pull
check_step "Pulling Docker images"

echo "Starting containers..."
docker compose up -d
check_step "Starting Mailcow containers"

# Wait for services to initialize
echo "Waiting for services to initialize (this may take a few minutes)..."
sleep 30

# Check container health
echo "Verifying container status..."
if ! docker compose ps | grep -q "Exit\|Restarting"; then
    echo "All containers are running properly."
else
    echo "Warning: Some containers may need attention. Check logs with 'docker compose logs'"
fi

# Print completion message
cat << EOF

Mailcow installation complete!
Important next steps:
1. Access the Mailcow UI at https://${MAILCOW_HOSTNAME}
2. Default login credentials:
   Username: admin
   Password: moohoo
   CHANGE THIS PASSWORD IMMEDIATELY!

3. Configure these DNS records for ${MAILCOW_HOSTNAME}:
   - A record pointing to your server's IP
   - MX record pointing to ${MAILCOW_HOSTNAME}
   - SPF, DKIM, and DMARC records (shown in Mailcow UI)

4. Review and configure:
   - Spam filter settings
   - Backup settings
   - SSL certificate settings
   - Mail retention policies

Credentials have been saved to: /opt/mailcow-dockerized/data/conf/installation_info.txt

The full Mailcow documentation is available at:
https://mailcow.github.io/mailcow-dockerized-docs/
EOF

# Offer to show container status
read -p "Would you like to check the status of Mailcow containers? (y/n) " response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])+$ ]]; then
    docker compose ps
fi
