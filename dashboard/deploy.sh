#!/bin/bash

# Cold Email Dashboard Deployment Script
# Automated deployment with rollback capability

set -e  # Exit on any error

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
SERVICE_NAME="cold-email-dashboard"
SERVICE_USER="dashboard"
PYTHON_VERSION="3.8"
VENV_PATH="/opt/cold-email-dashboard/venv"
APP_PATH="/opt/cold-email-dashboard"
BACKUP_DIR="/opt/cold-email-dashboard/backups"
LOG_DIR="/var/log/cold-email-dashboard"
CONFIG_DIR="/etc/cold-email-dashboard"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a /tmp/deployment.log
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a /tmp/deployment.log
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a /tmp/deployment.log
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a /tmp/deployment.log
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Create system user for the service
create_service_user() {
    log_info "Creating service user: $SERVICE_USER"
    
    if ! id "$SERVICE_USER" &>/dev/null; then
        useradd -r -s /bin/bash -d "$APP_PATH" -m "$SERVICE_USER"
        log_success "Service user created: $SERVICE_USER"
    else
        log_info "Service user already exists: $SERVICE_USER"
    fi
}

# Create directory structure
create_directories() {
    log_info "Creating directory structure"
    
    directories=("$APP_PATH" "$BACKUP_DIR" "$LOG_DIR" "$CONFIG_DIR")
    
    for dir in "${directories[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            log_success "Created directory: $dir"
        fi
    done
    
    # Set ownership
    chown -R $SERVICE_USER:$SERVICE_USER "$APP_PATH" "$LOG_DIR"
    chown -R root:$SERVICE_USER "$CONFIG_DIR"
    chmod 750 "$CONFIG_DIR"
}

# Install system dependencies
install_system_dependencies() {
    log_info "Installing system dependencies"
    
    # Update package list
    apt-get update -qq
    
    # Install Python and other dependencies
    apt-get install -y \
        python3 \
        python3-pip \
        python3-venv \
        python3-dev \
        build-essential \
        curl \
        wget \
        git \
        nginx \
        supervisor \
        ufw \
        fail2ban \
        logrotate \
        htop \
        tree \
        jq
    
    log_success "System dependencies installed"
}

# Create Python virtual environment
setup_python_environment() {
    log_info "Setting up Python virtual environment"
    
    # Remove existing venv if it exists
    if [[ -d "$VENV_PATH" ]]; then
        rm -rf "$VENV_PATH"
        log_info "Removed existing virtual environment"
    fi
    
    # Create new virtual environment
    sudo -u $SERVICE_USER python3 -m venv "$VENV_PATH"
    
    # Activate and upgrade pip
    sudo -u $SERVICE_USER "$VENV_PATH/bin/pip" install --upgrade pip setuptools wheel
    
    log_success "Python virtual environment created"
}

# Install Python dependencies
install_python_dependencies() {
    log_info "Installing Python dependencies"
    
    # Copy requirements.txt to app directory
    cp "$PROJECT_DIR/requirements.txt" "$APP_PATH/"
    chown $SERVICE_USER:$SERVICE_USER "$APP_PATH/requirements.txt"
    
    # Install from requirements.txt
    sudo -u $SERVICE_USER "$VENV_PATH/bin/pip" install -r "$APP_PATH/requirements.txt"
    
    log_success "Python dependencies installed"
}

# Deploy application files
deploy_application() {
    log_info "Deploying application files"
    
    # Create backup of existing deployment
    if [[ -d "$APP_PATH/dashboard" ]]; then
        backup_name="backup_$(date +%Y%m%d_%H%M%S)"
        sudo -u $SERVICE_USER mv "$APP_PATH/dashboard" "$BACKUP_DIR/$backup_name"
        log_info "Existing deployment backed up to: $BACKUP_DIR/$backup_name"
    fi
    
    # Copy application files
    sudo -u $SERVICE_USER mkdir -p "$APP_PATH/dashboard"
    cp -r "$PROJECT_DIR"/* "$APP_PATH/dashboard/"
    chown -R $SERVICE_USER:$SERVICE_USER "$APP_PATH/dashboard"
    
    # Make start script executable
    chmod +x "$APP_PATH/dashboard/start_dashboard.sh"
    
    log_success "Application files deployed"
}

# Create environment configuration
create_environment_config() {
    log_info "Creating environment configuration"
    
    cat > "$CONFIG_DIR/dashboard.env" << 'EOF'
# Flask Configuration
FLASK_ENV=production
FLASK_PORT=5000
FLASK_SECRET_KEY=change-this-secret-key-in-production

# Security
API_KEY=change-this-api-key-in-production

# Rate Limiting
RATE_LIMIT_REQUESTS=100
RATE_LIMIT_WINDOW=3600

# Email Configuration (update as needed)
DOMAIN=
SERVER_IP=
ADMIN_EMAIL=
DMARC_EMAIL=

# SMTP Configuration
SMTP_HOST=localhost
SMTP_PORT=587
SMTP_SECURITY=tls
SMTP_USER=
SMTP_PASSWORD=

# External API Keys
CLOUDFLARE_API_TOKEN=
MAILCOW_API_KEY=
MAILCOW_HOSTNAME=

# Logging
LOG_LEVEL=INFO
LOG_FILE=/var/log/cold-email-dashboard/dashboard.log
EOF
    
    # Set secure permissions
    chown root:$SERVICE_USER "$CONFIG_DIR/dashboard.env"
    chmod 640 "$CONFIG_DIR/dashboard.env"
    
    log_success "Environment configuration created"
    log_warning "Please edit $CONFIG_DIR/dashboard.env with your actual configuration"
}

# Configure firewall
configure_firewall() {
    log_info "Configuring firewall"
    
    # Enable UFW
    ufw --force enable
    
    # Allow SSH
    ufw allow ssh
    
    # Allow HTTP and HTTPS
    ufw allow 80/tcp
    ufw allow 443/tcp
    
    # Allow dashboard port (will be proxied by nginx)
    ufw allow 5000/tcp
    
    log_success "Firewall configured"
}

# Create systemd service
create_systemd_service() {
    log_info "Creating systemd service"
    
    cat > "/etc/systemd/system/$SERVICE_NAME.service" << EOF
[Unit]
Description=Cold Email Infrastructure Dashboard
After=network.target

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$APP_PATH/dashboard
Environment=PATH=$VENV_PATH/bin
EnvironmentFile=$CONFIG_DIR/dashboard.env
ExecStart=$VENV_PATH/bin/python app.py
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=mixed
TimeoutStopSec=5
PrivateTmp=true
Restart=always
RestartSec=10

# Security settings
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$APP_PATH $LOG_DIR
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true

[Install]
WantedBy=multi-user.target
EOF
    
    # Reload systemd and enable service
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    
    log_success "Systemd service created and enabled"
}

# Configure log rotation
configure_logging() {
    log_info "Configuring log rotation"
    
    cat > "/etc/logrotate.d/$SERVICE_NAME" << EOF
$LOG_DIR/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 644 $SERVICE_USER $SERVICE_USER
    postrotate
        systemctl reload $SERVICE_NAME > /dev/null 2>&1 || true
    endscript
}
EOF
    
    log_success "Log rotation configured"
}

# Test deployment
test_deployment() {
    log_info "Testing deployment"
    
    # Start the service
    systemctl start "$SERVICE_NAME"
    
    # Wait for service to start
    sleep 5
    
    # Check service status
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log_success "Service is running"
        
        # Test HTTP endpoint
        if curl -s -o /dev/null -w "%{http_code}" http://localhost:5000/api/health | grep -q "200"; then
            log_success "Health check endpoint is responding"
        else
            log_warning "Health check endpoint not responding properly"
        fi
    else
        log_error "Service failed to start"
        log_info "Service logs:"
        journalctl -u "$SERVICE_NAME" --no-pager -n 20
        return 1
    fi
}

# Display deployment summary
display_summary() {
    log_success "Deployment completed successfully!"
    
    echo ""
    echo "=== Deployment Summary ==="
    echo "Service Name: $SERVICE_NAME"
    echo "Service User: $SERVICE_USER"
    echo "Application Path: $APP_PATH"
    echo "Configuration: $CONFIG_DIR/dashboard.env"
    echo "Logs: $LOG_DIR/"
    echo "Virtual Environment: $VENV_PATH"
    echo ""
    echo "=== Service Management ==="
    echo "Start service: systemctl start $SERVICE_NAME"
    echo "Stop service: systemctl stop $SERVICE_NAME"
    echo "Restart service: systemctl restart $SERVICE_NAME"
    echo "Check status: systemctl status $SERVICE_NAME"
    echo "View logs: journalctl -u $SERVICE_NAME -f"
    echo ""
    echo "=== Access Information ==="
    echo "Dashboard URL: http://localhost:5000"
    echo "Health Check: http://localhost:5000/api/health"
    echo ""
    echo "=== Next Steps ==="
    echo "1. Edit configuration: $CONFIG_DIR/dashboard.env"
    echo "2. Configure nginx proxy (optional): see nginx/dashboard.conf"
    echo "3. Set up SSL certificate (optional): use certbot"
    echo "4. Configure monitoring and backups"
    echo ""
    log_warning "Remember to:"
    log_warning "- Change default secret keys in $CONFIG_DIR/dashboard.env"
    log_warning "- Configure your domain and email settings"
    log_warning "- Set up proper monitoring and backups"
}

# Rollback function
rollback_deployment() {
    log_warning "Rolling back deployment..."
    
    # Stop service
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    
    # Find latest backup
    latest_backup=$(ls -t "$BACKUP_DIR" 2>/dev/null | head -n 1)
    
    if [[ -n "$latest_backup" && -d "$BACKUP_DIR/$latest_backup" ]]; then
        # Restore from backup
        rm -rf "$APP_PATH/dashboard"
        sudo -u $SERVICE_USER mv "$BACKUP_DIR/$latest_backup" "$APP_PATH/dashboard"
        log_info "Restored from backup: $latest_backup"
        
        # Start service
        systemctl start "$SERVICE_NAME"
        log_success "Rollback completed"
    else
        log_error "No backup found for rollback"
    fi
}

# Cleanup function
cleanup_on_error() {
    log_error "Deployment failed. Performing cleanup..."
    
    # Stop service if it was created
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    systemctl disable "$SERVICE_NAME" 2>/dev/null || true
    
    # Remove systemd service file
    rm -f "/etc/systemd/system/$SERVICE_NAME.service"
    systemctl daemon-reload
    
    # Rollback if possible
    rollback_deployment
}

# Main deployment function
main() {
    log_info "Starting Cold Email Dashboard deployment..."
    
    # Set up error handling
    trap cleanup_on_error ERR
    
    # Check prerequisites
    check_root
    
    # Create user and directories
    create_service_user
    create_directories
    
    # Install dependencies
    install_system_dependencies
    setup_python_environment
    install_python_dependencies
    
    # Deploy application
    deploy_application
    create_environment_config
    
    # Configure system services
    configure_firewall
    create_systemd_service
    configure_logging
    
    # Test deployment
    test_deployment
    
    # Display summary
    display_summary
    
    log_success "Deployment completed successfully!"
}

# Parse command line arguments
case "${1:-deploy}" in
    deploy)
        main
        ;;
    rollback)
        rollback_deployment
        ;;
    test)
        test_deployment
        ;;
    *)
        echo "Usage: $0 {deploy|rollback|test}"
        echo "  deploy   - Full deployment (default)"
        echo "  rollback - Rollback to previous version"
        echo "  test     - Test current deployment"
        exit 1
        ;;
esac