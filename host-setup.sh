#!/bin/bash

# --- Configuration Variables for Initial Setup ---
# These are internal to this setup script, don't change them unless you change paths on server
REMOTE_REPO_PATH="/home/shelaria/box" # Make sure this matches REMOTE_REPO_PATH in your deploy.sh

# --- Error Handling ---
set -e
log_info() { echo -e "\n\033[1;34m=== $1 ===\033[0m"; }         # Blue bold
log_error() { echo -e "\n\033[1;31m!!! ERROR: $1 !!!\033[0m"; } # Red bold

log_info "Starting initial setup..."

# remove prev packages
log_info "Uninstalling conflicting packages"
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
    sudo apt-get remove $pkg 2>/dev/null || true
done

# 1. Update system and install basic prerequisites
log_info "Updating system packages and installing curl, gnupg..."
sudo apt update
sudo apt install -y ca-certificates curl gnupg lsb-release

# 2. Install Docker Engine, containerd, and Docker Compose plugin
log_info "Installing Docker Engine and Docker Compose plugin..."

# Add Docker's official GPG key:
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" |
    sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
sudo apt-get update

sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

log_info "Verifying Docker installation..."
sudo docker run hello-world || log_error "Docker 'hello-world' test failed. Check Docker installation."

# Add after Docker installation
log_info "Adding current user to docker group..."
sudo usermod -aG docker $USER
log_info "Note: You may need to log out and back in for docker group changes to take effect"

# 3. Docker Swarm Initialization
log_info "Checking Docker Swarm status and initializing if necessary..."
PRIVATE_IP=$(hostname -I | awk '{print $1}')

if [ "$(sudo docker info --format '{{.Swarm.LocalNodeState}}')" = "active" ]; then
    log_info "This node is already part of a Docker Swarm. Skipping swarm initialization."
else
    # Try to determine a usable IP address (non-loopback)

    if [[ -z "$PRIVATE_IP" || "$PRIVATE_IP" == "127."* ]]; then
        log_error "Could not determine a valid advertise IP. Please set it manually."
        exit 1
    fi

    log_info "Initializing Docker Swarm with --advertise-addr $PRIVATE_IP..."
    if sudo docker swarm init --advertise-addr "$PRIVATE_IP"; then
        log_info "Docker Swarm initialized successfully."
    else
        log_error "Docker Swarm initialization failed."
        exit 1
    fi
fi

echo "Docker setup complete."

# 3. Configure Firewall (UFW)
log_info "Configuring UFW firewall..."
sudo apt install -y ufw # Ensure ufw is installed

sudo ufw allow OpenSSH # Keep SSH access
# sudo ufw allow 2222/tcp        # For SFTP via proFTP

sudo ufw allow 2377/tcp # Docker Swarm management port (for other managers)
sudo ufw allow 7946/tcp # for overlay network node discovery
sudo ufw allow 7946/udp # for overlay network node discovery
sudo ufw allow 4789/udp # (configurable) for overlay network traffic  (VXLAN)

log_info "Enabling UFW firewall. Confirm with 'y' if prompted."
sudo ufw enable || log_error "Failed to enable UFW."
sudo ufw status verbose || log_error "Failed to show UFW status."

# 4. Create Application's Project Directory
log_info "Creating application project directory: $REMOTE_REPO_PATH"
sudo mkdir -p "$REMOTE_REPO_PATH"
# No need for chown if the commands are run as root; root will own directories it creates.

log_info final manual step: create docker secrets
log_info 'use ssh-agent for only 1 x prompt "eval "$(ssh-agent -s)"'
log_info "ssh-add ~/.ssh/key"
log_info "ssh -i ~/.ssh/key user@$PRIVATE_IP"
log_info "./deploy.sh"

log_info "Initial setup completed!"
