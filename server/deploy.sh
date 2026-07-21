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

run_remote_silent() {
    local command="$@"
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
        # create network that is used by beszel
        run_remote "docker network create --driver overlay --attachable management_net"

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
    all_dirs=$(run_remote_silent "find '$REMOTE_REPO_PATH' -maxdepth 1 -type d -not -path '$REMOTE_REPO_PATH'")
    remote_dirs=$(echo "$all_dirs" | sed 's|.*/||' | grep -v -E '^(scripts|docs|\.git)$')

    # for each remote dir add local .env file to docker
    for dir in $remote_dirs; do
        echo "  attempting to add secret for '$dir' "
        (
            # cd into local dir, read the secret, and the run the remote command to input the secret
            cd "$dir"
            # Check if .env file exists
            if [[ ! -f ".env" ]]; then
                echo "No .env file found in '$dir', skipping..."
                exit 0 # Exit the subshell, continue with next directory
            fi

            # Arrays to store keys and values
            declare -a keys=()
            declare -a values=()

            # Read .env file
            while IFS= read -r line || [[ -n "$line" ]]; do
                # Skip empty lines and comments
                [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
                # Extract key=value

                if [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
                    key="${BASH_REMATCH[1]}"
                    value="${BASH_REMATCH[2]}"

                    echo "    key found '$key'"
                    # Remove quotes if present
                    value=$(echo "$value" | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
                    secret_name="${dir}_${key,,}" # Convert to lowercase

                    # Add to arrays
                    keys+=("$key")
                    values+=("$value")

                fi
            done <".env"
            # create each secret
            for i in "${!keys[@]}"; do
                key="${keys[$i]}"
                value="${values[$i]}"

                secret_name="${dir}_${key,,}" # Convert to lowercase

                # check if secret is in use
                if run_remote "docker service ls --quiet | xargs -r docker service inspect | grep -q '\"SecretName\": \"${secret_name}\"' || docker service ls --quiet | xargs -r docker service inspect | grep -q '\"Source\": \"${secret_name}\"'"; then
                    info "Secret $secret_name is in use by services, skipping removal"
                else
                    info "Secret $secret_name not in use"
                    # Check if secret exists
                    if run_remote "docker secret ls --format '{{.Name}}' | grep -q '^${secret_name}\$'"; then
                        info "Secret $secret_name already exists, removing old one"
                    fi
                    run_remote "docker secret rm '$secret_name' || true"
                    # Create secret
                    echo "$value" | run_remote "docker secret create '$secret_name' - 2>/dev/null"
                fi

                if [[ $? -eq 0 ]]; then
                    info "Created secret: $secret_name"
                else
                    error "Failed to create secret: $secret_name"
                fi

            done

        )

    done

    # Build images from Dockerfiles only
    for dir in $remote_dirs; do
        full_path="$REMOTE_REPO_PATH/$dir"
        if run_remote "test -f '$full_path/Dockerfile'"; then
            log "Building $dir from Dockerfile"
            run_remote "docker build -t '$dir:latest' '$full_path'" || {
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

    # make the dirs for bindmounts
    run_remote "mkdir -p ~/immich/library ~/immich/postgres"
    info "all done"
}

main
