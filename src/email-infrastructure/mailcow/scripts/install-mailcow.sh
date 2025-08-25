#!/bin/bash

# Mailcow Automated Installation Script
# This script automates the complete installation of Mailcow dockerized mail server
# Usage: ./install-mailcow.sh [domain] [email] [timezone]

set -e

# Configuration
MAILCOW_REPO="https://github.com/mailcow/mailcow-dockerized.git"
MAILCOW_DIR="/opt/mailcow-dockerized"
LOG_FILE="/var/log/mailcow-install.log"
CONFIG_DIR="$(dirname "$0")/../config"
TEMPLATES_DIR="$(dirname "$0")/../templates"

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
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
    fi
}

# Validate parameters
validate_params() {
    if [[ -z "$DOMAIN" ]]; then
        read -p "Enter your mail server domain (e.g., mail.example.com): " DOMAIN
    fi
    
    if [[ -z "$ADMIN_EMAIL" ]]; then
        read -p "Enter admin email address: " ADMIN_EMAIL
    fi
    
    if [[ -z "$TIMEZONE" ]]; then
        TIMEZONE=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "UTC")
    fi
    
    # Validate domain format
    if ! [[ "$DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*$ ]]; then
        error "Invalid domain format: $DOMAIN"
    fi
    
    # Validate email format
    if ! [[ "$ADMIN_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        error "Invalid email format: $ADMIN_EMAIL"
    fi
    
    info "Domain: $DOMAIN"
    info "Admin Email: $ADMIN_EMAIL"
    info "Timezone: $TIMEZONE"
}

# System requirements check
check_requirements() {
    log "Checking system requirements..."
    
    # Check OS
    if ! command -v lsb_release &> /dev/null; then
        warning "lsb_release not found, attempting to detect OS..."
        if [[ -f /etc/debian_version ]]; then
            OS="debian"
        elif [[ -f /etc/redhat-release ]]; then
            OS="rhel"
        else
            error "Unsupported operating system"
        fi
    else
        OS=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
    fi
    
    # Check if supported OS
    case "$OS" in
        ubuntu|debian)
            info "Detected supported OS: $OS"
            ;;
        centos|rhel|rocky|almalinux)
            info "Detected supported OS: $OS"
            ;;
        *)
            error "Unsupported OS: $OS. Mailcow supports Ubuntu, Debian, CentOS, RHEL, Rocky Linux, AlmaLinux"
            ;;
    esac
    
    # Check RAM (minimum 6GB recommended)
    RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
    if [[ $RAM_GB -lt 4 ]]; then
        error "Insufficient RAM: ${RAM_GB}GB detected. Minimum 4GB required, 6GB+ recommended"
    elif [[ $RAM_GB -lt 6 ]]; then
        warning "RAM: ${RAM_GB}GB detected. 6GB+ recommended for optimal performance"
    else
        info "RAM: ${RAM_GB}GB - OK"
    fi
    
    # Check disk space (minimum 20GB)
    DISK_GB=$(df / | awk 'NR==2 {print int($4/1024/1024)}')
    if [[ $DISK_GB -lt 20 ]]; then
        error "Insufficient disk space: ${DISK_GB}GB available. Minimum 20GB required"
    else
        info "Disk space: ${DISK_GB}GB available - OK"
    fi
    
    # Check if ports are available
    for port in 25 80 143 443 465 587 993 995 4190; do
        if ss -tuln | grep -q ":$port "; then
            warning "Port $port is already in use"
        fi
    done
}

# Install system dependencies
install_dependencies() {
    log "Installing system dependencies..."
    
    case "$OS" in
        ubuntu|debian)
            apt-get update
            apt-get install -y \
                curl \
                git \
                docker.io \
                docker-compose \
                openssl \
                ca-certificates \
                gnupg \
                lsb-release \
                ufw \
                fail2ban \
                htop \
                nano \
                wget \
                unzip
            
            # Enable and start Docker
            systemctl enable docker
            systemctl start docker
            ;;
        centos|rhel|rocky|almalinux)
            yum update -y || dnf update -y
            yum install -y curl git docker docker-compose openssl ca-certificates gnupg firewalld fail2ban htop nano wget unzip || \
            dnf install -y curl git docker docker-compose openssl ca-certificates gnupg firewalld fail2ban htop nano wget unzip
            
            # Enable and start Docker
            systemctl enable docker
            systemctl start docker
            ;;
    esac
    
    # Verify Docker installation
    if ! docker --version &>/dev/null; then
        error "Docker installation failed"
    fi
    
    if ! docker-compose --version &>/dev/null; then
        error "Docker Compose installation failed"
    fi
    
    info "Dependencies installed successfully"
}

# Configure firewall
configure_firewall() {
    log "Configuring firewall..."
    
    case "$OS" in
        ubuntu|debian)
            # Configure UFW
            ufw --force reset
            ufw default deny incoming
            ufw default allow outgoing
            
            # Allow SSH (current connection)
            ufw allow ssh
            
            # Allow Mailcow ports
            ufw allow 25/tcp    # SMTP
            ufw allow 80/tcp    # HTTP
            ufw allow 143/tcp   # IMAP
            ufw allow 443/tcp   # HTTPS
            ufw allow 465/tcp   # SMTPS
            ufw allow 587/tcp   # SMTP Submission
            ufw allow 993/tcp   # IMAPS
            ufw allow 995/tcp   # POP3S
            ufw allow 4190/tcp  # Sieve
            
            ufw --force enable
            ;;
        centos|rhel|rocky|almalinux)
            # Configure firewalld
            systemctl enable firewalld
            systemctl start firewalld
            
            # Allow Mailcow ports
            firewall-cmd --permanent --add-port=25/tcp
            firewall-cmd --permanent --add-port=80/tcp
            firewall-cmd --permanent --add-port=143/tcp
            firewall-cmd --permanent --add-port=443/tcp
            firewall-cmd --permanent --add-port=465/tcp
            firewall-cmd --permanent --add-port=587/tcp
            firewall-cmd --permanent --add-port=993/tcp
            firewall-cmd --permanent --add-port=995/tcp
            firewall-cmd --permanent --add-port=4190/tcp
            
            firewall-cmd --reload
            ;;
    esac
    
    info "Firewall configured successfully"
}

# Download and prepare Mailcow
download_mailcow() {
    log "Downloading Mailcow..."
    
    # Remove existing installation if present
    if [[ -d "$MAILCOW_DIR" ]]; then
        warning "Existing Mailcow installation found, backing up..."
        mv "$MAILCOW_DIR" "${MAILCOW_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    # Clone Mailcow repository
    git clone "$MAILCOW_REPO" "$MAILCOW_DIR"
    cd "$MAILCOW_DIR"
    
    # Get latest stable release
    LATEST_TAG=$(git describe --tags --abbrev=0)
    git checkout "$LATEST_TAG"
    
    info "Downloaded Mailcow version: $LATEST_TAG"
}

# Generate mailcow.conf
generate_config() {
    log "Generating Mailcow configuration..."
    
    cd "$MAILCOW_DIR"
    
    # Use template if available, otherwise generate
    if [[ -f "$TEMPLATES_DIR/mailcow.conf.template" ]]; then
        cp "$TEMPLATES_DIR/mailcow.conf.template" mailcow.conf
        
        # Replace placeholders
        sed -i "s/{{MAILCOW_HOSTNAME}}/$DOMAIN/g" mailcow.conf
        sed -i "s/{{ADMIN_EMAIL}}/$ADMIN_EMAIL/g" mailcow.conf
        sed -i "s/{{TIMEZONE}}/$TIMEZONE/g" mailcow.conf
        sed -i "s/{{HTTP_PORT}}/80/g" mailcow.conf
        sed -i "s/{{HTTPS_PORT}}/443/g" mailcow.conf
    else
        # Generate basic configuration
        cat > mailcow.conf << EOF
# Mailcow Configuration
MAILCOW_HOSTNAME=$DOMAIN
MAILCOW_PASS_SCHEME=BLF-CRYPT

# Admin user
ADMIN_EMAIL=$ADMIN_EMAIL

# HTTP/HTTPS Bindings
HTTP_PORT=80
HTTPS_PORT=443
HTTP_BIND=0.0.0.0
HTTPS_BIND=0.0.0.0

# Database
DBNAME=mailcow
DBUSER=mailcow
DBPASS=$(openssl rand -base64 32)
DBROOT=$(openssl rand -base64 32)

# Redis
REDIS_PORT=7654

# Timezone
TZ=$TIMEZONE

# Additional IPs to bind
ADDITIONAL_SAN=

# Skip running ACME (Let's Encrypt) - set to y to obtain certificates
SKIP_LETS_ENCRYPT=n

# Create HTTPS redirect
SKIP_HTTP_VERIFICATION=n

# Skip IPv4 check in ACME container
SKIP_IP_CHECK=n

# Skip Clamd (saves RAM)
SKIP_CLAMD=n

# Skip Solr (saves RAM, disables FTS)
SKIP_SOLR=n

# Enable watchdog
USE_WATCHDOG=y

# Watchdog settings
WATCHDOG_NOTIFY_EMAIL=$ADMIN_EMAIL

# Compose project name
COMPOSE_PROJECT_NAME=mailcowdockerized

# Docker-Compose version
DOCKER_COMPOSE_VERSION=v2

# Default language
MAILCOW_API_KEY=$(openssl rand -base64 32)

# Backup location
BACKUP_LOCATION=/var/backups/mailcow

# Log rotation
LOG_LINES=9999

# Additional domains
ADDITIONAL_SAN=

# Enable Fail2ban
ENABLE_FAIL2BAN=y
EOF
    fi
    
    # Set proper permissions
    chmod 600 mailcow.conf
    
    info "Configuration generated successfully"
}

# Pull and start containers
start_mailcow() {
    log "Starting Mailcow containers..."
    
    cd "$MAILCOW_DIR"
    
    # Pull images
    docker-compose pull
    
    # Start containers
    docker-compose up -d
    
    # Wait for containers to be ready
    log "Waiting for containers to start..."
    sleep 30
    
    # Check container status
    if docker-compose ps | grep -q "Exit"; then
        error "Some containers failed to start. Check logs with: docker-compose logs"
    fi
    
    info "Mailcow started successfully"
}

# Generate SSL certificates
setup_ssl() {
    log "Setting up SSL certificates..."
    
    cd "$MAILCOW_DIR"
    
    # Let Mailcow generate certificates automatically
    info "SSL certificates will be generated automatically by ACME"
    info "Ensure your domain $DOMAIN points to this server's IP address"
    
    # Wait a bit for ACME to work
    sleep 60
    
    # Check if certificates were generated
    if docker-compose exec acme-mailcow ls -la /etc/ssl/mail/ | grep -q "$DOMAIN"; then
        info "SSL certificates generated successfully"
    else
        warning "SSL certificate generation may still be in progress. Check logs if needed."
    fi
}

# Create initial admin account
create_admin() {
    log "Creating admin account..."
    
    cd "$MAILCOW_DIR"
    
    # Wait for web container to be ready
    sleep 30
    
    # Generate admin password
    ADMIN_PASS=$(openssl rand -base64 16)
    
    # Create admin via API (this will be handled by configure script)
    info "Admin account will be created during configuration phase"
    
    # Save credentials securely
    cat > "$CONFIG_DIR/admin_credentials" << EOF
ADMIN_EMAIL=$ADMIN_EMAIL
ADMIN_PASS=$ADMIN_PASS
DOMAIN=$DOMAIN
EOF
    
    chmod 600 "$CONFIG_DIR/admin_credentials"
    
    info "Admin credentials saved to $CONFIG_DIR/admin_credentials"
}

# Main installation function
main() {
    log "Starting Mailcow installation..."
    
    # Parse arguments
    DOMAIN="$1"
    ADMIN_EMAIL="$2"
    TIMEZONE="$3"
    
    check_root
    validate_params
    check_requirements
    install_dependencies
    configure_firewall
    download_mailcow
    generate_config
    start_mailcow
    setup_ssl
    create_admin
    
    log "Mailcow installation completed successfully!"
    info "Access your mail server at: https://$DOMAIN"
    info "Admin credentials are saved in: $CONFIG_DIR/admin_credentials"
    info "Run the configuration script next: ./configure-mailcow.sh"
    
    # Show next steps
    cat << EOF

${GREEN}Installation Complete!${NC}

Next Steps:
1. Ensure your domain $DOMAIN points to this server
2. Run the configuration script: ./configure-mailcow.sh
3. Access the web interface at: https://$DOMAIN
4. Check container status: docker-compose ps
5. View logs: docker-compose logs

Important files:
- Configuration: $MAILCOW_DIR/mailcow.conf
- Admin credentials: $CONFIG_DIR/admin_credentials
- Installation log: $LOG_FILE

EOF
}

# Run main function
main "$@"