#!/bin/bash

# Cold Email Dashboard Quick Start Script
# One-command deployment with comprehensive validation and setup

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="Cold Email Dashboard"
VERSION="1.0.0"
DEPLOY_MODE="${DEPLOY_MODE:-native}"  # native, docker, or minimal
DOMAIN="${DOMAIN:-dashboard.localhost}"
EMAIL="${EMAIL:-admin@localhost}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_debug() { echo -e "${PURPLE}[DEBUG]${NC} $1"; }
log_step() { echo -e "${CYAN}[STEP]${NC} $1"; }

# Progress tracking
TOTAL_STEPS=12
CURRENT_STEP=0

progress_step() {
    ((CURRENT_STEP++))
    echo -e "${CYAN}[${CURRENT_STEP}/${TOTAL_STEPS}]${NC} $1"
}

# Print banner
print_banner() {
    echo -e "${CYAN}"
    cat << 'EOF'
 ____      _     _   ____                 _ _   ____            _     _                         _ 
/ ___|___ | | __| | | ___| _ __ ___   __ _(_) | |  _ \  __ _ ___| |__ | |__   ___   __ _ _ __ __| |
| |   / _ \| |/ _` | |___ \| '_ ` _ \ / _` | | | | | | |/ _` / __| '_ \| '_ \ / _ \ / _` | '__/ _` |
| |__| (_) | | (_| |  ___) | | | | | | (_| | | | | |_| | (_| \__ \ | | | |_) | (_) | (_| | | | (_| |
 \____\___/|_|\__,_| |____/|_| |_| |_|\__,_|_|_| |____/ \__,_|___/_| |_|_.__/ \___/ \__,_|_|  \__,_|
                                                                                                    
EOF
    echo -e "${NC}"
    echo -e "${GREEN}$PROJECT_NAME v$VERSION - Quick Start Script${NC}"
    echo -e "${BLUE}Automated deployment and validation for your email infrastructure dashboard${NC}"
    echo ""
}

# Show help
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

OPTIONS:
    -m, --mode MODE         Deployment mode: native, docker, minimal (default: native)
    -d, --domain DOMAIN     Domain name (default: dashboard.localhost)
    -e, --email EMAIL       Administrator email (default: admin@localhost)
    -p, --port PORT         Dashboard port (default: 5000)
    -s, --ssl               Enable SSL/TLS setup
    -n, --nginx             Setup nginx reverse proxy
    -b, --backup            Setup automated backups
    -f, --full              Full deployment (SSL + nginx + backup)
    --docker-only           Docker deployment only
    --check-only            Only run validation checks
    --no-firewall           Skip firewall configuration
    --no-install            Skip package installation
    -h, --help              Show this help message

DEPLOYMENT MODES:
    native     - Full native deployment with systemd service
    docker     - Docker-based deployment with docker-compose
    minimal    - Minimal setup for development/testing

EXAMPLES:
    $0                                          # Basic native deployment
    $0 --mode docker --domain mail.example.com # Docker deployment
    $0 --full --domain dashboard.example.com   # Full production setup
    $0 --check-only                            # Only validate environment

ENVIRONMENT VARIABLES:
    DEPLOY_MODE         Deployment mode (native/docker/minimal)
    DOMAIN              Dashboard domain name
    EMAIL               Administrator email
    FLASK_PORT          Dashboard port (default: 5000)
    SKIP_FIREWALL       Skip firewall setup (yes/no)
    SKIP_PACKAGES       Skip package installation (yes/no)
    SSL_CERT_TYPE       SSL certificate type (letsencrypt/selfsigned)
EOF
}

# System validation
validate_system() {
    progress_step "Validating system requirements..."
    
    local errors=0
    local warnings=0
    
    # Check OS
    if [[ ! -f /etc/os-release ]]; then
        log_error "Unable to detect operating system"
        ((errors++))
    else
        source /etc/os-release
        if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
            log_warning "Untested operating system: $PRETTY_NAME"
            ((warnings++))
        else
            log_success "Operating system: $PRETTY_NAME"
        fi
    fi
    
    # Check architecture
    local arch=$(uname -m)
    if [[ "$arch" != "x86_64" ]]; then
        log_warning "Untested architecture: $arch"
        ((warnings++))
    else
        log_success "Architecture: $arch"
    fi
    
    # Check root privileges
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        ((errors++))
    else
        log_success "Running with root privileges"
    fi
    
    # Check available disk space
    local available_gb=$(df / --output=avail | tail -1 | awk '{print int($1/1024/1024)}')
    if [[ $available_gb -lt 2 ]]; then
        log_error "Insufficient disk space: ${available_gb}GB available, 2GB minimum required"
        ((errors++))
    else
        log_success "Disk space: ${available_gb}GB available"
    fi
    
    # Check available memory
    local mem_gb=$(free -g | awk '/^Mem:/{print $2}')
    if [[ $mem_gb -lt 1 ]]; then
        log_warning "Low memory: ${mem_gb}GB available, 1GB recommended"
        ((warnings++))
    else
        log_success "Memory: ${mem_gb}GB available"
    fi
    
    # Check network connectivity
    if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        log_error "No internet connectivity detected"
        ((errors++))
    else
        log_success "Internet connectivity available"
    fi
    
    # Check if ports are available
    local required_ports=(80 443 5000)
    for port in "${required_ports[@]}"; do
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            log_warning "Port $port is already in use"
            ((warnings++))
        else
            log_debug "Port $port is available"
        fi
    done
    
    echo ""
    if [[ $errors -gt 0 ]]; then
        log_error "System validation failed with $errors errors"
        return 1
    elif [[ $warnings -gt 0 ]]; then
        log_warning "System validation completed with $warnings warnings"
    else
        log_success "System validation passed"
    fi
    
    return 0
}

# Check dependencies
check_dependencies() {
    progress_step "Checking dependencies..."
    
    local missing_deps=()
    local optional_deps=()
    
    # Required for native deployment
    if [[ "$DEPLOY_MODE" == "native" ]]; then
        local required_packages=(curl wget git python3 python3-pip python3-venv systemctl)
        
        for package in "${required_packages[@]}"; do
            if ! command -v "$package" >/dev/null 2>&1; then
                missing_deps+=("$package")
            else
                log_debug "$package is available"
            fi
        done
    fi
    
    # Required for Docker deployment
    if [[ "$DEPLOY_MODE" == "docker" ]]; then
        if ! command -v docker >/dev/null 2>&1; then
            missing_deps+=("docker")
        else
            log_debug "Docker is available"
        fi
        
        if ! command -v docker-compose >/dev/null 2>&1 && ! docker compose version >/dev/null 2>&1; then
            missing_deps+=("docker-compose")
        else
            log_debug "Docker Compose is available"
        fi
    fi
    
    # Optional packages
    local optional_packages=(nginx certbot ufw fail2ban htop tree jq)
    for package in "${optional_packages[@]}"; do
        if ! command -v "$package" >/dev/null 2>&1; then
            optional_deps+=("$package")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_warning "Missing required dependencies: ${missing_deps[*]}"
        return 1
    fi
    
    if [[ ${#optional_deps[@]} -gt 0 ]]; then
        log_info "Missing optional dependencies: ${optional_deps[*]}"
    fi
    
    log_success "All required dependencies are available"
    return 0
}

# Install packages
install_packages() {
    if [[ "${SKIP_PACKAGES:-no}" == "yes" ]]; then
        log_info "Skipping package installation"
        return 0
    fi
    
    progress_step "Installing required packages..."
    
    # Update package list
    apt-get update -qq
    
    # Install basic packages
    local basic_packages=(curl wget git python3 python3-pip python3-venv build-essential)
    apt-get install -y "${basic_packages[@]}"
    
    # Install deployment-specific packages
    if [[ "$DEPLOY_MODE" == "docker" ]]; then
        # Install Docker
        if ! command -v docker >/dev/null 2>&1; then
            curl -fsSL https://get.docker.com | sh
            systemctl enable docker
            systemctl start docker
            log_success "Docker installed"
        fi
        
        # Install Docker Compose
        if ! command -v docker-compose >/dev/null 2>&1 && ! docker compose version >/dev/null 2>&1; then
            curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
                -o /usr/local/bin/docker-compose
            chmod +x /usr/local/bin/docker-compose
            log_success "Docker Compose installed"
        fi
    fi
    
    # Install optional packages
    local optional_packages=(nginx certbot python3-certbot-nginx ufw fail2ban logrotate htop tree jq)
    apt-get install -y "${optional_packages[@]}" || log_warning "Some optional packages could not be installed"
    
    log_success "Package installation completed"
}

# Validate configuration
validate_configuration() {
    progress_step "Validating configuration..."
    
    # Check domain
    if [[ "$DOMAIN" == "dashboard.localhost" ]]; then
        log_warning "Using default domain: $DOMAIN"
        log_warning "This will only work for local testing"
    else
        log_info "Domain: $DOMAIN"
        
        # Check if domain resolves
        if dig +short "$DOMAIN" >/dev/null 2>&1; then
            log_success "Domain resolves correctly"
        else
            log_warning "Domain does not resolve - DNS may need configuration"
        fi
    fi
    
    # Check email
    if [[ "$EMAIL" == "admin@localhost" ]]; then
        log_warning "Using default email: $EMAIL"
    else
        log_info "Administrator email: $EMAIL"
    fi
    
    # Validate configuration files exist
    if [[ -f "$SCRIPT_DIR/app.py" ]]; then
        log_success "Dashboard application found"
    else
        log_error "Dashboard application not found at $SCRIPT_DIR/app.py"
        return 1
    fi
    
    if [[ -f "$SCRIPT_DIR/requirements.txt" ]]; then
        log_success "Requirements file found"
    else
        log_error "Requirements file not found at $SCRIPT_DIR/requirements.txt"
        return 1
    fi
    
    return 0
}

# Deploy based on mode
deploy_application() {
    case "$DEPLOY_MODE" in
        native)
            deploy_native
            ;;
        docker)
            deploy_docker
            ;;
        minimal)
            deploy_minimal
            ;;
        *)
            log_error "Unknown deployment mode: $DEPLOY_MODE"
            return 1
            ;;
    esac
}

# Native deployment
deploy_native() {
    progress_step "Deploying with native mode..."
    
    local deploy_script="$SCRIPT_DIR/deploy.sh"
    
    if [[ -f "$deploy_script" ]]; then
        log_info "Running full deployment script..."
        "$deploy_script" deploy
        log_success "Native deployment completed"
    else
        log_error "Deployment script not found: $deploy_script"
        return 1
    fi
}

# Docker deployment
deploy_docker() {
    progress_step "Deploying with Docker mode..."
    
    local docker_script="$SCRIPT_DIR/docker-start.sh"
    
    if [[ -f "$docker_script" ]]; then
        log_info "Running Docker deployment script..."
        "$docker_script" start
        log_success "Docker deployment completed"
    else
        log_error "Docker script not found: $docker_script"
        return 1
    fi
}

# Minimal deployment
deploy_minimal() {
    progress_step "Deploying with minimal mode..."
    
    log_info "Setting up minimal development environment..."
    
    # Create virtual environment
    if [[ ! -d "$SCRIPT_DIR/venv" ]]; then
        python3 -m venv "$SCRIPT_DIR/venv"
        log_success "Virtual environment created"
    fi
    
    # Install dependencies
    "$SCRIPT_DIR/venv/bin/pip" install --upgrade pip
    "$SCRIPT_DIR/venv/bin/pip" install -r "$SCRIPT_DIR/requirements.txt"
    log_success "Dependencies installed"
    
    # Create minimal configuration
    if [[ ! -f "$SCRIPT_DIR/.env" ]]; then
        cat > "$SCRIPT_DIR/.env" << EOF
FLASK_ENV=development
FLASK_PORT=5000
FLASK_SECRET_KEY=dev-secret-key
API_KEY=dev-api-key
DOMAIN=$DOMAIN
EMAIL=$EMAIL
EOF
        log_success "Development configuration created"
    fi
    
    log_success "Minimal deployment completed"
    log_info "To start the dashboard run: cd $SCRIPT_DIR && ./venv/bin/python app.py"
}

# Configure firewall
configure_firewall() {
    if [[ "${SKIP_FIREWALL:-no}" == "yes" ]]; then
        log_info "Skipping firewall configuration"
        return 0
    fi
    
    progress_step "Configuring firewall..."
    
    if command -v ufw >/dev/null 2>&1; then
        # Enable UFW
        ufw --force enable
        
        # Allow SSH
        ufw allow ssh
        
        # Allow HTTP and HTTPS
        ufw allow 80/tcp
        ufw allow 443/tcp
        
        # Allow dashboard port
        ufw allow 5000/tcp
        
        log_success "Firewall configured"
    else
        log_warning "UFW not available, skipping firewall configuration"
    fi
}

# Setup SSL (optional)
setup_ssl() {
    local ssl_script="$SCRIPT_DIR/ssl/setup-ssl.sh"
    
    if [[ -f "$ssl_script" ]]; then
        progress_step "Setting up SSL/TLS..."
        
        local cert_type="${SSL_CERT_TYPE:-letsencrypt}"
        "$ssl_script" "$DOMAIN" "$EMAIL" "$cert_type"
        log_success "SSL/TLS setup completed"
    else
        log_warning "SSL setup script not found, skipping SSL configuration"
    fi
}

# Setup nginx (optional)
setup_nginx() {
    local nginx_script="$SCRIPT_DIR/nginx/setup-nginx.sh"
    
    if [[ -f "$nginx_script" ]]; then
        progress_step "Setting up nginx reverse proxy..."
        
        "$nginx_script" "$DOMAIN" "$EMAIL"
        log_success "Nginx setup completed"
    else
        log_warning "Nginx setup script not found, skipping nginx configuration"
    fi
}

# Setup backups (optional)
setup_backups() {
    local backup_script="$SCRIPT_DIR/scripts/backup.sh"
    
    if [[ -f "$backup_script" ]]; then
        progress_step "Setting up automated backups..."
        
        # Test backup functionality
        "$backup_script" test
        
        # Create cron job for daily backups
        cat > /etc/cron.d/dashboard-backup << EOF
# Dashboard automated backup
0 2 * * * root $backup_script full
EOF
        
        chmod 644 /etc/cron.d/dashboard-backup
        log_success "Automated backups configured"
    else
        log_warning "Backup script not found, skipping backup configuration"
    fi
}

# Test deployment
test_deployment() {
    progress_step "Testing deployment..."
    
    local max_attempts=30
    local attempt=0
    
    log_info "Waiting for dashboard to be ready..."
    
    while [[ $attempt -lt $max_attempts ]]; do
        if curl -s -f http://localhost:5000/api/health >/dev/null 2>&1; then
            log_success "Dashboard is responding"
            break
        fi
        
        ((attempt++))
        log_debug "Attempt $attempt/$max_attempts..."
        sleep 2
    done
    
    if [[ $attempt -eq $max_attempts ]]; then
        log_error "Dashboard is not responding after $max_attempts attempts"
        return 1
    fi
    
    # Run additional tests
    local response_code
    response_code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:5000/api/health)
    
    if [[ "$response_code" == "200" ]]; then
        log_success "Health check endpoint responding correctly"
    else
        log_warning "Health check returned status code: $response_code"
    fi
    
    # Test main dashboard page
    if curl -s -f http://localhost:5000/ >/dev/null 2>&1; then
        log_success "Main dashboard page is accessible"
    else
        log_warning "Main dashboard page may not be accessible"
    fi
    
    return 0
}

# Generate access information
generate_access_info() {
    progress_step "Generating access information..."
    
    local public_ip
    public_ip=$(curl -s https://api.ipify.org 2>/dev/null || echo "Unable to detect")
    
    log_success "Deployment completed successfully!"
    
    echo ""
    echo "========================================================================================"
    echo -e "${GREEN}                            DEPLOYMENT COMPLETE                                    ${NC}"
    echo "========================================================================================"
    echo ""
    echo -e "${CYAN}Access Information:${NC}"
    echo "  Dashboard URL (local):    http://localhost:5000"
    
    if [[ "$DOMAIN" != "dashboard.localhost" ]]; then
        echo "  Dashboard URL (domain):   http://$DOMAIN"
        if [[ -f "/etc/ssl/dashboard/dashboard.crt" ]]; then
            echo "  Dashboard URL (HTTPS):    https://$DOMAIN"
        fi
    fi
    
    if [[ "$public_ip" != "Unable to detect" ]]; then
        echo "  Dashboard URL (IP):       http://$public_ip:5000"
    fi
    
    echo "  Health Check:             http://localhost:5000/api/health"
    echo ""
    echo -e "${CYAN}System Information:${NC}"
    echo "  Deployment Mode:          $DEPLOY_MODE"
    echo "  Domain:                   $DOMAIN"
    echo "  Administrator Email:      $EMAIL"
    echo "  Public IP:                $public_ip"
    echo ""
    echo -e "${CYAN}Service Management:${NC}"
    
    if [[ "$DEPLOY_MODE" == "native" ]]; then
        echo "  Start Service:            systemctl start cold-email-dashboard"
        echo "  Stop Service:             systemctl stop cold-email-dashboard"
        echo "  Restart Service:          systemctl restart cold-email-dashboard"
        echo "  Service Status:           systemctl status cold-email-dashboard"
        echo "  View Logs:                journalctl -u cold-email-dashboard -f"
    elif [[ "$DEPLOY_MODE" == "docker" ]]; then
        echo "  Start Services:           cd $SCRIPT_DIR && ./docker-start.sh start"
        echo "  Stop Services:            cd $SCRIPT_DIR && ./docker-start.sh stop"
        echo "  View Logs:                cd $SCRIPT_DIR && docker-compose logs -f"
    elif [[ "$DEPLOY_MODE" == "minimal" ]]; then
        echo "  Start Dashboard:          cd $SCRIPT_DIR && ./venv/bin/python app.py"
        echo "  Environment:              cd $SCRIPT_DIR && source venv/bin/activate"
    fi
    
    echo ""
    echo -e "${CYAN}Important Files:${NC}"
    
    if [[ "$DEPLOY_MODE" == "native" ]]; then
        echo "  Configuration:            /etc/cold-email-dashboard/dashboard.env"
        echo "  Application:              /opt/cold-email-dashboard/dashboard/"
        echo "  Logs:                     /var/log/cold-email-dashboard/"
        echo "  Backups:                  /opt/cold-email-dashboard/backups/"
    elif [[ "$DEPLOY_MODE" == "docker" ]]; then
        echo "  Configuration:            $SCRIPT_DIR/.env"
        echo "  Docker Compose:           $SCRIPT_DIR/docker-compose.yml"
    elif [[ "$DEPLOY_MODE" == "minimal" ]]; then
        echo "  Configuration:            $SCRIPT_DIR/.env"
        echo "  Virtual Environment:      $SCRIPT_DIR/venv/"
    fi
    
    echo ""
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "  1. Visit the dashboard URL to verify it's working"
    echo "  2. Configure your email settings in the configuration file"
    echo "  3. Set up your domain DNS records if using a custom domain"
    echo "  4. Configure SSL certificates for production use"
    echo "  5. Review and update security settings"
    echo ""
    echo -e "${YELLOW}Need Help?${NC}"
    echo "  Check the logs if something isn't working"
    echo "  Verify firewall settings allow access to required ports"
    echo "  Ensure DNS is configured if using a custom domain"
    echo ""
    echo "========================================================================================"
}

# Cleanup on error
cleanup_on_error() {
    log_error "Quick start failed. Performing cleanup..."
    
    # Stop services if they were started
    if [[ "$DEPLOY_MODE" == "native" ]]; then
        systemctl stop cold-email-dashboard 2>/dev/null || true
    elif [[ "$DEPLOY_MODE" == "docker" ]]; then
        cd "$SCRIPT_DIR" && docker-compose down 2>/dev/null || true
    fi
    
    log_info "Cleanup completed. Check the logs above for error details."
}

# Main function
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -m|--mode)
                DEPLOY_MODE="$2"
                shift 2
                ;;
            -d|--domain)
                DOMAIN="$2"
                shift 2
                ;;
            -e|--email)
                EMAIL="$2"
                shift 2
                ;;
            -p|--port)
                export FLASK_PORT="$2"
                shift 2
                ;;
            -s|--ssl)
                SETUP_SSL=true
                shift
                ;;
            -n|--nginx)
                SETUP_NGINX=true
                shift
                ;;
            -b|--backup)
                SETUP_BACKUP=true
                shift
                ;;
            -f|--full)
                SETUP_SSL=true
                SETUP_NGINX=true
                SETUP_BACKUP=true
                shift
                ;;
            --docker-only)
                DEPLOY_MODE="docker"
                shift
                ;;
            --check-only)
                CHECK_ONLY=true
                shift
                ;;
            --no-firewall)
                export SKIP_FIREWALL=yes
                shift
                ;;
            --no-install)
                export SKIP_PACKAGES=yes
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Print banner
    print_banner
    
    # Set up error handling
    trap cleanup_on_error ERR
    
    # Validation phase
    log_step "Starting system validation..."
    validate_system || exit 1
    
    check_dependencies || {
        if [[ "${SKIP_PACKAGES:-no}" == "no" ]]; then
            log_info "Missing dependencies will be installed"
        else
            exit 1
        fi
    }
    
    validate_configuration || exit 1
    
    # If check-only mode, exit here
    if [[ "${CHECK_ONLY:-false}" == true ]]; then
        log_success "Validation checks completed successfully!"
        exit 0
    fi
    
    # Installation phase
    log_step "Starting installation phase..."
    install_packages
    configure_firewall
    
    # Deployment phase
    log_step "Starting deployment phase..."
    deploy_application || exit 1
    
    # Optional components
    if [[ "${SETUP_SSL:-false}" == true ]]; then
        setup_ssl
    fi
    
    if [[ "${SETUP_NGINX:-false}" == true ]]; then
        setup_nginx
    fi
    
    if [[ "${SETUP_BACKUP:-false}" == true ]]; then
        setup_backups
    fi
    
    # Testing phase
    test_deployment || {
        log_warning "Deployment test failed, but continuing..."
    }
    
    # Generate final information
    generate_access_info
    
    log_success "Quick start completed successfully!"
}

# Run main function with all arguments
main "$@"