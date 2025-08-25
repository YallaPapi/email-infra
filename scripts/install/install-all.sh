#!/bin/bash
#
# Master Installation Script for Cold Email Infrastructure
# Orchestrates the complete installation of all components
#

set -e  # Exit on any error

# Source environment setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../utilities/setup-environment.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$EMAIL_INFRA_LOGS/install.log"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$EMAIL_INFRA_LOGS/install.log"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$EMAIL_INFRA_LOGS/install.log"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$EMAIL_INFRA_LOGS/install.log"
}

# Show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -e, --environment ENV    Target environment (development|staging|production)"
    echo "  -d, --domain DOMAIN      Primary domain for the infrastructure"
    echo "  -i, --ip IP             Server IP address"
    echo "  --skip-deps             Skip dependency installation"
    echo "  --skip-vps              Skip VPS setup"
    echo "  --skip-dns              Skip DNS setup"
    echo "  --skip-mailcow          Skip Mailcow installation"
    echo "  --skip-monitoring       Skip monitoring setup"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "Example:"
    echo "  $0 -e production -d mail.example.com -i 192.168.1.100"
}

# Parse command line arguments
ENVIRONMENT="development"
DOMAIN=""
SERVER_IP=""
SKIP_DEPS=false
SKIP_VPS=false
SKIP_DNS=false
SKIP_MAILCOW=false
SKIP_MONITORING=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -d|--domain)
            DOMAIN="$2"
            shift 2
            ;;
        -i|--ip)
            SERVER_IP="$2"
            shift 2
            ;;
        --skip-deps)
            SKIP_DEPS=true
            shift
            ;;
        --skip-vps)
            SKIP_VPS=true
            shift
            ;;
        --skip-dns)
            SKIP_DNS=true
            shift
            ;;
        --skip-mailcow)
            SKIP_MAILCOW=true
            shift
            ;;
        --skip-monitoring)
            SKIP_MONITORING=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$DOMAIN" ]]; then
    error "Domain is required. Use -d or --domain to specify."
    show_usage
    exit 1
fi

if [[ -z "$SERVER_IP" ]]; then
    error "Server IP is required. Use -i or --ip to specify."
    show_usage
    exit 1
fi

# Set environment
export EMAIL_INFRA_ENV="$ENVIRONMENT"

# Installation header
echo "========================================="
echo "Cold Email Infrastructure Installation"
echo "========================================="
echo "Environment: $ENVIRONMENT"
echo "Domain: $DOMAIN"
echo "Server IP: $SERVER_IP"
echo "Installation Log: $EMAIL_INFRA_LOGS/install.log"
echo "========================================="

# Create log directory
mkdir -p "$EMAIL_INFRA_LOGS"

# Start installation
log "Starting Cold Email Infrastructure installation"
log "Environment: $ENVIRONMENT, Domain: $DOMAIN, IP: $SERVER_IP"

# Phase 1: Dependencies
if [[ "$SKIP_DEPS" == false ]]; then
    log "Phase 1: Installing dependencies"
    if [[ -x "$EMAIL_INFRA_SCRIPTS/install/install-dependencies.sh" ]]; then
        "$EMAIL_INFRA_SCRIPTS/install/install-dependencies.sh" || {
            error "Failed to install dependencies"
            exit 1
        }
    else
        warn "Dependencies installation script not found, skipping"
    fi
else
    log "Phase 1: Skipping dependencies installation"
fi

# Phase 2: VPS Setup
if [[ "$SKIP_VPS" == false ]]; then
    log "Phase 2: Setting up VPS environment"
    if [[ -x "$VPS_SCRIPTS/setup-vps.sh" ]]; then
        "$VPS_SCRIPTS/setup-vps.sh" --ip "$SERVER_IP" || {
            error "Failed to setup VPS"
            exit 1
        }
    else
        error "VPS setup script not found at $VPS_SCRIPTS/setup-vps.sh"
        exit 1
    fi
else
    log "Phase 2: Skipping VPS setup"
fi

# Phase 3: DNS Setup
if [[ "$SKIP_DNS" == false ]]; then
    log "Phase 3: Setting up DNS configuration"
    if [[ -x "$DNS_SCRIPTS/record-generator.sh" ]]; then
        "$DNS_SCRIPTS/record-generator.sh" --domain "$DOMAIN" --ip "$SERVER_IP" --deploy || {
            error "Failed to setup DNS"
            exit 1
        }
    else
        error "DNS setup script not found at $DNS_SCRIPTS/record-generator.sh"
        exit 1
    fi
else
    log "Phase 3: Skipping DNS setup"
fi

# Phase 4: Mailcow Installation
if [[ "$SKIP_MAILCOW" == false ]]; then
    log "Phase 4: Installing and configuring Mailcow"
    if [[ -x "$MAILCOW_AUTOMATION/install-mailcow.sh" ]]; then
        "$MAILCOW_AUTOMATION/install-mailcow.sh" "$DOMAIN" "admin@$DOMAIN" || {
            error "Failed to install Mailcow"
            exit 1
        }
    else
        error "Mailcow installation script not found at $MAILCOW_AUTOMATION/install-mailcow.sh"
        exit 1
    fi
    
    # Configure Mailcow
    if [[ -x "$MAILCOW_AUTOMATION/configure-mailcow.sh" ]]; then
        "$MAILCOW_AUTOMATION/configure-mailcow.sh" || {
            error "Failed to configure Mailcow"
            exit 1
        }
    fi
else
    log "Phase 4: Skipping Mailcow installation"
fi

# Phase 5: Monitoring Setup
if [[ "$SKIP_MONITORING" == false ]]; then
    log "Phase 5: Setting up monitoring and alerting"
    if [[ -x "$MONITORING_SCRIPTS/health-check-all.sh" ]]; then
        # Setup monitoring configuration first
        python3 -c "
from email_infrastructure.monitoring.core.monitor_engine import MonitorEngine
from email_infrastructure.core.config_manager import config_manager
monitor = MonitorEngine(config_manager.get_monitoring_config())
monitor.setup_monitoring_for_domain('$DOMAIN', '$SERVER_IP')
" || {
            error "Failed to setup monitoring"
            exit 1
        }
    else
        warn "Monitoring setup scripts not found, skipping"
    fi
else
    log "Phase 5: Skipping monitoring setup"
fi

# Phase 6: Post-Installation Setup
log "Phase 6: Running post-installation setup"
if [[ -x "$EMAIL_INFRA_SCRIPTS/install/post-install-setup.sh" ]]; then
    "$EMAIL_INFRA_SCRIPTS/install/post-install-setup.sh" "$DOMAIN" "$SERVER_IP" || {
        error "Failed post-installation setup"
        exit 1
    }
else
    warn "Post-installation setup script not found"
fi

# Phase 7: Validation
log "Phase 7: Validating installation"
if [[ -x "$EMAIL_INFRA_SCRIPTS/utilities/validate-setup.sh" ]]; then
    "$EMAIL_INFRA_SCRIPTS/utilities/validate-setup.sh" "$DOMAIN" "$SERVER_IP" || {
        warn "Installation validation reported issues - check logs"
    }
else
    warn "Validation script not found"
fi

# Installation complete
log "=== INSTALLATION COMPLETE ==="
log "Cold Email Infrastructure has been successfully installed"
log "Environment: $ENVIRONMENT"
log "Domain: $DOMAIN"
log "Server IP: $SERVER_IP"
log "Installation log: $EMAIL_INFRA_LOGS/install.log"

echo ""
echo "========================================="
echo -e "${GREEN}Installation Complete!${NC}"
echo "========================================="
echo "Next Steps:"
echo "1. Check installation log: $EMAIL_INFRA_LOGS/install.log"
echo "2. Verify DNS propagation for $DOMAIN"
echo "3. Test email sending/receiving"
echo "4. Review monitoring dashboard"
echo "5. Set up regular backups"
echo ""
echo "Useful Commands:"
echo "  ./scripts/utilities/validate-setup.sh $DOMAIN $SERVER_IP"
echo "  ./scripts/maintenance/health-check-all.sh"
echo "  ./scripts/maintenance/backup-all.sh"
echo "========================================="