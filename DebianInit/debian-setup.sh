#!/bin/bash
# Prevent script from executing if only partially downloaded
set -e

# Welcome message and confirmation prompt
cat << "EOF"
╔════════════════════════════════════════════╗
║     Debian Server Security Setup Script    ║
║            By Your Joshua Blais            ║
╚════════════════════════════════════════════╝
This script will configure your Debian server with security best practices:
- Create a new administrative user with SSH key access
- Configure SSH with custom port and security settings
- Set up UFW firewall and fail2ban
- Install essential packages and enable automatic updates
EOF

read -p "Would you like to continue? (y/N) " confirm
if [[ $confirm != [yY] ]]; then
   echo "Setup cancelled."
   exit 1
fi

# Root check with clear message
if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run as root. Try: sudo curl ... | sudo bash"
   exit 1
fi

# Function to handle errors
handle_error() {
    echo "Error occurred in script at line: ${1}"
    echo "Line exited with status: ${2}"
}
trap 'handle_error ${LINENO} $?' ERR

# Installation feedback
echo "Installing essential packages..."
apt update && apt upgrade -y
apt install -y ufw fail2ban neovim curl wget git unzip certbot tmux \
    apt-transport-https ca-certificates gnupg lsb-release

echo "Setting up Docker repository..."
# Remove any old Docker installations that might conflict
apt remove -y docker docker-engine docker.io containerd runc || true

# Add Docker's official GPG key
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Add the Docker repository
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine and Docker Compose
echo "Installing Docker..."
apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Start and enable Docker
echo "Configuring Docker..."
systemctl enable docker
systemctl start docker

# Test Docker installation
echo "Testing Docker installation..."
docker --version
docker compose version

echo "Configuring firewall..."
ufw deny incoming
ufw default allow outgoing
ufw allow 80/tcp
ufw allow 443/tcp

# SSH port configuration with validation
while true; do
    read -p "Enter desired SSH port number (between 1024-65535): " ssh_port
    if [[ "$ssh_port" =~ ^[0-9]+$ ]] && [ "$ssh_port" -ge 1024 ] && [ "$ssh_port" -le 65535 ]; then
        break
    fi
    echo "Invalid port number. Please try again."
done

echo "Adding firewall rules..."
ufw allow $ssh_port/tcp
ufw --force enable

echo "Configuring SSH..."
sed -i "s/^#Port 22/Port $ssh_port/" /etc/ssh/sshd_config
sed -i 's/^PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config

# User creation with input validation
while true; do
    read -p "Enter new username (lowercase letters and numbers only): " username
    if [[ "$username" =~ ^[a-z][a-z0-9]*$ ]]; then
        break
    fi
    echo "Invalid username. Please use lowercase letters and numbers only."
done

echo "Creating new user..."
adduser $username
usermod -aG sudo $username
usermod -aG docker $username  # Add user to docker group

echo "Setting up SSH key..."
mkdir -p /home/$username/.ssh
touch /home/$username/.ssh/authorized_keys
chown -R $username:$username /home/$username/.ssh
chmod 700 /home/$username/.ssh
chmod 600 /home/$username/.ssh/authorized_keys

echo "Please paste your SSH public key (Ctrl+D when done):"
cat > /home/$username/.ssh/authorized_keys
chown $username:$username /home/$username/.ssh/authorized_keys

echo "Configuring fail2ban..."
cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
sed -i 's/bantime  = 10m/bantime  = 1h/' /etc/fail2ban/jail.local
sed -i 's/findtime  = 10m/findtime  = 30m/' /etc/fail2ban/jail.local
sed -i 's/maxretry = 5/maxretry = 3/' /etc/fail2ban/jail.local

echo "Enabling security services..."
systemctl enable fail2ban
systemctl start fail2ban

echo "Setting up automatic updates..."
apt install -y unattended-upgrades
dpkg-reconfigure -plow unattended-upgrades

echo "Restarting SSH service..."
systemctl restart ssh

# Final instructions with clear formatting
cat << EOF
✅ Setup Complete! Important Details:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SSH Port: $ssh_port
Username: $username
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚠️  IMPORTANT: Test SSH access with your new user before closing this session!
   Command: ssh -p $ssh_port $username@<your-server-ip>

Docker has been installed and configured. The new user ($username) has been added to the docker group.
You'll need to log out and back in for the docker group membership to take effect.
EOF
