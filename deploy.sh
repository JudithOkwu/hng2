#!/bin/bash

#######################################
# Complete Automated Deployment & Validation Script
# Purpose: Deploy and validate Dockerized application
# Author: DevOps Intern Stage 1
# Date: $(date +%Y-%m-%d)
#######################################

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log files
LOG_FILE="deploy_$(date +%Y%m%d_%H%M%S).log"
VALIDATION_LOG="validate_$(date +%Y%m%d_%H%M%S).log"
VALIDATION_JSON="validation_summary.json"
DEPLOYMENT_ENV="deployment.env"

# Validation counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
WARNING_TESTS=0

#######################################
# Logging Functions
#######################################
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1" | tee -a "$LOG_FILE"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1" | tee -a "$VALIDATION_LOG"
    ((PASSED_TESTS++))
    ((TOTAL_TESTS++))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1" | tee -a "$VALIDATION_LOG"
    ((FAILED_TESTS++))
    ((TOTAL_TESTS++))
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$VALIDATION_LOG"
    ((WARNING_TESTS++))
    ((TOTAL_TESTS++))
}

#######################################
# Error Handler
#######################################
error_exit() {
    log_error "$1"
    exit "${2:-1}"
}

# Trap errors
trap 'error_exit "Script failed at line $LINENO" 1' ERR
trap 'log_info "Script interrupted by user"; exit 130' INT TERM

#######################################
# Validation Functions
#######################################
validate_url() {
    local url="$1"
    if [[ ! "$url" =~ ^https?:// ]]; then
        return 1
    fi
    return 0
}

validate_ip() {
    local ip="$1"
    if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 0
    fi
    return 1
}

validate_port() {
    local port="$1"
    if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1024 ] && [ "$port" -le 65535 ]; then
        return 0
    fi
    return 1
}

validate_file_exists() {
    local file="$1"
    if [ ! -f "$file" ]; then
        return 1
    fi
    return 0
}

#######################################
# User Input Collection
#######################################
collect_user_input() {
    log_info "Collecting deployment parameters..."

    # Git Repository URL
    while true; do
        read -p "Enter Git Repository URL: " REPO_URL
        if validate_url "$REPO_URL"; then
            break
        else
            log_error "Invalid URL format. Please enter a valid HTTP/HTTPS URL."
        fi
    done

    # Personal Access Token
    while true; do
        read -s -p "Enter Personal Access Token (PAT): " PAT
        echo
        if [ -n "$PAT" ]; then
            break
        else
            log_error "PAT cannot be empty."
        fi
    done

    # Branch name
    read -p "Enter branch name (default: main): " BRANCH
    BRANCH="${BRANCH:-main}"

    # SSH Username
    while true; do
        read -p "Enter SSH username: " SSH_USER
        if [ -n "$SSH_USER" ]; then
            break
        else
            log_error "Username cannot be empty."
        fi
    done

    # Server IP
    while true; do
        read -p "Enter server IP address: " SERVER_IP
        if validate_ip "$SERVER_IP"; then
            break
        else
            log_error "Invalid IP address format."
        fi
    done

    # SSH Key Path
    while true; do
        read -p "Enter SSH key path: " SSH_KEY_PATH
        if validate_file_exists "$SSH_KEY_PATH"; then
            # Check permissions
            PERMS=$(stat -f "%A" "$SSH_KEY_PATH" 2>/dev/null || stat -c "%a" "$SSH_KEY_PATH" 2>/dev/null)
            if [ "$PERMS" != "600" ] && [ "$PERMS" != "400" ]; then
                log_warning "SSH key permissions are $PERMS. Setting to 600..."
                chmod 600 "$SSH_KEY_PATH"
            fi
            break
        else
            log_error "SSH key file not found at: $SSH_KEY_PATH"
        fi
    done

    # Application Port
    while true; do
        read -p "Enter application port (1024-65535): " APP_PORT
        if validate_port "$APP_PORT"; then
            break
        else
            log_error "Invalid port. Must be between 1024 and 65535."
        fi
    done

    log "All parameters collected successfully."
}

#######################################
# Repository Management
#######################################
clone_repository() {
    log_info "Managing repository..."

    # Extract repo name from URL
    REPO_NAME=$(basename "$REPO_URL" .git)
    LOCAL_REPO_PATH="./$REPO_NAME"

    # Build authenticated URL
    if [[ "$REPO_URL" =~ ^https://github.com ]]; then
        AUTH_URL=$(echo "$REPO_URL" | sed "s|https://|https://${PAT}@|")
    else
        AUTH_URL="$REPO_URL"
    fi

    if [ -d "$LOCAL_REPO_PATH" ]; then
        log_warning "Repository directory exists. Pulling latest changes..."
        cd "$LOCAL_REPO_PATH" || error_exit "Failed to enter repository directory" 1
        git pull origin "$BRANCH" >> "$LOG_FILE" 2>&1 || error_exit "Failed to pull latest changes" 1
    else
        log_info "Cloning repository..."
        git clone "$AUTH_URL" "$LOCAL_REPO_PATH" >> "$LOG_FILE" 2>&1 || error_exit "Failed to clone repository" 1
        cd "$LOCAL_REPO_PATH" || error_exit "Failed to enter repository directory" 1
    fi

    # Checkout branch
    log_info "Checking out branch: $BRANCH"
    git checkout "$BRANCH" >> "$LOG_FILE" 2>&1 || error_exit "Failed to checkout branch $BRANCH" 1

    # Validate Dockerfile or docker-compose.yml exists
    if [ ! -f "Dockerfile" ] && [ ! -f "docker-compose.yml" ]; then
        error_exit "Neither Dockerfile nor docker-compose.yml found in repository" 1
    fi

    if [ -f "Dockerfile" ]; then
        log "Found Dockerfile"
        DEPLOY_TYPE="dockerfile"
    fi

    if [ -f "docker-compose.yml" ]; then
        log "Found docker-compose.yml"
        DEPLOY_TYPE="compose"
    fi

    cd - > /dev/null
}

#######################################
# SSH Connectivity Test
#######################################
test_ssh_connection() {
    log_info "Testing SSH connectivity to $SERVER_IP..."

    if ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=no \
        "$SSH_USER@$SERVER_IP" "echo 'SSH connection successful'" >> "$LOG_FILE" 2>&1; then
        log "SSH connection successful"
    else
        error_exit "Failed to establish SSH connection to $SERVER_IP" 2
    fi
}

#######################################
# Remote Server Preparation
#######################################
prepare_remote_server() {
    log_info "Preparing remote server environment..."

    # Update system packages
    log_info "Updating system packages..."
    ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" << 'ENDSSH' >> "$LOG_FILE" 2>&1
        sudo apt update -y
        sudo apt upgrade -y
ENDSSH

    # Install Docker
    log_info "Installing Docker..."
    ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" << 'ENDSSH' >> "$LOG_FILE" 2>&1
        if ! command -v docker &> /dev/null; then
            echo "Installing Docker..."
            sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            sudo apt update -y
            sudo apt install -y docker-ce docker-ce-cli containerd.io
        else
            echo "Docker already installed"
        fi
ENDSSH

    # Install Docker Compose
    log_info "Installing Docker Compose..."
    ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" << 'ENDSSH' >> "$LOG_FILE" 2>&1
        if ! command -v docker-compose &> /dev/null; then
            echo "Installing Docker Compose..."
            sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
            sudo chmod +x /usr/local/bin/docker-compose
        else
            echo "Docker Compose already installed"
        fi
ENDSSH

    # Install Nginx
    log_info "Installing Nginx..."
    ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" << 'ENDSSH' >> "$LOG_FILE" 2>&1
        if ! command -v nginx &> /dev/null; then
            echo "Installing Nginx..."
            sudo apt install -y nginx
        else
            echo "Nginx already installed"
        fi
ENDSSH

    # Add user to docker group and fix permissions
    log_info "Adding user to docker group and fixing permissions..."
    ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" << ENDSSH >> "$LOG_FILE" 2>&1
        sudo usermod -aG docker $SSH_USER
        # Fix Docker socket permissions
        sudo chmod 666 /var/run/docker.sock
ENDSSH

    # Enable and start services
    log_info "Enabling and starting services..."
    ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" << 'ENDSSH' >> "$LOG_FILE" 2>&1
        sudo systemctl enable docker
        sudo systemctl start docker
        sudo systemctl restart docker
        sudo systemctl enable nginx
        sudo systemctl start nginx
ENDSSH

    # Verify installations
    log_info "Verifying installations..."
    ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" << 'ENDSSH' | tee -a "$LOG_FILE"
        echo "Docker version:"
        docker --version
        echo "Docker Compose version:"
        docker-compose --version
        echo "Nginx version:"
        nginx -v
ENDSSH

    log "Remote server preparation completed"
}

#######################################
# Transfer Files and Deploy
#######################################
deploy_application() {
    log_info "Deploying application to remote server..."

    REMOTE_PATH="~/deployments/$REPO_NAME"

    # Create remote directory
    ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" "mkdir -p $REMOTE_PATH" >> "$LOG_FILE" 2>&1

    # Transfer files using rsync
    log_info "Transferring files to remote server..."
    rsync -avz -e "ssh -i $SSH_KEY_PATH" \
        --exclude='.git' \
        --exclude='node_modules' \
        --exclude='__pycache__' \
        "./$REPO_NAME/" \
        "$SSH_USER@$SERVER_IP:$REMOTE_PATH/" >> "$LOG_FILE" 2>&1 || error_exit "Failed to transfer files" 3

    log "Files transferred successfully"

    # Stop and remove existing containers
    log_info "Stopping existing containers..."
    CONTAINER_NAME=$(echo "$REPO_NAME" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]-')

    ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" << ENDSSH >> "$LOG_FILE" 2>&1
        cd $REMOTE_PATH
        # Stop and remove existing container
        if docker ps -a | grep -q "$CONTAINER_NAME"; then
            echo "Stopping and removing existing container: $CONTAINER_NAME"
            docker stop "$CONTAINER_NAME" 2>/dev/null || true
            docker rm "$CONTAINER_NAME" 2>/dev/null || true
        fi
ENDSSH

    # Deploy based on type
    if [ "$DEPLOY_TYPE" = "compose" ]; then
        log_info "Deploying with docker-compose..."
        ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" << ENDSSH >> "$LOG_FILE" 2>&1
            cd $REMOTE_PATH
            docker-compose down 2>/dev/null || true
            docker-compose up -d --build
ENDSSH
    else
        log_info "Deploying with Dockerfile..."
        ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" << ENDSSH >> "$LOG_FILE" 2>&1
            cd $REMOTE_PATH
            docker build -t $CONTAINER_NAME .
            docker run -d --name $CONTAINER_NAME -p $APP_PORT:$APP_PORT $CONTAINER_NAME
ENDSSH
    fi

    # Wait for container to be healthy
    log_info "Waiting for container to start..."
    sleep 5

    # Verify container is running
    if ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" "docker ps | grep -q '$CONTAINER_NAME'"; then
        log "Container deployed successfully"
    else
        error_exit "Container failed to start. Check logs for details." 3
    fi
}

#######################################
# Configure Nginx Reverse Proxy
#######################################
configure_nginx() {
    log_info "Configuring Nginx reverse proxy..."

    # Create Nginx config
    NGINX_CONFIG="/etc/nginx/sites-available/app-proxy"

    ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" << ENDSSH >> "$LOG_FILE" 2>&1
        # Backup existing config if present
        if [ -f "$NGINX_CONFIG" ]; then
            sudo cp "$NGINX_CONFIG" "${NGINX_CONFIG}.backup.\$(date +%Y%m%d_%H%M%S)"
        fi

        # Create new config
        sudo tee "$NGINX_CONFIG" > /dev/null << 'EOF'
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://localhost:$APP_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;

        # Security headers
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-XSS-Protection "1; mode=block" always;
    }
}
EOF

        # Enable site
        sudo ln -sf "$NGINX_CONFIG" /etc/nginx/sites-enabled/app-proxy

        # Remove default if exists
        sudo rm -f /etc/nginx/sites-enabled/default

        # Test configuration
        sudo nginx -t

        # Reload Nginx
        sudo systemctl reload nginx
ENDSSH

    if [ $? -eq 0 ]; then
        log "Nginx configured successfully"
    else
        error_exit "Failed to configure Nginx" 4
    fi
}

#######################################
# Save Deployment Information
#######################################
save_deployment_info() {
    log_info "Saving deployment information..."

    cat > "$DEPLOYMENT_ENV" << EOF
# Deployment Configuration
# Generated: $(date)
SERVER_IP=$SERVER_IP
SERVER_USER=$SSH_USER
SSH_KEY_PATH=$SSH_KEY_PATH
APP_PORT=$APP_PORT
CONTAINER_NAME=$CONTAINER_NAME
REPO_NAME=$REPO_NAME
DEPLOY_TYPE=$DEPLOY_TYPE
LOG_FILE=$LOG_FILE
DEPLOYMENT_PATH=~/deployments/$REPO_NAME
EOF

    log "Deployment information saved to $DEPLOYMENT_ENV"
}

#######################################
# VALIDATION FUNCTIONS
#######################################

#######################################
# Service Validation
#######################################
validate_services() {
    log_info "========================================="
    log_info "VALIDATING REMOTE SERVICES"
    log_info "========================================="

    # Test Docker service
    log_info "Checking Docker service..."
    if ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" "systemctl is-active docker" >> "$VALIDATION_LOG" 2>&1; then
        log_pass "Docker service is running"
    else
        log_fail "Docker service is not running"
        return 10
    fi

    # Test Nginx service
    log_info "Checking Nginx service..."
    if ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" "systemctl is-active nginx" >> "$VALIDATION_LOG" 2>&1; then
        log_pass "Nginx service is running"
    else
        log_fail "Nginx service is not running"
        return 10
    fi

    # Test container status
    log_info "Checking container status..."
    if ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" "docker ps | grep -q '$CONTAINER_NAME'" >> "$VALIDATION_LOG" 2>&1; then
        log_pass "Container '$CONTAINER_NAME' is running"
    else
        log_fail "Container '$CONTAINER_NAME' is not running"
        ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" "docker ps -a | grep '$CONTAINER_NAME'" >> "$VALIDATION_LOG" 2>&1 || true
        return 10
    fi

    # Check container health
    log_info "Checking container health..."
    HEALTH_STATUS=$(ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" \
        "docker inspect --format='{{.State.Status}}' $CONTAINER_NAME 2>/dev/null" || echo "unknown")

    if [ "$HEALTH_STATUS" = "running" ]; then
        log_pass "Container health status: $HEALTH_STATUS"
    else
        log_warn "Container status: $HEALTH_STATUS"
    fi

    # Check container logs for errors
    log_info "Checking container logs for critical errors..."
    ERROR_COUNT=$(ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" \
        "docker logs --tail=50 $CONTAINER_NAME 2>&1 | grep -iE 'error|exception|fatal|critical' | wc -l" || echo "0")

    if [ "$ERROR_COUNT" -eq 0 ]; then
        log_pass "No critical errors found in container logs"
    else
        log_warn "Found $ERROR_COUNT potential error messages in container logs"
    fi
}

#######################################
# Network Connectivity Tests
#######################################
validate_network() {
    log_info "========================================="
    log_info "VALIDATING NETWORK CONNECTIVITY"
    log_info "========================================="

    # Test container responds on internal port
    log_info "Testing container on internal port $APP_PORT..."
    if ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" \
        "curl -f -s -o /dev/null -w '%{http_code}' http://localhost:$APP_PORT --max-time 5" >> "$VALIDATION_LOG" 2>&1; then
        log_pass "Container responds on port $APP_PORT"
    else
        log_fail "Container not responding on port $APP_PORT"
        return 11
    fi

    # Test Nginx proxying
    log_info "Testing Nginx proxy on port 80..."
    RESPONSE_CODE=$(ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" \
        "curl -s -o /dev/null -w '%{http_code}' http://localhost:80 --max-time 5" || echo "000")

    if [ "$RESPONSE_CODE" = "200" ] || [ "$RESPONSE_CODE" = "301" ] || [ "$RESPONSE_CODE" = "302" ]; then
        log_pass "Nginx proxy responding (HTTP $RESPONSE_CODE)"
    else
        log_fail "Nginx proxy not responding correctly (HTTP $RESPONSE_CODE)"
        return 11
    fi

    # Test Nginx config syntax
    log_info "Validating Nginx configuration syntax..."
    if ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" "sudo nginx -t" >> "$VALIDATION_LOG" 2>&1; then
        log_pass "Nginx configuration syntax is valid"
    else
        log_fail "Nginx configuration has syntax errors"
        return 11
    fi

    # Test external HTTP access
    log_info "Testing external HTTP access..."
    START_TIME=$(date +%s%N)
    EXT_RESPONSE_CODE=$(curl -s -o /dev/null -w '%{http_code}' "http://$SERVER_IP" --max-time 10 || echo "000")
    END_TIME=$(date +%s%N)
    RESPONSE_TIME=$(( (END_TIME - START_TIME) / 1000000 ))

    if [ "$EXT_RESPONSE_CODE" = "200" ] || [ "$EXT_RESPONSE_CODE" = "301" ] || [ "$EXT_RESPONSE_CODE" = "302" ]; then
        log_pass "External access successful (HTTP $EXT_RESPONSE_CODE, ${RESPONSE_TIME}ms)"

        if [ "$RESPONSE_TIME" -gt 2000 ]; then
            log_warn "Response time is slow: ${RESPONSE_TIME}ms (threshold: 2000ms)"
        else
            log_pass "Response time is acceptable: ${RESPONSE_TIME}ms"
        fi
    else
        log_fail "External access failed (HTTP $EXT_RESPONSE_CODE)"
        return 11
    fi

    # Verify Nginx headers
    log_info "Verifying response headers..."
    HEADERS=$(curl -s -I "http://$SERVER_IP" --max-time 5 || echo "")

    if echo "$HEADERS" | grep -qi "server.*nginx"; then
        log_pass "Nginx signature found in headers"
    else
        log_warn "Nginx signature not found in headers"
    fi
}

#######################################
# Resource Validation
#######################################
validate_resources() {
    log_info "========================================="
    log_info "VALIDATING SYSTEM RESOURCES"
    log_info "========================================="

    # Check disk usage
    log_info "Checking disk usage for /var/lib/docker..."
    DISK_USAGE=$(ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" \
        "df -h /var/lib/docker | tail -1 | awk '{print \$5}' | sed 's/%//'" || echo "0")

    if [ "$DISK_USAGE" -lt 80 ]; then
        log_pass "Disk usage: ${DISK_USAGE}% (healthy)"
    elif [ "$DISK_USAGE" -lt 90 ]; then
        log_warn "Disk usage: ${DISK_USAGE}% (warning threshold)"
    else
        log_fail "Disk usage: ${DISK_USAGE}% (critical)"
    fi

    # Check memory usage
    log_info "Checking memory usage..."
    MEMORY_USAGE=$(ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" \
        "free | grep Mem | awk '{printf \"%.0f\", \$3/\$2 * 100.0}'" || echo "0")

    if [ "$MEMORY_USAGE" -lt 90 ]; then
        log_pass "Memory usage: ${MEMORY_USAGE}% (healthy)"
    else
        log_warn "Memory usage: ${MEMORY_USAGE}% (high)"
    fi

    # Check container resource usage
    log_info "Checking container resource usage..."
    ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" \
        "docker stats --no-stream $CONTAINER_NAME" >> "$VALIDATION_LOG" 2>&1 || true
    log_pass "Container stats logged (see $VALIDATION_LOG)"
}

#######################################
# Security Checks
#######################################
validate_security() {
    log_info "========================================="
    log_info "VALIDATING SECURITY CONFIGURATION"
    log_info "========================================="

    # Check Nginx security headers
    log_info "Checking Nginx security headers..."
    SECURITY_HEADERS=$(curl -s -I "http://$SERVER_IP" --max-time 5 || echo "")

    if echo "$SECURITY_HEADERS" | grep -qi "X-Frame-Options"; then
        log_pass "X-Frame-Options header present"
    else
        log_warn "X-Frame-Options header missing"
    fi

    if echo "$SECURITY_HEADERS" | grep -qi "X-Content-Type-Options"; then
        log_pass "X-Content-Type-Options header present"
    else
        log_warn "X-Content-Type-Options header missing"
    fi

    # Check container user
    log_info "Checking container user..."
    CONTAINER_USER=$(ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" \
        "docker exec $CONTAINER_NAME whoami 2>/dev/null" || echo "unknown")

    if [ "$CONTAINER_USER" = "root" ]; then
        log_warn "Container is running as root (security concern)"
    else
        log_pass "Container running as non-root user: $CONTAINER_USER"
    fi

    # Check SSH key permissions
    log_info "Checking SSH key permissions..."
    KEY_PERMS=$(stat -f "%A" "$SSH_KEY_PATH" 2>/dev/null || stat -c "%a" "$SSH_KEY_PATH" 2>/dev/null)

    if [ "$KEY_PERMS" = "600" ] || [ "$KEY_PERMS" = "400" ]; then
        log_pass "SSH key permissions are secure: $KEY_PERMS"
    else
        log_warn "SSH key permissions should be 600 or 400 (current: $KEY_PERMS)"
    fi
}

#######################################
# Generate JSON Summary
#######################################
generate_json_summary() {
    log_info "Generating JSON summary..."

    cat > "$VALIDATION_JSON" << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "server": "$SERVER_IP",
  "container": "$CONTAINER_NAME",
  "results": {
    "total_tests": $TOTAL_TESTS,
    "passed": $PASSED_TESTS,
    "failed": $FAILED_TESTS,
    "warnings": $WARNING_TESTS,
    "success_rate": $(awk "BEGIN {printf \"%.2f\", ($PASSED_TESTS/$TOTAL_TESTS)*100}")
  },
  "validation_log": "$VALIDATION_LOG"
}
EOF

    log "JSON summary saved to $VALIDATION_JSON"
}

#######################################
# Print Summary Report
#######################################
print_summary() {
    echo "" | tee -a "$VALIDATION_LOG"
    log_info "========================================="
    log_info "VALIDATION SUMMARY"
    log_info "========================================="
    log_info "Total Tests: $TOTAL_TESTS"
    log_pass "Passed: $PASSED_TESTS"
    log_fail "Failed: $FAILED_TESTS"
    log_warn "Warnings: $WARNING_TESTS"

    SUCCESS_RATE=$(awk "BEGIN {printf \"%.1f\", ($PASSED_TESTS/$TOTAL_TESTS)*100}")
    log_info "Success Rate: ${SUCCESS_RATE}%"
    log_info "========================================="
    log_info "Validation Log: $VALIDATION_LOG"
    log_info "JSON Summary: $VALIDATION_JSON"
    log_info "========================================="

    if [ $FAILED_TESTS -eq 0 ]; then
        log ""
        log "${GREEN}ALL VALIDATIONS PASSED!${NC}"
        log "Deployment is healthy and ready for production"
        return 0
    else
        log ""
        log_error "VALIDATION FAILED"
        log_error "$FAILED_TESTS test(s) failed. Please review the logs."
        return 13
    fi
}

#######################################
# Main Execution
#######################################
main() {
    log_info "========================================="
    log_info "AUTOMATED DEPLOYMENT & VALIDATION SCRIPT"
    log_info "========================================="
    log_info "Starting deployment process..."
    log_info "Deployment log: $LOG_FILE"
    log_info "Validation log: $VALIDATION_LOG"
    echo ""

    # PHASE 1: DEPLOYMENT
    log_info "========================================="
    log_info "PHASE 1: DEPLOYMENT"
    log_info "========================================="

    collect_user_input
    clone_repository
    test_ssh_connection
    prepare_remote_server
    deploy_application
    configure_nginx
    save_deployment_info

    log ""
    log "========================================="
    log "DEPLOYMENT COMPLETED SUCCESSFULLY"
    log "========================================="
    log "Server IP: $SERVER_IP"
    log "Application Port: $APP_PORT"
    log "Container Name: $CONTAINER_NAME"
    log "Access your application at: http://$SERVER_IP"
    log "========================================="
    echo ""

    # PHASE 2: VALIDATION
    log_info "========================================="
    log_info "PHASE 2: VALIDATION"
    log_info "========================================="
    log_info "Starting deployment validation..."
    echo ""

    # Run validation tests
    validate_services || EXIT_CODE=$?
    validate_network || EXIT_CODE=$?
    validate_resources || EXIT_CODE=$?
    validate_security || EXIT_CODE=$?

    # Generate reports
    generate_json_summary
    print_summary || EXIT_CODE=$?

    log ""
    log "========================================="
    log "COMPLETE: DEPLOYMENT & VALIDATION FINISHED"
    log "========================================="
    log "Deployment Log: $LOG_FILE"
    log "Validation Log: $VALIDATION_LOG"
    log "JSON Summary: $VALIDATION_JSON"
    log "Configuration: $DEPLOYMENT_ENV"
    log "Application URL: http://$SERVER_IP"
    log "========================================="

    exit ${EXIT_CODE:-0}
}

# Run main function
main
