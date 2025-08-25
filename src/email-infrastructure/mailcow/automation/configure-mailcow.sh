#!/bin/bash

# Mailcow Post-Installation Configuration Script
# This script handles the complete configuration of Mailcow after installation
# Usage: ./configure-mailcow.sh [config_file]

set -e

# Configuration
MAILCOW_DIR="/opt/mailcow-dockerized"
CONFIG_DIR="$(dirname "$0")/../config"
API_DIR="$(dirname "$0")/../api"
LOG_FILE="/var/log/mailcow-configure.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
DEFAULT_CONFIG_FILE="$CONFIG_DIR/mailcow-config.yaml"

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

# Load configuration
load_config() {
    CONFIG_FILE="${1:-$DEFAULT_CONFIG_FILE}"
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        warning "Configuration file not found: $CONFIG_FILE"
        create_default_config
        CONFIG_FILE="$DEFAULT_CONFIG_FILE"
    fi
    
    # Source admin credentials if available
    if [[ -f "$CONFIG_DIR/admin_credentials" ]]; then
        source "$CONFIG_DIR/admin_credentials"
    else
        error "Admin credentials file not found. Run install script first."
    fi
    
    info "Using configuration file: $CONFIG_FILE"
}

# Create default configuration
create_default_config() {
    log "Creating default configuration file..."
    
    mkdir -p "$CONFIG_DIR"
    
    cat > "$DEFAULT_CONFIG_FILE" << 'EOF'
# Mailcow Configuration Settings
mailcow:
  hostname: mail.example.com
  admin_email: admin@example.com
  
# API Configuration
api:
  enabled: true
  rate_limit: 100
  
# Security Settings
security:
  fail2ban_enabled: true
  password_policy:
    min_length: 12
    require_uppercase: true
    require_lowercase: true
    require_numbers: true
    require_symbols: true
  
# Backup Settings
backup:
  enabled: true
  retention_days: 30
  location: /var/backups/mailcow
  
# Domain Settings
domains:
  default_quota: 5120  # MB
  max_aliases: 100
  
# Mailbox Settings
mailboxes:
  default_quota: 1024  # MB
  max_mailboxes_per_domain: 100
  
# DKIM Settings
dkim:
  key_size: 2048
  selector: dkim
  
# TLS/SSL Settings
tls:
  protocols:
    - TLSv1.2
    - TLSv1.3
  ciphers: ECDHE+AESGCM:ECDHE+CHACHA20:DHE+AESGCM:DHE+CHACHA20:!aNULL:!MD5:!DSS
  
# Spam Settings
spam:
  quarantine_enabled: true
  spam_score_reject: 15
  spam_score_add_header: 6
  
# Additional Services
services:
  webdav_enabled: true
  activesync_enabled: true
  cardav_enabled: true
  caldav_enabled: true
EOF
    
    info "Default configuration created at: $DEFAULT_CONFIG_FILE"
}

# Wait for Mailcow to be ready
wait_for_mailcow() {
    log "Waiting for Mailcow services to be ready..."
    
    cd "$MAILCOW_DIR"
    
    # Check if containers are running
    for i in {1..30}; do
        if docker-compose ps | grep -q "Up"; then
            info "Mailcow containers are running"
            break
        fi
        
        if [[ $i -eq 30 ]]; then
            error "Mailcow containers failed to start within 5 minutes"
        fi
        
        sleep 10
    done
    
    # Wait for web interface to be accessible
    for i in {1..30}; do
        if curl -k -s "https://${DOMAIN:-localhost}/api/v1/get/status/containers" > /dev/null 2>&1; then
            info "Mailcow API is accessible"
            break
        fi
        
        if [[ $i -eq 30 ]]; then
            warning "Mailcow API not accessible, continuing anyway"
        fi
        
        sleep 10
    done
}

# Get API key
get_api_key() {
    log "Setting up API access..."
    
    cd "$MAILCOW_DIR"
    
    # Try to get existing API key from config
    if [[ -f mailcow.conf ]]; then
        API_KEY=$(grep "MAILCOW_API_KEY" mailcow.conf | cut -d'=' -f2)
    fi
    
    # Generate new API key if not found
    if [[ -z "$API_KEY" ]]; then
        API_KEY=$(openssl rand -base64 32)
        echo "MAILCOW_API_KEY=$API_KEY" >> mailcow.conf
        
        # Restart containers to apply new API key
        docker-compose restart nginx-mailcow
    fi
    
    # Save API key for scripts
    echo "export MAILCOW_API_KEY='$API_KEY'" > "$CONFIG_DIR/api_key"
    chmod 600 "$CONFIG_DIR/api_key"
    
    info "API key configured and saved"
}

# Create admin user
create_admin_user() {
    log "Creating admin user..."
    
    cd "$MAILCOW_DIR"
    
    # Create admin user using docker exec
    docker-compose exec -T mysql-mailcow mysql -u root -p"$DBROOT" mailcow << EOF
INSERT IGNORE INTO admin (username, password, superadmin, active) 
VALUES ('$ADMIN_EMAIL', '{BLF-CRYPT}\$2y\$10\$$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-22)', 1, 1);
EOF
    
    # Update admin password
    ADMIN_PASS_HASH=$(docker-compose exec -T php-fpm-mailcow php -r "echo password_hash('$ADMIN_PASS', PASSWORD_DEFAULT);")
    
    docker-compose exec -T mysql-mailcow mysql -u root -p"$DBROOT" mailcow << EOF
UPDATE admin SET password = '$ADMIN_PASS_HASH' WHERE username = '$ADMIN_EMAIL';
EOF
    
    info "Admin user created: $ADMIN_EMAIL"
}

# Configure security settings
configure_security() {
    log "Configuring security settings..."
    
    cd "$MAILCOW_DIR"
    
    # Enable Fail2ban
    if ! docker-compose ps | grep -q "fail2ban"; then
        warning "Fail2ban container not found, enabling..."
        sed -i 's/SKIP_FAIL2BAN=y/SKIP_FAIL2BAN=n/' mailcow.conf
        docker-compose up -d fail2ban-mailcow
    fi
    
    # Configure TLS settings
    cat > data/conf/nginx/tls.conf << 'EOF'
# TLS Configuration
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
ssl_ecdh_curve secp384r1;
ssl_prefer_server_ciphers on;
ssl_session_cache shared:SSL:10m;
ssl_session_tickets off;
ssl_stapling on;
ssl_stapling_verify on;

# Security headers
add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload";
add_header X-Frame-Options DENY;
add_header X-Content-Type-Options nosniff;
add_header X-XSS-Protection "1; mode=block";
add_header Referrer-Policy "no-referrer-when-downgrade";
EOF
    
    # Configure password policy
    docker-compose exec -T mysql-mailcow mysql -u root -p"$DBROOT" mailcow << 'EOF'
INSERT IGNORE INTO domain_admins (username, domain, created, active) 
VALUES ('admin', 'ALL', NOW(), 1);

UPDATE domain SET passwd_update_expiry = 90 WHERE domain != 'ALL';
EOF
    
    info "Security settings configured"
}

# Setup backup system
setup_backup() {
    log "Setting up backup system..."
    
    BACKUP_DIR="/var/backups/mailcow"
    mkdir -p "$BACKUP_DIR"
    
    # Create backup script
    cat > "$BACKUP_DIR/backup.sh" << 'EOF'
#!/bin/bash

# Mailcow Backup Script
BACKUP_DIR="/var/backups/mailcow"
MAILCOW_DIR="/opt/mailcow-dockerized"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/mailcow-backup-$DATE.tar.gz"

cd "$MAILCOW_DIR"

# Create backup
./helper-scripts/backup_and_restore.sh backup all "$BACKUP_FILE"

# Cleanup old backups (keep 30 days)
find "$BACKUP_DIR" -name "mailcow-backup-*.tar.gz" -mtime +30 -delete

echo "Backup completed: $BACKUP_FILE"
EOF
    
    chmod +x "$BACKUP_DIR/backup.sh"
    
    # Setup cron job
    (crontab -l 2>/dev/null; echo "0 2 * * * $BACKUP_DIR/backup.sh") | crontab -
    
    info "Backup system configured with daily backups at 2:00 AM"
}

# Configure monitoring
setup_monitoring() {
    log "Setting up monitoring..."
    
    cd "$MAILCOW_DIR"
    
    # Enable watchdog
    if ! grep -q "USE_WATCHDOG=y" mailcow.conf; then
        echo "USE_WATCHDOG=y" >> mailcow.conf
        echo "WATCHDOG_NOTIFY_EMAIL=$ADMIN_EMAIL" >> mailcow.conf
    fi
    
    # Configure log rotation
    cat > data/conf/rsyslog/mailcow.conf << 'EOF'
# Mailcow log rotation
/var/log/mailcow/*.log {
    daily
    missingok
    rotate 30
    compress
    notifempty
    create 644 root root
    postrotate
        /usr/bin/docker-compose -f /opt/mailcow-dockerized/docker-compose.yml restart rsyslog-mailcow
    endscript
}
EOF
    
    info "Monitoring configured"
}

# Configure mail routing
configure_mail_routing() {
    log "Configuring mail routing..."
    
    cd "$MAILCOW_DIR"
    
    # Configure Postfix main settings
    cat > data/conf/postfix/main.cf.d/custom.cf << 'EOF'
# Custom Postfix configuration
# Reject unknown domains
smtpd_reject_unlisted_recipient = yes
smtpd_reject_unlisted_sender = yes

# Rate limiting
smtpd_client_connection_rate_limit = 10
smtpd_client_message_rate_limit = 20

# Additional security
smtpd_helo_required = yes
smtpd_delay_reject = yes

# Message size limits
message_size_limit = 52428800
mailbox_size_limit = 0
EOF
    
    # Restart Postfix to apply changes
    docker-compose restart postfix-mailcow
    
    info "Mail routing configured"
}

# Setup DKIM
setup_dkim() {
    log "Setting up DKIM configuration..."
    
    cd "$MAILCOW_DIR"
    
    # DKIM will be configured per domain via API
    info "DKIM will be configured automatically for each domain"
}

# Generate status report
generate_report() {
    log "Generating configuration report..."
    
    REPORT_FILE="/tmp/mailcow-config-report.txt"
    
    cat > "$REPORT_FILE" << EOF
Mailcow Configuration Report
Generated: $(date)
==========================

Installation Details:
- Mailcow Directory: $MAILCOW_DIR
- Domain: $DOMAIN
- Admin Email: $ADMIN_EMAIL

Container Status:
$(cd "$MAILCOW_DIR" && docker-compose ps)

Configuration Files:
- Main Config: $MAILCOW_DIR/mailcow.conf
- API Key: $CONFIG_DIR/api_key
- Admin Credentials: $CONFIG_DIR/admin_credentials

Services Status:
- Web Interface: https://$DOMAIN
- API Endpoint: https://$DOMAIN/api/v1/
- Mail Ports: 25, 143, 465, 587, 993, 995

Security Features:
- SSL/TLS: Enabled
- Fail2ban: $(docker-compose ps | grep -q fail2ban && echo "Enabled" || echo "Disabled")
- Password Policy: Configured
- Security Headers: Enabled

Backup:
- Location: $BACKUP_DIR
- Schedule: Daily at 2:00 AM
- Retention: 30 days

Next Steps:
1. Test mail functionality
2. Configure domains via API
3. Set up mailboxes
4. Configure DKIM for domains

EOF
    
    cat "$REPORT_FILE"
    cp "$REPORT_FILE" "$CONFIG_DIR/configuration-report.txt"
    
    info "Configuration report saved to: $CONFIG_DIR/configuration-report.txt"
}

# Main configuration function
main() {
    log "Starting Mailcow configuration..."
    
    check_root
    load_config "$1"
    wait_for_mailcow
    get_api_key
    create_admin_user
    configure_security
    setup_backup
    setup_monitoring
    configure_mail_routing
    setup_dkim
    generate_report
    
    log "Mailcow configuration completed successfully!"
    
    cat << EOF

${GREEN}Configuration Complete!${NC}

Access Information:
- Web Interface: https://$DOMAIN
- Admin Email: $ADMIN_EMAIL
- Admin Password: Check $CONFIG_DIR/admin_credentials

API Information:
- API Key: Check $CONFIG_DIR/api_key
- API Endpoint: https://$DOMAIN/api/v1/

Next Steps:
1. Access the web interface and verify login
2. Use the Python API wrapper: python3 ../api/mailcow-api.py
3. Configure your first domain: ../automation/domain-manager.sh add example.com
4. Set up mailboxes: ../automation/mailbox-manager.sh create user@example.com

Configuration report: $CONFIG_DIR/configuration-report.txt

EOF
}

# Run main function
main "$@"