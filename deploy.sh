#!/bin/bash

# Docker Swarm Deployment Script
# This script creates secrets from .env files, builds images, and deploys services

set -e # Exit on any error

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/deploy.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

# remote fun
run_remote() {
    local command="$@"
    log "Executing remotely on $DROPLET_HOST: '$command'"
    # using ssh-agent now so don't need to specific the key path
    # ssh -i "$SSH_KEY_PATH" "$SSH_USER@$DROPLET_HOST" "$command"
    # ssh "$SSH_USER@$DROPLET_HOST" "$command"
    ssh debian-box "$command"
}
# --- Load Environment Variables from local .env file ---
if [ -f "deploy.env" ]; then
    log "Loading configuration from deploy.env..."
    source "deploy.env"
else
    error "deploy.env not found! Please create it with your deployment variables."
    exit 1
fi

# Main function
main() {
    # clone down/update the repo
    log "Navigating to $REMOTE_REPO_PATH and pulling latest code..."
    run_remote "cd $REMOTE_REPO_PATH && \
        if [ -d .git ]; then \
            echo 'Git repo exists, pulling...'; \
            git pull origin $GIT_BRANCH; \
        else \
            echo 'Git repo not found, init and cloning...'; \
            git init && \
            git remote add origin $GIT_REPO_URL && \
            git pull origin $GIT_BRANCH; \
        fi"

    # init the swarm if not already inited
    if ! run_remote "docker info --format '{{.Swarm.LocalNodeState}}'" | grep -q "active"; then
        log "Initializing Docker Swarm"
        run_remote "docker swarm init"
        if [[ $? -eq 0 ]]; then
            log "Docker Swarm initialized successfully"
        else
            error "Failed to initialize Docker Swarm"
            return 1
        fi
    else
        info "Docker Swarm already initialized"
    fi

    # get a list of services on server
    remote_dirs=$(run_remote " find '$REMOTE_REPO_PATH' -maxdepth 1 -type d -not -path '$REMOTE_REPO_PATH' -printf '%f\n' | \ grep -v -E '^(scripts|docs|\.git)$' ")

    # for each remote dir add local .env file to docker
    for dir in $remote_dirs; do
        (
            # cd into local dir, read the secret, and the run the remote command to input the secret
            cd "$dir"

            # Read .env file and create secrets
            while IFS= read -r line || [[ -n "$line" ]]; do
                # Skip empty lines and comments
                [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
                # Extract key=value
                if [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
                    key="${BASH_REMATCH[1]}"
                    value="${BASH_REMATCH[2]}"

                    # Remove quotes if present
                    value=$(echo "$value" | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")

                    secret_name="${dir}_${key,,}" # Convert to lowercase

                    # Check if secret already exists
                    if run_remote "docker secret ls --format '{{.Name}}' | grep -q '^${secret_name}\$'"; then
                        info "Secret $secret_name already exists, removing old one"
                        run_remote "docker secret rm '$secret_name' || true"
                    fi
                    # Create secret
                    echo "$value" | run_remote "docker secret create '$secret_name' - 2>/dev/null"

                    if [[ $? -eq 0 ]]; then
                        info "Created secret: $secret_name"
                    else
                        error "Failed to create secret: $secret_name"
                    fi
                fi
            done <".env"

        )

    done

    # Build images from Dockerfiles only
    for dir in $remote_dirs; do
        full_path="$REMOTE_REPO_PATH/$dir"
        if run_remote "test -f '$full_path/Dockerfile'"; then
            log "Building $dir from Dockerfile"
            run_remote "cd '$full_path' && docker build -t '$dir:latest' '$dir'" || {
                error "Build failed: $dir"
                return 1
            }
            log "Built: $dir:latest"
        else
            info "No Dockerfile found in $dir, skipping"
        fi
    done

    # deploy
    for dir in $remote_dirs; do
        full_path="$REMOTE_REPO_PATH/$dir"
        if run_remote "test -f '$full_path/docker-compose.yml'"; then
            log "Deploying service: $dir"

            # Deploy the stack
            run_remote "cd $full_path && docker stack deploy -c docker-compose.yml '$dir'"

            if [[ $? -eq 0 ]]; then
                log "Successfully deployed service: $dir"
            else
                error "Failed to deploy service: $dir"
                return 1
            fi

        else
            warning "No docker-compose.yml found in $dir, skipping deployment"
        fi

    done

    info "all done"
}
