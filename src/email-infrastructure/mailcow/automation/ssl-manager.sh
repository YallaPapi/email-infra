#!/bin/bash

# Mailcow SSL Certificate Management
# Handles SSL certificate generation, renewal, and management
# Usage: ./ssl-manager.sh [action] [domain] [options]

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/../config"
MAILCOW_DIR="/opt/mailcow-dockerized"
LOG_FILE="/var/log/mailcow-ssl-manager.log"

# SSL Configuration
SSL_CONFIG_FILE="$CONFIG_DIR/ssl-config.yaml"
SSL_BACKUP_DIR="$CONFIG_DIR/ssl-backups"
ACME_CONFIG_DIR="$MAILCOW_DIR/data/assets/ssl"

# Certificate settings
DEFAULT_KEY_SIZE=4096
DEFAULT_CERT_VALIDITY=90  # Days
RENEWAL_THRESHOLD=30      # Renew if expires within 30 days

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M%S')]${NC} $1" | tee -a "$LOG_FILE"
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

# Load configuration
load_config() {
    if [[ -f "$CONFIG_DIR/admin_credentials" ]]; then
        source "$CONFIG_DIR/admin_credentials"
    else
        warning "Admin credentials not found"
    fi
    
    if [[ -f "$SSL_CONFIG_FILE" ]]; then
        # Basic YAML parsing would go here
        info "SSL configuration loaded"
    else
        create_ssl_config
    fi
}

# Create SSL configuration
create_ssl_config() {
    log "Creating SSL configuration..."
    
    mkdir -p "$CONFIG_DIR" "$SSL_BACKUP_DIR"
    
    cat > "$SSL_CONFIG_FILE" << EOF
# SSL Configuration for Mailcow
# Generated: $(date)

ssl:
  # Certificate provider (letsencrypt, selfsigned, custom)
  provider: "letsencrypt"
  
  # Let's Encrypt configuration
  letsencrypt:
    # Use staging environment for testing (true/false)
    staging: false
    
    # Email for Let's Encrypt registration
    email: "${ADMIN_EMAIL:-admin@localhost}"
    
    # Key algorithm (rsa, ecdsa)
    key_algorithm: "rsa"
    
    # RSA key size (2048, 4096)
    rsa_key_size: $DEFAULT_KEY_SIZE
    
    # ECDSA curve (P-256, P-384)
    ecdsa_curve: "P-384"
    
    # Challenge type (http-01, dns-01, tls-alpn-01)
    challenge_type: "http-01"
    
    # Automatic renewal
    auto_renewal: true
    renewal_threshold_days: $RENEWAL_THRESHOLD
    
    # Post-renewal hooks
    post_renewal_hooks:
      - "docker-compose -f $MAILCOW_DIR/docker-compose.yml restart nginx-mailcow"
      - "docker-compose -f $MAILCOW_DIR/docker-compose.yml restart postfix-mailcow"
      - "docker-compose -f $MAILCOW_DIR/docker-compose.yml restart dovecot-mailcow"
  
  # Custom certificate configuration
  custom:
    # Certificate file path
    cert_file: ""
    
    # Private key file path
    key_file: ""
    
    # Intermediate certificate file path
    intermediate_file: ""
    
    # Full chain file path
    fullchain_file: ""
  
  # Self-signed certificate configuration
  selfsigned:
    # Certificate validity period (days)
    validity_days: 365
    
    # Certificate subject
    subject:
      country: "US"
      state: "California"
      city: "San Francisco"
      organization: "Mailcow"
      organizational_unit: "IT Department"
      common_name: "${DOMAIN:-mail.localhost}"
      
    # Subject Alternative Names
    san:
      - "${DOMAIN:-mail.localhost}"
      - "autodiscover.${DOMAIN:-localhost}"
      - "autoconfig.${DOMAIN:-localhost}"

# Security settings
security:
  # Supported TLS versions
  tls_versions:
    - "TLSv1.2"
    - "TLSv1.3"
  
  # Cipher suites (modern, intermediate, old)
  cipher_suite: "modern"
  
  # HSTS settings
  hsts:
    enabled: true
    max_age: 31536000
    include_subdomains: true
    preload: false
  
  # OCSP stapling
  ocsp_stapling: true
  
  # Certificate transparency
  certificate_transparency: true

# Monitoring and notifications
monitoring:
  # Check certificate expiration
  check_expiration: true
  
  # Days before expiration to send warning
  expiration_warning_days: 30
  
  # Notification methods
  notifications:
    email:
      enabled: true
      recipients:
        - "${ADMIN_EMAIL:-admin@localhost}"
      smtp_server: "localhost"
      smtp_port: 587
    
    webhook:
      enabled: false
      url: ""
      secret: ""

# Backup settings
backup:
  # Automatic backup of certificates
  auto_backup: true
  
  # Backup retention (days)
  retention_days: 90
  
  # Backup location
  backup_directory: "$SSL_BACKUP_DIR"
  
  # Compress backups
  compress: true

EOF
    
    chmod 600 "$SSL_CONFIG_FILE"
    info "SSL configuration created: $SSL_CONFIG_FILE"
}

# Check prerequisites
check_prerequisites() {
    log "Checking SSL prerequisites..."
    
    # Check if Mailcow directory exists
    if [[ ! -d "$MAILCOW_DIR" ]]; then
        error "Mailcow directory not found: $MAILCOW_DIR"
    fi
    
    # Check if running as root (needed for port 80/443)
    if [[ $EUID -ne 0 ]]; then
        error "SSL management requires root privileges"
    fi
    
    # Check if ports 80 and 443 are available
    for port in 80 443; do
        if ss -tuln | grep -q ":$port "; then
            info "Port $port is in use (expected for web server)"
        fi
    done
    
    # Check DNS resolution
    if [[ -n "$DOMAIN" ]]; then
        local resolved_ip=$(dig +short "$DOMAIN" 2>/dev/null | head -1)
        local server_ip=$(curl -s ifconfig.me 2>/dev/null)
        
        if [[ "$resolved_ip" == "$server_ip" ]]; then
            info "DNS resolution correct for $DOMAIN"
        else
            warning "DNS resolution mismatch: $DOMAIN resolves to $resolved_ip, server IP is $server_ip"
        fi
    fi
    
    info "Prerequisites check completed"
}

# Setup Let's Encrypt
setup_letsencrypt() {
    local domain="${1:-$DOMAIN}"
    local email="${2:-$ADMIN_EMAIL}"
    local staging="${3:-false}"
    
    if [[ -z "$domain" ]]; then
        error "Domain is required for Let's Encrypt setup"
    fi
    
    if [[ -z "$email" ]]; then
        error "Email is required for Let's Encrypt setup"
    fi
    
    log "Setting up Let's Encrypt for domain: $domain"
    
    check_prerequisites
    
    cd "$MAILCOW_DIR"
    
    # Update mailcow.conf for Let's Encrypt
    if [[ -f "mailcow.conf" ]]; then
        # Enable Let's Encrypt
        if grep -q "SKIP_LETS_ENCRYPT=" mailcow.conf; then
            sed -i "s/SKIP_LETS_ENCRYPT=.*/SKIP_LETS_ENCRYPT=n/" mailcow.conf
        else
            echo "SKIP_LETS_ENCRYPT=n" >> mailcow.conf
        fi
        
        # Set staging mode
        if [[ "$staging" == "true" ]]; then
            if grep -q "LE_STAGING=" mailcow.conf; then
                sed -i "s/LE_STAGING=.*/LE_STAGING=y/" mailcow.conf
            else
                echo "LE_STAGING=y" >> mailcow.conf
            fi
            warning "Let's Encrypt staging mode enabled - certificates will not be trusted!"
        else
            if grep -q "LE_STAGING=" mailcow.conf; then
                sed -i "s/LE_STAGING=.*/LE_STAGING=n/" mailcow.conf
            else
                echo "LE_STAGING=n" >> mailcow.conf
            fi
        fi
        
        # Set additional SANs if needed
        local additional_domains="autodiscover.$domain,autoconfig.$domain"
        if grep -q "ADDITIONAL_SAN=" mailcow.conf; then
            sed -i "s/ADDITIONAL_SAN=.*/ADDITIONAL_SAN=$additional_domains/" mailcow.conf
        else
            echo "ADDITIONAL_SAN=$additional_domains" >> mailcow.conf
        fi
        
        info "Mailcow configuration updated for Let's Encrypt"
    else
        error "mailcow.conf not found"
    fi
    
    # Restart containers to apply configuration
    log "Restarting Mailcow containers..."
    docker-compose down
    docker-compose up -d
    
    # Wait for services to be ready
    log "Waiting for services to start..."
    sleep 30
    
    # Monitor certificate generation
    monitor_certificate_generation "$domain"
}

# Monitor certificate generation
monitor_certificate_generation() {
    local domain="$1"
    local max_wait=300  # 5 minutes
    local wait_time=0
    
    log "Monitoring certificate generation for $domain..."
    
    cd "$MAILCOW_DIR"
    
    while [[ $wait_time -lt $max_wait ]]; do
        # Check if certificate files exist
        if [[ -f "data/assets/ssl/cert.pem" && -f "data/assets/ssl/key.pem" ]]; then
            info "Certificate files found"
            
            # Verify certificate
            if verify_certificate "$domain"; then
                info "Certificate generation completed successfully"
                
                # Backup the new certificate
                backup_certificate "$domain"
                return 0
            fi
        fi
        
        # Check ACME container logs for errors
        local acme_logs=$(docker-compose logs acme-mailcow 2>/dev/null | tail -10)
        if echo "$acme_logs" | grep -qi "error\|fail"; then
            warning "ACME container errors detected:"
            echo "$acme_logs"
        fi
        
        sleep 10
        wait_time=$((wait_time + 10))
        info "Waiting for certificate generation... (${wait_time}s/${max_wait}s)"
    done
    
    error "Certificate generation timeout after $max_wait seconds"
}

# Verify certificate
verify_certificate() {
    local domain="${1:-$DOMAIN}"
    local cert_file="$MAILCOW_DIR/data/assets/ssl/cert.pem"
    local key_file="$MAILCOW_DIR/data/assets/ssl/key.pem"
    
    log "Verifying certificate for $domain..."
    
    # Check if certificate files exist
    if [[ ! -f "$cert_file" ]]; then
        warning "Certificate file not found: $cert_file"
        return 1
    fi
    
    if [[ ! -f "$key_file" ]]; then
        warning "Private key file not found: $key_file"
        return 1
    fi
    
    # Verify certificate details
    local cert_subject=$(openssl x509 -in "$cert_file" -noout -subject 2>/dev/null | grep -o "CN=[^,]*" | cut -d'=' -f2)
    local cert_issuer=$(openssl x509 -in "$cert_file" -noout -issuer 2>/dev/null)
    local cert_expiry=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d'=' -f2)
    local cert_san=$(openssl x509 -in "$cert_file" -noout -text 2>/dev/null | grep -A1 "Subject Alternative Name" | tail -1 | tr -d ' ')
    
    info "Certificate Details:"
    info "  Subject: $cert_subject"
    info "  Issuer: $cert_issuer"
    info "  Expires: $cert_expiry"
    info "  SAN: $cert_san"
    
    # Verify certificate matches private key
    local cert_modulus=$(openssl x509 -in "$cert_file" -noout -modulus 2>/dev/null | md5sum | cut -d' ' -f1)
    local key_modulus=$(openssl rsa -in "$key_file" -noout -modulus 2>/dev/null | md5sum | cut -d' ' -f1)
    
    if [[ "$cert_modulus" == "$key_modulus" ]]; then
        info "✓ Certificate and private key match"
    else
        warning "✗ Certificate and private key do not match"
        return 1
    fi
    
    # Check if certificate contains the domain
    if echo "$cert_san" | grep -q "$domain" || [[ "$cert_subject" == *"$domain"* ]]; then
        info "✓ Certificate valid for domain: $domain"
    else
        warning "✗ Certificate not valid for domain: $domain"
        return 1
    fi
    
    # Test SSL connection
    log "Testing SSL connection..."
    local ssl_test=$(echo | openssl s_client -connect "$domain:443" -servername "$domain" 2>/dev/null | grep "Verification:")
    
    if echo "$ssl_test" | grep -q "OK"; then
        info "✓ SSL connection test passed"
        return 0
    else
        warning "✗ SSL connection test failed: $ssl_test"
        return 1
    fi
}

# Install custom certificate
install_custom_certificate() {
    local cert_file="$1"
    local key_file="$2"
    local intermediate_file="$3"
    
    if [[ -z "$cert_file" || -z "$key_file" ]]; then
        error "Certificate file and private key file are required"
    fi
    
    if [[ ! -f "$cert_file" ]]; then
        error "Certificate file not found: $cert_file"
    fi
    
    if [[ ! -f "$key_file" ]]; then
        error "Private key file not found: $key_file"
    fi
    
    log "Installing custom certificate..."
    
    cd "$MAILCOW_DIR"
    
    # Backup existing certificates
    backup_certificate "custom-$(date +%Y%m%d_%H%M%S)"
    
    # Verify certificate and key match
    local cert_modulus=$(openssl x509 -in "$cert_file" -noout -modulus 2>/dev/null | md5sum | cut -d' ' -f1)
    local key_modulus=$(openssl rsa -in "$key_file" -noout -modulus 2>/dev/null | md5sum | cut -d' ' -f1)
    
    if [[ "$cert_modulus" != "$key_modulus" ]]; then
        error "Certificate and private key do not match"
    fi
    
    info "Certificate and private key validation passed"
    
    # Create SSL directory if it doesn't exist
    mkdir -p "data/assets/ssl"
    
    # Install certificate files
    cp "$cert_file" "data/assets/ssl/cert.pem"
    cp "$key_file" "data/assets/ssl/key.pem"
    
    # Install intermediate certificate if provided
    if [[ -n "$intermediate_file" && -f "$intermediate_file" ]]; then
        cp "$intermediate_file" "data/assets/ssl/intermediate.pem"
        
        # Create full chain
        cat "data/assets/ssl/cert.pem" "data/assets/ssl/intermediate.pem" > "data/assets/ssl/combined.pem"
    else
        cp "data/assets/ssl/cert.pem" "data/assets/ssl/combined.pem"
    fi
    
    # Set proper permissions
    chmod 600 data/assets/ssl/*.pem
    chown root:root data/assets/ssl/*.pem
    
    # Update mailcow.conf to skip Let's Encrypt
    if grep -q "SKIP_LETS_ENCRYPT=" mailcow.conf; then
        sed -i "s/SKIP_LETS_ENCRYPT=.*/SKIP_LETS_ENCRYPT=y/" mailcow.conf
    else
        echo "SKIP_LETS_ENCRYPT=y" >> mailcow.conf
    fi
    
    # Restart containers to apply new certificate
    log "Restarting containers to apply new certificate..."
    docker-compose restart nginx-mailcow postfix-mailcow dovecot-mailcow
    
    # Wait for services to restart
    sleep 10
    
    # Verify installation
    if verify_certificate; then
        info "Custom certificate installed successfully"
    else
        error "Custom certificate installation failed"
    fi
}

# Generate self-signed certificate
generate_selfsigned_certificate() {
    local domain="${1:-$DOMAIN}"
    local validity_days="${2:-365}"
    
    if [[ -z "$domain" ]]; then
        error "Domain is required for self-signed certificate"
    fi
    
    log "Generating self-signed certificate for $domain..."
    
    cd "$MAILCOW_DIR"
    
    # Backup existing certificates
    backup_certificate "before-selfsigned-$(date +%Y%m%d_%H%M%S)"
    
    # Create SSL directory
    mkdir -p "data/assets/ssl"
    
    # Generate private key
    openssl genrsa -out "data/assets/ssl/key.pem" $DEFAULT_KEY_SIZE
    
    # Create certificate signing request configuration
    cat > "/tmp/cert_config.conf" << EOF
[req]
default_bits = $DEFAULT_KEY_SIZE
prompt = no
distinguished_name = req_distinguished_name
req_extensions = v3_req

[req_distinguished_name]
C = US
ST = California
L = San Francisco
O = Mailcow
OU = IT Department
CN = $domain

[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = $domain
DNS.2 = autodiscover.$domain
DNS.3 = autoconfig.$domain
EOF
    
    # Generate certificate
    openssl req -new -x509 -key "data/assets/ssl/key.pem" \
        -out "data/assets/ssl/cert.pem" \
        -days "$validity_days" \
        -config "/tmp/cert_config.conf" \
        -extensions v3_req
    
    # Create combined certificate (same as cert for self-signed)
    cp "data/assets/ssl/cert.pem" "data/assets/ssl/combined.pem"
    
    # Set proper permissions
    chmod 600 data/assets/ssl/*.pem
    chown root:root data/assets/ssl/*.pem
    
    # Clean up
    rm -f "/tmp/cert_config.conf"
    
    # Update mailcow.conf to skip Let's Encrypt
    if grep -q "SKIP_LETS_ENCRYPT=" mailcow.conf; then
        sed -i "s/SKIP_LETS_ENCRYPT=.*/SKIP_LETS_ENCRYPT=y/" mailcow.conf
    else
        echo "SKIP_LETS_ENCRYPT=y" >> mailcow.conf
    fi
    
    # Restart containers
    log "Restarting containers to apply self-signed certificate..."
    docker-compose restart nginx-mailcow postfix-mailcow dovecot-mailcow
    
    sleep 10
    
    info "Self-signed certificate generated for $domain"
    warning "Self-signed certificates are not trusted by browsers and mail clients"
    warning "Use only for testing or internal purposes"
}

# Backup certificate
backup_certificate() {
    local backup_name="${1:-backup-$(date +%Y%m%d_%H%M%S)}"
    
    log "Backing up certificates: $backup_name"
    
    mkdir -p "$SSL_BACKUP_DIR"
    
    cd "$MAILCOW_DIR"
    
    if [[ -d "data/assets/ssl" ]]; then
        # Create backup archive
        tar -czf "$SSL_BACKUP_DIR/${backup_name}.tar.gz" -C data/assets ssl/
        
        # Create metadata file
        cat > "$SSL_BACKUP_DIR/${backup_name}.meta" << EOF
# SSL Certificate Backup Metadata
BACKUP_NAME=$backup_name
CREATED=$(date -Iseconds)
DOMAIN=$DOMAIN
BACKUP_TYPE=ssl_certificates

# Certificate details
EOF
        
        # Add certificate details if available
        if [[ -f "data/assets/ssl/cert.pem" ]]; then
            echo "# Certificate Subject:" >> "$SSL_BACKUP_DIR/${backup_name}.meta"
            openssl x509 -in "data/assets/ssl/cert.pem" -noout -subject >> "$SSL_BACKUP_DIR/${backup_name}.meta" 2>/dev/null || true
            echo "# Certificate Expiry:" >> "$SSL_BACKUP_DIR/${backup_name}.meta"
            openssl x509 -in "data/assets/ssl/cert.pem" -noout -enddate >> "$SSL_BACKUP_DIR/${backup_name}.meta" 2>/dev/null || true
        fi
        
        info "Certificate backup created: $SSL_BACKUP_DIR/${backup_name}.tar.gz"
    else
        warning "No SSL certificates found to backup"
    fi
}

# Restore certificate
restore_certificate() {
    local backup_name="$1"
    
    if [[ -z "$backup_name" ]]; then
        error "Backup name is required"
    fi
    
    local backup_file="$SSL_BACKUP_DIR/${backup_name}.tar.gz"
    
    if [[ ! -f "$backup_file" ]]; then
        error "Backup file not found: $backup_file"
    fi
    
    log "Restoring certificate from backup: $backup_name"
    
    cd "$MAILCOW_DIR"
    
    # Create current backup before restore
    backup_certificate "before-restore-$(date +%Y%m%d_%H%M%S)"
    
    # Extract backup
    tar -xzf "$backup_file" -C data/assets/
    
    # Set proper permissions
    chmod 600 data/assets/ssl/*.pem 2>/dev/null || true
    chown root:root data/assets/ssl/*.pem 2>/dev/null || true
    
    # Restart containers
    log "Restarting containers to apply restored certificate..."
    docker-compose restart nginx-mailcow postfix-mailcow dovecot-mailcow
    
    sleep 10
    
    info "Certificate restored from backup: $backup_name"
}

# List certificates
list_certificates() {
    local format="${1:-table}"
    
    log "Listing SSL certificates..."
    
    case "$format" in
        "table")
            echo ""
            printf "%-20s %-30s %-20s %-15s %-10s\n" "Type" "Subject/Domain" "Issuer" "Expires" "Status"
            printf "%-20s %-30s %-20s %-15s %-10s\n" "====================" "==============================" "====================" "===============" "=========="
            
            # Check current certificate
            cd "$MAILCOW_DIR"
            if [[ -f "data/assets/ssl/cert.pem" ]]; then
                local cert_subject=$(openssl x509 -in "data/assets/ssl/cert.pem" -noout -subject 2>/dev/null | sed 's/.*CN=\([^,]*\).*/\1/' || echo "Unknown")
                local cert_issuer=$(openssl x509 -in "data/assets/ssl/cert.pem" -noout -issuer 2>/dev/null | sed 's/.*CN=\([^,]*\).*/\1/' || echo "Unknown")
                local cert_expiry=$(openssl x509 -in "data/assets/ssl/cert.pem" -noout -enddate 2>/dev/null | cut -d'=' -f2 | cut -d' ' -f1-3 || echo "Unknown")
                
                # Determine certificate type
                local cert_type="Unknown"
                if echo "$cert_issuer" | grep -qi "let's encrypt"; then
                    cert_type="Let's Encrypt"
                elif [[ "$cert_subject" == "$cert_issuer" ]]; then
                    cert_type="Self-Signed"
                else
                    cert_type="Custom"
                fi
                
                # Check if certificate is expired
                local status="Valid"
                if openssl x509 -in "data/assets/ssl/cert.pem" -noout -checkend 0 >/dev/null 2>&1; then
                    status="Valid"
                else
                    status="Expired"
                fi
                
                printf "%-20s %-30s %-20s %-15s %-10s\n" "$cert_type" "$cert_subject" "$cert_issuer" "$cert_expiry" "$status"
            else
                printf "%-20s %-30s %-20s %-15s %-10s\n" "None" "No certificate" "N/A" "N/A" "Missing"
            fi
            echo ""
            ;;
        "json")
            echo "{"
            cd "$MAILCOW_DIR"
            if [[ -f "data/assets/ssl/cert.pem" ]]; then
                local cert_subject=$(openssl x509 -in "data/assets/ssl/cert.pem" -noout -subject 2>/dev/null | sed 's/.*CN=\([^,]*\).*/\1/' || echo "Unknown")
                local cert_issuer=$(openssl x509 -in "data/assets/ssl/cert.pem" -noout -issuer 2>/dev/null | sed 's/.*CN=\([^,]*\).*/\1/' || echo "Unknown")
                local cert_expiry=$(openssl x509 -in "data/assets/ssl/cert.pem" -noout -enddate 2>/dev/null | cut -d'=' -f2 || echo "Unknown")
                
                echo "  \"current_certificate\": {"
                echo "    \"subject\": \"$cert_subject\","
                echo "    \"issuer\": \"$cert_issuer\","
                echo "    \"expiry\": \"$cert_expiry\","
                echo "    \"file_path\": \"data/assets/ssl/cert.pem\""
                echo "  }"
            else
                echo "  \"current_certificate\": null"
            fi
            echo "}"
            ;;
    esac
}

# Check certificate expiration
check_expiration() {
    local warning_days="${1:-$RENEWAL_THRESHOLD}"
    
    log "Checking certificate expiration..."
    
    cd "$MAILCOW_DIR"
    
    if [[ ! -f "data/assets/ssl/cert.pem" ]]; then
        warning "No certificate found"
        return 1
    fi
    
    # Check if certificate is expired
    if ! openssl x509 -in "data/assets/ssl/cert.pem" -noout -checkend 0 >/dev/null 2>&1; then
        error "Certificate has already expired!"
        return 1
    fi
    
    # Check if certificate expires within warning period
    local warning_seconds=$((warning_days * 24 * 60 * 60))
    
    if ! openssl x509 -in "data/assets/ssl/cert.pem" -noout -checkend $warning_seconds >/dev/null 2>&1; then
        local expiry_date=$(openssl x509 -in "data/assets/ssl/cert.pem" -noout -enddate | cut -d'=' -f2)
        warning "Certificate expires soon: $expiry_date"
        warning "Consider renewing the certificate"
        return 2
    fi
    
    local expiry_date=$(openssl x509 -in "data/assets/ssl/cert.pem" -noout -enddate | cut -d'=' -f2)
    info "Certificate is valid until: $expiry_date"
    return 0
}

# Renew certificate
renew_certificate() {
    log "Renewing certificate..."
    
    cd "$MAILCOW_DIR"
    
    # Check current certificate type
    if [[ -f "data/assets/ssl/cert.pem" ]]; then
        local cert_issuer=$(openssl x509 -in "data/assets/ssl/cert.pem" -noout -issuer 2>/dev/null)
        
        if echo "$cert_issuer" | grep -qi "let's encrypt"; then
            info "Renewing Let's Encrypt certificate..."
            
            # Force renewal by restarting ACME container
            docker-compose restart acme-mailcow
            
            # Monitor renewal process
            monitor_certificate_generation "$DOMAIN"
            
        else
            warning "Cannot automatically renew non-Let's Encrypt certificate"
            warning "Please install a new certificate manually"
            return 1
        fi
    else
        error "No certificate found to renew"
        return 1
    fi
}

# Show usage
show_usage() {
    cat << EOF
Mailcow SSL Certificate Manager

Usage: $0 [action] [domain] [options]

Actions:
  setup-letsencrypt [domain] [email] [--staging]
    Setup Let's Encrypt SSL certificates
    
  install-custom <cert_file> <key_file> [intermediate_file]
    Install custom SSL certificate
    
  generate-selfsigned [domain] [validity_days]
    Generate self-signed certificate
    
  verify [domain]
    Verify current SSL certificate
    
  list [format]
    List current certificates (format: table, json)
    
  check-expiration [warning_days]
    Check certificate expiration
    
  renew
    Renew SSL certificate
    
  backup [backup_name]
    Backup current certificates
    
  restore <backup_name>
    Restore certificates from backup

Options:
  --staging         Use Let's Encrypt staging environment
  --force          Force operation without confirmation
  --help          Show this help message

Examples:
  $0 setup-letsencrypt mail.example.com admin@example.com
  $0 setup-letsencrypt mail.example.com admin@example.com --staging
  $0 install-custom /path/to/cert.pem /path/to/key.pem /path/to/intermediate.pem
  $0 generate-selfsigned mail.example.com 365
  $0 verify mail.example.com
  $0 list table
  $0 check-expiration 30
  $0 renew
  $0 backup before-update
  $0 restore backup-20231201_120000

Configuration file: $SSL_CONFIG_FILE
Backup directory: $SSL_BACKUP_DIR

EOF
}

# Main function
main() {
    local action="$1"
    shift
    
    # Load configuration
    load_config
    
    case "$action" in
        "setup-letsencrypt")
            local staging=""
            for arg in "$@"; do
                if [[ "$arg" == "--staging" ]]; then
                    staging="true"
                    break
                fi
            done
            setup_letsencrypt "$1" "$2" "$staging"
            ;;
        "install-custom")
            install_custom_certificate "$1" "$2" "$3"
            ;;
        "generate-selfsigned")
            generate_selfsigned_certificate "$1" "$2"
            ;;
        "verify")
            verify_certificate "$1"
            ;;
        "list")
            list_certificates "$1"
            ;;
        "check-expiration")
            check_expiration "$1"
            ;;
        "renew")
            renew_certificate
            ;;
        "backup")
            backup_certificate "$1"
            ;;
        "restore")
            restore_certificate "$1"
            ;;
        "help"|"--help"|"-h")
            show_usage
            ;;
        "")
            error "No action specified. Use '$0 help' for usage information."
            ;;
        *)
            error "Unknown action: $action. Use '$0 help' for usage information."
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi