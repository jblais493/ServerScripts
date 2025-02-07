#!/bin/bash

# Check if script is run with sudo privileges
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run with sudo privileges"
    exit 1
fi

# Function to check command success
check_step() {
    if [ $? -ne 0 ]; then
        echo "Error: $1 failed"
        exit 1
    fi
}

# Install additional required packages for Mailcow
echo "Installing additional dependencies..."
apt install -y \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release
check_step "Installing dependencies"

# Update Docker repository to ensure latest version
echo "Updating Docker repository..."
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
check_step "Adding Docker GPG key"

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
check_step "Adding Docker repository"

apt update && apt upgrade -y
check_step "Updating system"

# Configure firewall for mail services
echo "Configuring firewall rules for mail services..."
ufw allow 25/tcp   # SMTP
ufw allow 465/tcp  # SMTPS
ufw allow 587/tcp  # Submission
ufw allow 143/tcp  # IMAP
ufw allow 993/tcp  # IMAPS
ufw allow 110/tcp  # POP3
ufw allow 995/tcp  # POP3S
check_step "Configuring firewall"

# Install Mailcow
echo "Installing Mailcow..."
cd /opt || exit 1
git clone https://github.com/mailcow/mailcow-dockerized
check_step "Cloning Mailcow repository"

cd mailcow-dockerized || exit 1

# Get domain information
read -p "Enter your mail server hostname (e.g., mail.example.com): " MAILCOW_HOSTNAME
while [[ -z "$MAILCOW_HOSTNAME" ]]; do
    read -p "Hostname cannot be empty. Please enter your mail server hostname: " MAILCOW_HOSTNAME
done

# Generate Mailcow configuration
echo "Generating Mailcow configuration..."
cat << EOF > mailcow.conf
MAILCOW_HOSTNAME=${MAILCOW_HOSTNAME}
SKIP_LETS_ENCRYPT=n
SKIP_CLAMD=n
SKIP_SOLR=y
SOLR_HEAP=1024
ENABLE_SSL_SNI=n
SKIP_IP_CHECK=n
ADDITIONAL_SAN=
MAILCOW_TZ=UTC
EOF
check_step "Creating configuration file"

# Pull and start Mailcow
echo "Starting Mailcow services..."
docker-compose pull
check_step "Pulling Docker images"

docker-compose up -d
check_step "Starting Mailcow containers"

# Print completion message with important information
echo "
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

The full Mailcow documentation is available at:
https://mailcow.github.io/mailcow-dockerized-docs/

Would you like to check the status of Mailcow containers? (y/n)"

read -r response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])+$ ]]; then
    docker-compose ps
fi
