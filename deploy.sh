#!/bin/bash

# Docker Swarm Deployment Script
# This script creates secrets from .env files, builds images, and deploys services

set -e  # Exit on any error

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICES_DIR="$SCRIPT_DIR"
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

# git func
get_or_update_repo() {
    log "Navigating to $PROJECT_DIR and pulling latest code..."
        run_remote "cd $PROJECT_DIR && \
            if [ -d .git ]; then \
                echo 'Git repo exists, pulling...'; \
                git pull origin $GIT_BRANCH; \
            else \
                echo 'Git repo not found, init and cloning...'; \
                git init && \
                git remote add origin $GIT_REPO_URL && \
                git pull origin $GIT_BRANCH; \
            fi"
}

# Function to create Docker secrets from .env file
create_secrets_from_env() {
    local env_file="$1"
    local service_name="$2"
    
    if [[ ! -f "$env_file" ]]; then
        warning "No .env file found at $env_file"
        return 0
    fi
    
    log "Creating secrets from $env_file for service: $service_name"
    
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
            
            secret_name="${service_name}_${key,,}"  # Convert to lowercase
            
            # Check if secret already exists
            if run_remote "docker secret ls --format '{{.Name}}' | grep -q '^${secret_name}$'"; then
                info "Secret $secret_name already exists, removing old one"
                run_remote "docker secret rm '$secret_name' || true"
            fi
            
            # Create secret
            run_remote "echo '$value' | docker secret create '$secret_name' - 2>/dev/null"

            if [[ $? -eq 0 ]]; then
                info "Created secret: $secret_name"
            else
                error "Failed to create secret: $secret_name"
            fi
        fi
    done < "$env_file"
}

# Function to build Docker image if Dockerfile exists
build_image() {
    local service_dir="$1"
    local service_name="$2"
    
    if [[ -f "$service_dir/Dockerfile" ]]; then
        log "Building image for $service_name"
        
        # Build the image
        run_remote "docker build -t '$service_name:latest' '$service_dir'"
        
        if [[ $? -eq 0 ]]; then
            log "Successfully built image: $service_name:latest"
        else
            error "Failed to build image for $service_name"
            return 1
        fi
    else
        info "No Dockerfile found in $service_dir, skipping build"
    fi
}

# Function to deploy service using docker-compose
deploy_service() {
    local service_dir="$1"
    local service_name="$2"
    
    if [[ -f "$service_dir/docker-compose.yml" ]]; then
        log "Deploying service: $service_name"
        
        # Change to service directory
        run_remote "cd $service_dir" 
        
        # Deploy the stack
        run_remote "docker stack deploy -c docker-compose.yml '$service_name'"
        
        if [[ $? -eq 0 ]]; then
            log "Successfully deployed service: $service_name"
        else
            error "Failed to deploy service: $service_name"
            return 1
        fi
        
    else
        warning "No docker-compose.yml found in $service_dir, skipping deployment"
    fi
}

# Function to initialize Docker Swarm if not already initialized
init_swarm() {
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
}

# Function to list available services
list_services() {
    log "Available services:"
    for dir in "$SERVICES_DIR"/*; do
        if [[ -d "$dir" ]]; then
            service_name=$(basename "$dir")
            has_dockerfile=""
            has_compose=""
            has_env=""
            
            [[ -f "$dir/Dockerfile" ]] && has_dockerfile="✓ Dockerfile"
            [[ -f "$dir/docker-compose.yml" ]] && has_compose="✓ docker-compose.yml"
            [[ -f "$dir/.env" ]] && has_env="✓ .env"
            
            info "  $service_name: $has_dockerfile $has_compose $has_env"
        fi
    done
}

# Function to process a single service
process_service() {
    local service_dir="$1"
    local service_name="$2"
    
    log "Processing service: $service_name"
    
    # Create secrets from .env file
    create_secrets_from_env "$service_dir/.env" "$service_name"
    
    # Build image if Dockerfile exists
    build_image "$service_dir" "$service_name"
    
    # Deploy service
    deploy_service "$service_dir" "$service_name"
}

# Function to clean up old secrets
cleanup_secrets() {
    local service_name="$1"
    
    log "Cleaning up old secrets for service: $service_name"
    
    # Remove secrets that start with service name
    run_remote "docker secret ls --format '{{.Name}}'" | grep "^${service_name}_" | while read -r secret; do
            if docker secret rm \"\$secret\" 2>/dev/null; then
                echo \"Successfully removed secret: \$secret\"
            else
                echo \"Failed to remove secret: \$secret\"
            fi
        done
    "
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
    local service_filter="$1"
    local action="${2:-deploy}"
    
    log "Starting Docker Swarm deployment script"
    
    # Initialize swarm if needed
    init_swarm
    
    case "$action" in
        "list")
            list_services
            exit 0
            ;;
        "cleanup")
            if [[ -n "$service_filter" ]]; then
                cleanup_secrets "$service_filter"
            else
                error "Please specify a service name for cleanup"
                exit 1
            fi
            exit 0
            ;;
        "deploy")
            # Continue with deployment
            ;;
        *)
            error "Unknown action: $action"
            echo "Usage: $0 [service_name] [deploy|list|cleanup]"
            exit 1
            ;;
    esac
    
    # Process services
    if [[ -n "$service_filter" ]]; then
        # Process specific service
        service_dir="$SERVICES_DIR/$service_filter"
        if [[ -d "$service_dir" ]]; then
            process_service "$service_dir" "$service_filter"
        else
            error "Service directory not found: $service_dir"
            exit 1
        fi
    else
        # Process all services
        for dir in "$SERVICES_DIR"/*; do
            if [[ -d "$dir" ]]; then
                service_name=$(basename "$dir")
                # Skip common non-service directories
                if [[ "$service_name" != "scripts" && "$service_name" != "docs" && "$service_name" != ".git" ]]; then
                    process_service "$dir" "$service_name"
                fi
            fi
        done
    fi
    
    log "Deployment completed!"
    
    # Show running services
    info "Current Docker Swarm services:"
    run_remote "docker service ls"
}

# Help function
show_help() {
    cat << EOF
    Docker Swarm Deployment Script

    Usage: $0 [OPTIONS] [SERVICE_NAME] [ACTION]

    ACTIONS:
      deploy    Deploy services (default)
      list      List available services
      cleanup   Remove secrets for a specific service

    OPTIONS:
      -h, --help    Show this help message

    EXAMPLES:
      $0                    # Deploy all services
      $0 immich             # Deploy only immich service
      $0 list               # List all available services
      $0 immich cleanup     # Cleanup secrets for immich service

    DIRECTORY STRUCTURE:
      Your services should be organized like this:
      
      project/
      ├── immich/
      │   ├── docker-compose.yml
      │   └── .env
      ├── test-web-server/
      │   ├── Dockerfile
      │   └── .env
      └── deploy.sh (this script)

    The script will:
    1. Create Docker secrets from .env files
    2. Build images if Dockerfile exists
    3. Deploy services using docker-compose.yml via Docker Swarm

EOF
}

# Parse command line arguments
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    show_help
    exit 0
fi

# Run main function with arguments
main "$@"