#!/bin/bash

# VPS Setup Script for Cold Email Infrastructure
# Supports Ubuntu 22.04 LTS and Debian 12
# Author: Cold Email Infrastructure Setup Agent
# Version: 1.0.0

set -euo pipefail

# =============================================================================
# CONFIGURATION AND CONSTANTS
# =============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BASE_DIR="$(dirname "$SCRIPT_DIR")"
readonly CONFIG_DIR="$BASE_DIR/config"
readonly LOG_DIR="$BASE_DIR/logs"
readonly MONITORING_DIR="$BASE_DIR/monitoring"

readonly LOG_FILE="$LOG_DIR/vps-setup-$(date +%Y%m%d_%H%M%S).log"
readonly NETWORK_CONFIG_FILE="$CONFIG_DIR/network-config.yaml"
readonly FIREWALL_RULES_FILE="$CONFIG_DIR/firewall-rules.json"

# Mail server ports that need to be opened
readonly MAIL_PORTS=(25 587 465 143 993 110 995 80 443)

# Required packages for the mail infrastructure
readonly REQUIRED_PACKAGES=(
    "docker.io"
    "docker-compose"
    "git"
    "curl"
    "wget"
    "ufw"
    "net-tools"
    "ifupdown"
    "resolvconf"
    "dnsutils"
    "fail2ban"
    "logrotate"
    "cron"
    "python3"
    "python3-pip"
    "python3-yaml"
    "python3-requests"
    "jq"
    "htop"
    "iotop"
    "iftop"
    "tcpdump"
    "nmap"
)

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() {
    log "INFO" "$@"
}

log_warn() {
    log "WARN" "$@"
}

log_error() {
    log "ERROR" "$@"
}

log_success() {
    log "SUCCESS" "$@"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root. Use sudo."
        exit 1
    fi
}

create_directories() {
    log_info "Creating required directories..."
    mkdir -p "$LOG_DIR" "$MONITORING_DIR"
    chmod 755 "$LOG_DIR" "$MONITORING_DIR"
}

detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$NAME
        VERSION=$VERSION_ID
        log_info "Detected OS: $OS $VERSION"
        
        case "$OS" in
            "Ubuntu")
                if [[ "$VERSION" != "22.04" ]]; then
                    log_warn "Ubuntu version $VERSION detected. This script is optimized for 22.04 LTS."
                fi
                PACKAGE_MANAGER="apt"
                ;;
            "Debian GNU/Linux")
                if [[ "$VERSION" != "12" ]]; then
                    log_warn "Debian version $VERSION detected. This script is optimized for Debian 12."
                fi
                PACKAGE_MANAGER="apt"
                ;;
            *)
                log_error "Unsupported OS: $OS. This script supports Ubuntu 22.04 LTS and Debian 12."
                exit 1
                ;;
        esac
    else
        log_error "Cannot detect OS. /etc/os-release not found."
        exit 1
    fi
}

# =============================================================================
# SYSTEM UPDATE AND PACKAGE INSTALLATION
# =============================================================================

update_system() {
    log_info "Updating system packages..."
    
    case "$PACKAGE_MANAGER" in
        "apt")
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -y || {
                log_error "Failed to update package lists"
                return 1
            }
            apt-get upgrade -y || {
                log_error "Failed to upgrade packages"
                return 1
            }
            apt-get autoremove -y || log_warn "Failed to autoremove packages"
            apt-get autoclean -y || log_warn "Failed to clean package cache"
            ;;
        *)
            log_error "Unsupported package manager: $PACKAGE_MANAGER"
            return 1
            ;;
    esac
    
    log_success "System updated successfully"
}

install_packages() {
    log_info "Installing required packages..."
    
    local failed_packages=()
    
    for package in "${REQUIRED_PACKAGES[@]}"; do
        log_info "Installing $package..."
        
        case "$PACKAGE_MANAGER" in
            "apt")
                if ! apt-get install -y "$package"; then
                    log_warn "Failed to install $package"
                    failed_packages+=("$package")
                fi
                ;;
        esac
    done
    
    if [[ ${#failed_packages[@]} -gt 0 ]]; then
        log_warn "Failed to install packages: ${failed_packages[*]}"
        log_info "You may need to install these manually or check repositories"
    else
        log_success "All required packages installed successfully"
    fi
}

configure_docker() {
    log_info "Configuring Docker..."
    
    # Start and enable Docker
    systemctl start docker || {
        log_error "Failed to start Docker"
        return 1
    }
    
    systemctl enable docker || {
        log_error "Failed to enable Docker"
        return 1
    }
    
    # Add current user to docker group if not root
    if [[ -n "${SUDO_USER:-}" ]]; then
        usermod -aG docker "$SUDO_USER" || log_warn "Failed to add user to docker group"
    fi
    
    # Test Docker installation
    if docker --version && docker-compose --version; then
        log_success "Docker configured successfully"
    else
        log_error "Docker installation verification failed"
        return 1
    fi
}

# =============================================================================
# NETWORK CONFIGURATION
# =============================================================================

backup_network_config() {
    log_info "Backing up current network configuration..."
    
    local backup_dir="/etc/network/backup-$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    # Backup network interfaces
    if [[ -f /etc/network/interfaces ]]; then
        cp /etc/network/interfaces "$backup_dir/" || log_warn "Failed to backup /etc/network/interfaces"
    fi
    
    # Backup netplan configs (Ubuntu)
    if [[ -d /etc/netplan ]]; then
        cp -r /etc/netplan "$backup_dir/" || log_warn "Failed to backup netplan configs"
    fi
    
    # Backup systemd network configs
    if [[ -d /etc/systemd/network ]]; then
        cp -r /etc/systemd/network "$backup_dir/" || log_warn "Failed to backup systemd network configs"
    fi
    
    log_success "Network configuration backed up to $backup_dir"
}

detect_network_interfaces() {
    log_info "Detecting network interfaces..."
    
    # Get primary network interface
    PRIMARY_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)
    
    if [[ -z "$PRIMARY_INTERFACE" ]]; then
        log_error "Could not detect primary network interface"
        return 1
    fi
    
    log_info "Primary network interface: $PRIMARY_INTERFACE"
    
    # Get current IP and gateway
    PRIMARY_IP=$(ip addr show "$PRIMARY_INTERFACE" | grep "inet " | awk '{print $2}' | cut -d/ -f1)
    GATEWAY=$(ip route | grep default | awk '{print $3}' | head -1)
    NETMASK=$(ip addr show "$PRIMARY_INTERFACE" | grep "inet " | awk '{print $2}' | cut -d/ -f2)
    
    log_info "Current IP: $PRIMARY_IP/$NETMASK"
    log_info "Gateway: $GATEWAY"
}

configure_multiple_ips() {
    log_info "Configuring multiple IP addresses..."
    
    if [[ ! -f "$NETWORK_CONFIG_FILE" ]]; then
        log_warn "Network config file not found: $NETWORK_CONFIG_FILE"
        log_info "Creating sample network configuration..."
        create_sample_network_config
        return 0
    fi
    
    # Parse YAML config file (requires python3-yaml)
    python3 << 'EOF'
import yaml
import sys
import os

config_file = os.environ.get('NETWORK_CONFIG_FILE')
primary_interface = os.environ.get('PRIMARY_INTERFACE')

try:
    with open(config_file, 'r') as f:
        config = yaml.safe_load(f)
    
    additional_ips = config.get('additional_ips', [])
    
    if not additional_ips:
        print("No additional IPs configured")
        sys.exit(0)
    
    # Generate interface aliases
    for i, ip_config in enumerate(additional_ips, 1):
        ip = ip_config.get('ip')
        netmask = ip_config.get('netmask', '24')
        
        if not ip:
            continue
            
        alias_interface = f"{primary_interface}:{i}"
        print(f"auto {alias_interface}")
        print(f"iface {alias_interface} inet static")
        print(f"address {ip}")
        print(f"netmask {netmask}")
        print("")
        
except Exception as e:
    print(f"Error parsing network config: {e}")
    sys.exit(1)
EOF
    
    log_success "Multiple IP configuration completed"
}

# =============================================================================
# FIREWALL CONFIGURATION
# =============================================================================

configure_firewall() {
    log_info "Configuring UFW firewall..."
    
    # Reset UFW to defaults
    ufw --force reset || {
        log_error "Failed to reset UFW"
        return 1
    }
    
    # Set default policies
    ufw default deny incoming || log_error "Failed to set default deny incoming"
    ufw default allow outgoing || log_error "Failed to set default allow outgoing"
    
    # Allow SSH (important - don't lock ourselves out)
    ufw allow ssh || log_error "Failed to allow SSH"
    ufw allow 22/tcp || log_error "Failed to allow port 22"
    
    # Allow mail server ports
    for port in "${MAIL_PORTS[@]}"; do
        log_info "Opening port $port..."
        ufw allow "$port" || log_warn "Failed to open port $port"
    done
    
    # Load additional firewall rules from JSON config
    if [[ -f "$FIREWALL_RULES_FILE" ]]; then
        log_info "Loading additional firewall rules from config..."
        load_firewall_rules_from_config
    fi
    
    # Enable UFW
    ufw --force enable || {
        log_error "Failed to enable UFW"
        return 1
    }
    
    # Show status
    ufw status verbose | tee -a "$LOG_FILE"
    
    log_success "Firewall configured successfully"
}

load_firewall_rules_from_config() {
    python3 << 'EOF'
import json
import subprocess
import sys
import os

config_file = os.environ.get('FIREWALL_RULES_FILE')

try:
    with open(config_file, 'r') as f:
        config = json.load(f)
    
    # Process allow rules
    allow_rules = config.get('allow', [])
    for rule in allow_rules:
        port = rule.get('port')
        protocol = rule.get('protocol', 'tcp')
        source = rule.get('source', 'any')
        comment = rule.get('comment', '')
        
        if port:
            if source == 'any':
                cmd = ['ufw', 'allow', f"{port}/{protocol}"]
            else:
                cmd = ['ufw', 'allow', 'from', source, 'to', 'any', 'port', str(port)]
            
            try:
                subprocess.run(cmd, check=True, capture_output=True)
                print(f"Allowed: {port}/{protocol} from {source} - {comment}")
            except subprocess.CalledProcessError as e:
                print(f"Failed to allow {port}/{protocol}: {e}")
    
    # Process deny rules
    deny_rules = config.get('deny', [])
    for rule in deny_rules:
        port = rule.get('port')
        protocol = rule.get('protocol', 'tcp')
        source = rule.get('source', 'any')
        comment = rule.get('comment', '')
        
        if port:
            if source == 'any':
                cmd = ['ufw', 'deny', f"{port}/{protocol}"]
            else:
                cmd = ['ufw', 'deny', 'from', source, 'to', 'any', 'port', str(port)]
            
            try:
                subprocess.run(cmd, check=True, capture_output=True)
                print(f"Denied: {port}/{protocol} from {source} - {comment}")
            except subprocess.CalledProcessError as e:
                print(f"Failed to deny {port}/{protocol}: {e}")

except Exception as e:
    print(f"Error loading firewall rules: {e}")
    sys.exit(1)
EOF
}

# =============================================================================
# FAIL2BAN CONFIGURATION
# =============================================================================

configure_fail2ban() {
    log_info "Configuring Fail2Ban..."
    
    # Create jail.local with mail server protection
    cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
backend = auto

[sshd]
enabled = true
port = ssh
logpath = /var/log/auth.log
maxretry = 3

[postfix]
enabled = true
port = smtp,465,submission
logpath = /var/log/mail.log
maxretry = 5

[dovecot]
enabled = true
port = pop3,pop3s,imap,imaps
logpath = /var/log/mail.log
maxretry = 5

[postfix-sasl]
enabled = true
port = smtp,465,submission,imap3,imaps,pop3,pop3s
logpath = /var/log/mail.log
maxretry = 3
EOF

    # Start and enable fail2ban
    systemctl restart fail2ban || {
        log_error "Failed to restart Fail2Ban"
        return 1
    }
    
    systemctl enable fail2ban || {
        log_error "Failed to enable Fail2Ban"
        return 1
    }
    
    log_success "Fail2Ban configured successfully"
}

# =============================================================================
# MONITORING AND HEALTH CHECKS
# =============================================================================

setup_monitoring() {
    log_info "Setting up system monitoring..."
    
    # Create monitoring scripts directory
    mkdir -p "$MONITORING_DIR"
    
    # Create system health check script
    create_health_check_script
    
    # Setup log rotation
    setup_log_rotation
    
    # Create system info script
    create_system_info_script
    
    log_success "Monitoring setup completed"
}

create_health_check_script() {
    log_info "Creating VPS health check script..."
    
    # Copy the health check script to monitoring directory
    if [[ -f "$SCRIPT_DIR/health-check.sh" ]]; then
        cp "$SCRIPT_DIR/health-check.sh" "$MONITORING_DIR/"
        chmod +x "$MONITORING_DIR/health-check.sh"
        log_success "Health check script created at $MONITORING_DIR/health-check.sh"
    else
        log_warn "Health check script source not found, creating placeholder..."
        cat > "$MONITORING_DIR/health-check.sh" << 'EOF'
#!/bin/bash
echo "Health check script placeholder - please update with actual health-check.sh"
EOF
        chmod +x "$MONITORING_DIR/health-check.sh"
    fi
}

create_system_info_script() {
    log_info "Creating system info script..."
    
    # Copy the system info script to monitoring directory
    if [[ -f "$SCRIPT_DIR/system-info.sh" ]]; then
        cp "$SCRIPT_DIR/system-info.sh" "$MONITORING_DIR/"
        chmod +x "$MONITORING_DIR/system-info.sh"
        log_success "System info script created at $MONITORING_DIR/system-info.sh"
    else
        log_warn "System info script source not found, creating placeholder..."
        cat > "$MONITORING_DIR/system-info.sh" << 'EOF'
#!/bin/bash
echo "System info script placeholder - please update with actual system-info.sh"
EOF
        chmod +x "$MONITORING_DIR/system-info.sh"
    fi
}

setup_log_rotation() {
    log_info "Setting up log rotation..."
    
    cat > /etc/logrotate.d/cold-email-infrastructure << 'EOF'
/home/stuart/cold-email-infrastructure/claude-task-master/src/email-infrastructure/vps/logs/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 0644 root root
}
EOF

    log_success "Log rotation configured"
}

# =============================================================================
# SAMPLE CONFIGURATION FILES
# =============================================================================

create_sample_network_config() {
    log_info "Creating sample network configuration..."
    
    cat > "$NETWORK_CONFIG_FILE" << EOF
# Network Configuration for Cold Email Infrastructure
# Configure additional IP addresses for your VPS

# Primary interface configuration (auto-detected)
primary_interface: "$PRIMARY_INTERFACE"
primary_ip: "$PRIMARY_IP"
gateway: "$GATEWAY"
netmask: "$NETMASK"

# Additional IP addresses to configure
# Add your additional IPs here
additional_ips:
  - ip: "192.168.1.100"
    netmask: "24"
    comment: "Additional IP for email sending"
  - ip: "192.168.1.101"
    netmask: "24"
    comment: "Additional IP for email sending"

# DNS configuration
dns_servers:
  - "8.8.8.8"
  - "8.8.4.4"
  - "1.1.1.1"

# Network interface options
interface_options:
  mtu: 1500
  metric: 100
EOF

    log_success "Sample network configuration created at $NETWORK_CONFIG_FILE"
}

create_sample_firewall_config() {
    log_info "Creating sample firewall configuration..."
    
    cat > "$FIREWALL_RULES_FILE" << 'EOF'
{
  "allow": [
    {
      "port": 2222,
      "protocol": "tcp",
      "source": "any",
      "comment": "Alternative SSH port"
    },
    {
      "port": 8080,
      "protocol": "tcp",
      "source": "192.168.1.0/24",
      "comment": "Web interface for local network"
    }
  ],
  "deny": [
    {
      "port": 23,
      "protocol": "tcp",
      "source": "any",
      "comment": "Block Telnet"
    }
  ],
  "rate_limit": [
    {
      "port": 22,
      "protocol": "tcp",
      "limit": "6/min",
      "comment": "SSH rate limiting"
    }
  ]
}
EOF

    log_success "Sample firewall configuration created at $FIREWALL_RULES_FILE"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    log_info "Starting VPS setup for Cold Email Infrastructure..."
    log_info "Script version: 1.0.0"
    
    # Pre-flight checks
    check_root
    create_directories
    detect_os
    
    # System setup
    update_system || {
        log_error "Failed to update system"
        exit 1
    }
    
    install_packages || {
        log_error "Failed to install required packages"
        exit 1
    }
    
    configure_docker || {
        log_error "Failed to configure Docker"
        exit 1
    }
    
    # Network configuration
    backup_network_config
    detect_network_interfaces || {
        log_error "Failed to detect network interfaces"
        exit 1
    }
    
    # Create sample configurations if they don't exist
    [[ ! -f "$NETWORK_CONFIG_FILE" ]] && create_sample_network_config
    [[ ! -f "$FIREWALL_RULES_FILE" ]] && create_sample_firewall_config
    
    configure_multiple_ips
    
    # Security configuration
    configure_firewall || {
        log_error "Failed to configure firewall"
        exit 1
    }
    
    configure_fail2ban || {
        log_error "Failed to configure Fail2Ban"
        exit 1
    }
    
    # Monitoring setup
    setup_monitoring || {
        log_error "Failed to setup monitoring"
        exit 1
    }
    
    log_success "VPS setup completed successfully!"
    log_info "Log file: $LOG_FILE"
    log_info "Configuration files:"
    log_info "  - Network: $NETWORK_CONFIG_FILE"
    log_info "  - Firewall: $FIREWALL_RULES_FILE"
    log_info ""
    log_info "Next steps:"
    log_info "1. Review and customize configuration files"
    log_info "2. Reboot the system to apply network changes"
    log_info "3. Run the health check script: $MONITORING_DIR/health-check.sh"
    log_info "4. Configure your email infrastructure"
}

# =============================================================================
# SCRIPT ENTRY POINT
# =============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi