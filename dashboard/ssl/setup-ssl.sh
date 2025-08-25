#!/bin/bash

# SSL/TLS Setup Script for Cold Email Dashboard
# Automates SSL certificate setup with Let's Encrypt and self-signed certificates

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOMAIN="${1:-dashboard.localhost}"
EMAIL="${2:-admin@localhost}"
CERT_TYPE="${3:-letsencrypt}"  # letsencrypt, selfsigned, or import

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Install required packages
install_dependencies() {
    log_info "Installing SSL dependencies..."
    
    apt-get update -qq
    apt-get install -y \
        certbot \
        python3-certbot-nginx \
        openssl \
        curl \
        wget
    
    log_success "SSL dependencies installed"
}

# Validate domain configuration
validate_domain() {
    local domain="$1"
    
    log_info "Validating domain configuration..."
    
    # Check if domain resolves to this server
    local domain_ip
    domain_ip=$(dig +short "$domain" 2>/dev/null || echo "")
    
    if [[ -z "$domain_ip" ]]; then
        log_warning "Domain $domain does not resolve to any IP address"
        log_warning "Make sure DNS is configured properly"
        return 1
    fi
    
    # Get public IP
    local public_ip
    public_ip=$(curl -s https://api.ipify.org 2>/dev/null || echo "")
    
    if [[ -n "$public_ip" && "$domain_ip" != "$public_ip" ]]; then
        log_warning "Domain $domain resolves to $domain_ip but server public IP is $public_ip"
        log_warning "SSL certificate validation may fail"
    else
        log_success "Domain configuration appears correct"
    fi
}

# Create directories
create_directories() {
    log_info "Creating SSL directories..."
    
    mkdir -p /etc/ssl/dashboard
    mkdir -p /var/www/certbot
    mkdir -p /etc/nginx/ssl
    
    chown -R www-data:www-data /var/www/certbot
    
    log_success "SSL directories created"
}

# Generate self-signed certificate
generate_selfsigned() {
    local domain="$1"
    
    log_info "Generating self-signed SSL certificate..."
    
    # Create OpenSSL configuration
    cat > /tmp/ssl.conf << EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = v3_req

[dn]
C=US
ST=State
L=City
O=Organization
OU=Dashboard
CN=$domain

[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = $domain
DNS.2 = www.$domain
DNS.3 = localhost
IP.1 = 127.0.0.1
EOF
    
    # Generate private key
    openssl genrsa -out /etc/ssl/dashboard/dashboard.key 2048
    
    # Generate certificate signing request
    openssl req -new -key /etc/ssl/dashboard/dashboard.key \
        -out /tmp/dashboard.csr \
        -config /tmp/ssl.conf
    
    # Generate self-signed certificate
    openssl x509 -req -in /tmp/dashboard.csr \
        -signkey /etc/ssl/dashboard/dashboard.key \
        -out /etc/ssl/dashboard/dashboard.crt \
        -days 365 \
        -extensions v3_req \
        -extfile /tmp/ssl.conf
    
    # Create full chain
    cp /etc/ssl/dashboard/dashboard.crt /etc/ssl/dashboard/fullchain.pem
    cp /etc/ssl/dashboard/dashboard.key /etc/ssl/dashboard/privkey.pem
    
    # Set permissions
    chmod 600 /etc/ssl/dashboard/dashboard.key /etc/ssl/dashboard/privkey.pem
    chmod 644 /etc/ssl/dashboard/dashboard.crt /etc/ssl/dashboard/fullchain.pem
    
    # Cleanup
    rm -f /tmp/ssl.conf /tmp/dashboard.csr
    
    log_success "Self-signed certificate generated"
    log_warning "Self-signed certificates are not trusted by browsers"
    log_warning "Users will see a security warning when accessing the site"
}

# Generate Let's Encrypt certificate
generate_letsencrypt() {
    local domain="$1"
    local email="$2"
    
    log_info "Generating Let's Encrypt SSL certificate..."
    
    # Validate domain first
    validate_domain "$domain" || {
        log_error "Domain validation failed. Cannot proceed with Let's Encrypt"
        return 1
    }
    
    # Stop nginx temporarily if running
    local nginx_was_running=false
    if systemctl is-active --quiet nginx; then
        nginx_was_running=true
        systemctl stop nginx
    fi
    
    # Create temporary nginx config for validation
    cat > /etc/nginx/sites-available/certbot-temp << EOF
server {
    listen 80;
    server_name $domain;
    
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
    
    location / {
        return 301 https://\$server_name\$request_uri;
    }
}
EOF
    
    # Enable temporary config
    ln -sf /etc/nginx/sites-available/certbot-temp /etc/nginx/sites-enabled/certbot-temp
    rm -f /etc/nginx/sites-enabled/default
    
    # Start nginx
    systemctl start nginx
    
    # Wait for nginx to start
    sleep 2
    
    # Request certificate
    if certbot certonly \
        --webroot \
        --webroot-path=/var/www/certbot \
        --email "$email" \
        --agree-tos \
        --no-eff-email \
        --domains "$domain"; then
        
        # Copy certificates to dashboard location
        cp "/etc/letsencrypt/live/$domain/fullchain.pem" /etc/ssl/dashboard/
        cp "/etc/letsencrypt/live/$domain/privkey.pem" /etc/ssl/dashboard/
        
        # Create symbolic links for easier access
        ln -sf "/etc/letsencrypt/live/$domain/fullchain.pem" /etc/ssl/dashboard/dashboard.crt
        ln -sf "/etc/letsencrypt/live/$domain/privkey.pem" /etc/ssl/dashboard/dashboard.key
        
        log_success "Let's Encrypt certificate obtained successfully"
        
        # Remove temporary config
        rm -f /etc/nginx/sites-enabled/certbot-temp
        
        return 0
    else
        log_error "Failed to obtain Let's Encrypt certificate"
        log_info "Falling back to self-signed certificate"
        
        # Clean up and generate self-signed
        rm -f /etc/nginx/sites-enabled/certbot-temp
        
        if [[ "$nginx_was_running" == true ]]; then
            systemctl stop nginx
        fi
        
        generate_selfsigned "$domain"
        return 1
    fi
}

# Import existing certificate
import_certificate() {
    local cert_file="$1"
    local key_file="$2"
    local chain_file="${3:-}"
    
    log_info "Importing existing SSL certificate..."
    
    if [[ ! -f "$cert_file" ]]; then
        log_error "Certificate file not found: $cert_file"
        return 1
    fi
    
    if [[ ! -f "$key_file" ]]; then
        log_error "Private key file not found: $key_file"
        return 1
    fi
    
    # Validate certificate and key match
    local cert_modulus key_modulus
    cert_modulus=$(openssl x509 -noout -modulus -in "$cert_file" | openssl md5)
    key_modulus=$(openssl rsa -noout -modulus -in "$key_file" | openssl md5)
    
    if [[ "$cert_modulus" != "$key_modulus" ]]; then
        log_error "Certificate and private key do not match"
        return 1
    fi
    
    # Copy certificate files
    cp "$cert_file" /etc/ssl/dashboard/dashboard.crt
    cp "$key_file" /etc/ssl/dashboard/dashboard.key
    
    if [[ -n "$chain_file" && -f "$chain_file" ]]; then
        cp "$chain_file" /etc/ssl/dashboard/chain.pem
        cat /etc/ssl/dashboard/dashboard.crt /etc/ssl/dashboard/chain.pem > /etc/ssl/dashboard/fullchain.pem
    else
        cp /etc/ssl/dashboard/dashboard.crt /etc/ssl/dashboard/fullchain.pem
    fi
    
    cp /etc/ssl/dashboard/dashboard.key /etc/ssl/dashboard/privkey.pem
    
    # Set permissions
    chmod 600 /etc/ssl/dashboard/dashboard.key /etc/ssl/dashboard/privkey.pem
    chmod 644 /etc/ssl/dashboard/dashboard.crt /etc/ssl/dashboard/fullchain.pem
    
    log_success "SSL certificate imported successfully"
}

# Create DH parameters
generate_dhparam() {
    log_info "Generating Diffie-Hellman parameters (this may take a while)..."
    
    if [[ ! -f /etc/ssl/dashboard/dhparam.pem ]]; then
        openssl dhparam -out /etc/ssl/dashboard/dhparam.pem 2048
        log_success "DH parameters generated"
    else
        log_info "DH parameters already exist, skipping"
    fi
}

# Create SSL nginx configuration
create_ssl_nginx_config() {
    local domain="$1"
    
    log_info "Creating SSL nginx configuration..."
    
    cat > /etc/nginx/sites-available/dashboard-ssl << EOF
# Cold Email Dashboard - SSL Configuration

# HTTP redirect to HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name $domain;
    
    # Allow Let's Encrypt challenges
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
    
    # Redirect everything else to HTTPS
    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

# HTTPS server
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $domain;
    
    # SSL Configuration
    ssl_certificate /etc/ssl/dashboard/fullchain.pem;
    ssl_certificate_key /etc/ssl/dashboard/privkey.pem;
    ssl_dhparam /etc/ssl/dashboard/dhparam.pem;
    
    # SSL Security Settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_ecdh_curve secp384r1;
    ssl_session_timeout 10m;
    ssl_session_cache shared:SSL:10m;
    ssl_session_tickets off;
    
    # OCSP Stapling
    ssl_stapling on;
    ssl_stapling_verify on;
    ssl_trusted_certificate /etc/ssl/dashboard/fullchain.pem;
    resolver 8.8.8.8 8.8.4.4 valid=300s;
    resolver_timeout 5s;
    
    # Security Headers
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    
    # Logging
    access_log /var/log/nginx/dashboard_ssl_access.log combined;
    error_log /var/log/nginx/dashboard_ssl_error.log;
    
    # Dashboard proxy
    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
        proxy_cache_bypass \$http_upgrade;
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
    
    # Static files with caching
    location /static/ {
        proxy_pass http://127.0.0.1:5000;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    
    # Health check
    location /health {
        access_log off;
        proxy_pass http://127.0.0.1:5000;
    }
    
    # Security - block sensitive files
    location ~ /\\. {
        deny all;
    }
    
    location ~ \\.(log|conf|env)\$ {
        deny all;
    }
}
EOF
    
    # Enable SSL configuration
    ln -sf /etc/nginx/sites-available/dashboard-ssl /etc/nginx/sites-enabled/dashboard
    
    # Remove default site
    rm -f /etc/nginx/sites-enabled/default
    
    log_success "SSL nginx configuration created"
}

# Test SSL configuration
test_ssl_config() {
    local domain="$1"
    
    log_info "Testing SSL configuration..."
    
    # Test nginx configuration
    if nginx -t; then
        log_success "Nginx configuration is valid"
    else
        log_error "Nginx configuration is invalid"
        return 1
    fi
    
    # Restart nginx
    systemctl restart nginx
    
    # Wait for nginx to start
    sleep 3
    
    # Test SSL connection
    if curl -k -s -I "https://$domain/health" | grep -q "200 OK"; then
        log_success "SSL connection test passed"
    else
        log_warning "SSL connection test failed - this may be normal for self-signed certificates"
    fi
    
    # Test certificate
    local cert_info
    cert_info=$(openssl x509 -in /etc/ssl/dashboard/dashboard.crt -noout -subject -dates)
    log_info "Certificate information:"
    echo "$cert_info"
}

# Set up automatic renewal for Let's Encrypt
setup_renewal() {
    log_info "Setting up automatic certificate renewal..."
    
    # Create renewal script
    cat > /usr/local/bin/renew-dashboard-ssl.sh << 'EOF'
#!/bin/bash
# Dashboard SSL Certificate Renewal Script

LOGFILE="/var/log/dashboard-ssl-renewal.log"

log_message() {
    echo "$(date): $1" | tee -a "$LOGFILE"
}

# Renew Let's Encrypt certificates
if certbot renew --quiet --nginx; then
    log_message "Certificate renewal successful"
    
    # Copy renewed certificates to dashboard location
    if [[ -d "/etc/letsencrypt/live" ]]; then
        for domain_dir in /etc/letsencrypt/live/*/; do
            domain=$(basename "$domain_dir")
            if [[ -f "$domain_dir/fullchain.pem" && -f "$domain_dir/privkey.pem" ]]; then
                cp "$domain_dir/fullchain.pem" /etc/ssl/dashboard/
                cp "$domain_dir/privkey.pem" /etc/ssl/dashboard/
                log_message "Updated certificates for $domain"
            fi
        done
    fi
    
    # Reload nginx
    systemctl reload nginx
    log_message "Nginx reloaded"
else
    log_message "Certificate renewal failed"
    exit 1
fi
EOF
    
    chmod +x /usr/local/bin/renew-dashboard-ssl.sh
    
    # Create cron job for renewal
    cat > /etc/cron.d/dashboard-ssl-renewal << 'EOF'
# Dashboard SSL Certificate Renewal
# Runs twice daily at random minutes to avoid hitting rate limits
0 12 * * * root /usr/local/bin/renew-dashboard-ssl.sh
0 0 * * * root /usr/local/bin/renew-dashboard-ssl.sh
EOF
    
    chmod 644 /etc/cron.d/dashboard-ssl-renewal
    
    log_success "Automatic certificate renewal configured"
}

# Create SSL monitoring script
create_ssl_monitor() {
    log_info "Creating SSL monitoring script..."
    
    cat > /usr/local/bin/monitor-dashboard-ssl.sh << 'EOF'
#!/bin/bash
# Dashboard SSL Certificate Monitor

LOGFILE="/var/log/dashboard-ssl-monitor.log"
CERT_FILE="/etc/ssl/dashboard/dashboard.crt"
WARNING_DAYS=30

log_message() {
    echo "$(date): $1" | tee -a "$LOGFILE"
}

if [[ ! -f "$CERT_FILE" ]]; then
    log_message "ERROR: Certificate file not found: $CERT_FILE"
    exit 1
fi

# Check certificate expiration
expiry_date=$(openssl x509 -in "$CERT_FILE" -noout -enddate | cut -d= -f2)
expiry_epoch=$(date -d "$expiry_date" +%s)
current_epoch=$(date +%s)
days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))

if [[ $days_until_expiry -lt 0 ]]; then
    log_message "CRITICAL: Certificate has expired!"
    exit 2
elif [[ $days_until_expiry -lt $WARNING_DAYS ]]; then
    log_message "WARNING: Certificate expires in $days_until_expiry days"
    exit 1
else
    log_message "Certificate is valid for $days_until_expiry more days"
fi

# Test SSL connectivity
if curl -k -s -I https://localhost/health >/dev/null; then
    log_message "SSL connectivity test passed"
else
    log_message "WARNING: SSL connectivity test failed"
    exit 1
fi
EOF
    
    chmod +x /usr/local/bin/monitor-dashboard-ssl.sh
    
    # Add monitoring to cron
    echo "0 6 * * * root /usr/local/bin/monitor-dashboard-ssl.sh" >> /etc/cron.d/dashboard-ssl-renewal
    
    log_success "SSL monitoring script created"
}

# Display SSL information
show_ssl_info() {
    local domain="$1"
    
    log_success "SSL setup completed!"
    
    echo ""
    echo "=== SSL Certificate Information ==="
    openssl x509 -in /etc/ssl/dashboard/dashboard.crt -noout -subject -issuer -dates
    echo ""
    echo "=== Access URLs ==="
    echo "HTTPS: https://$domain"
    echo "Health Check: https://$domain/health"
    echo ""
    echo "=== Certificate Files ==="
    echo "Certificate: /etc/ssl/dashboard/dashboard.crt"
    echo "Private Key: /etc/ssl/dashboard/dashboard.key"
    echo "Full Chain: /etc/ssl/dashboard/fullchain.pem"
    echo ""
    echo "=== Management Commands ==="
    echo "Test SSL: curl -I https://$domain/health"
    echo "Check certificate: openssl x509 -in /etc/ssl/dashboard/dashboard.crt -noout -dates"
    echo "Renew certificate: /usr/local/bin/renew-dashboard-ssl.sh"
    echo "Monitor SSL: /usr/local/bin/monitor-dashboard-ssl.sh"
    echo ""
    echo "=== Logs ==="
    echo "SSL renewal: /var/log/dashboard-ssl-renewal.log"
    echo "SSL monitoring: /var/log/dashboard-ssl-monitor.log"
    echo "Nginx SSL access: /var/log/nginx/dashboard_ssl_access.log"
    echo "Nginx SSL errors: /var/log/nginx/dashboard_ssl_error.log"
}

# Main function
main() {
    local domain="$1"
    local email="$2"
    local cert_type="$3"
    
    log_info "Setting up SSL/TLS for Cold Email Dashboard"
    log_info "Domain: $domain"
    log_info "Email: $email"
    log_info "Certificate Type: $cert_type"
    
    check_root
    install_dependencies
    create_directories
    generate_dhparam
    
    case "$cert_type" in
        letsencrypt)
            generate_letsencrypt "$domain" "$email" || generate_selfsigned "$domain"
            setup_renewal
            ;;
        selfsigned)
            generate_selfsigned "$domain"
            ;;
        import)
            import_certificate "${4:-}" "${5:-}" "${6:-}"
            ;;
        *)
            log_error "Unknown certificate type: $cert_type"
            echo "Usage: $0 <domain> <email> <cert_type> [cert_file] [key_file] [chain_file]"
            echo "Certificate types: letsencrypt, selfsigned, import"
            exit 1
            ;;
    esac
    
    create_ssl_nginx_config "$domain"
    test_ssl_config "$domain"
    create_ssl_monitor
    show_ssl_info "$domain"
    
    log_success "SSL/TLS setup completed!"
}

# Parse command line arguments
if [[ $# -eq 0 ]]; then
    echo "Usage: $0 <domain> [email] [cert_type] [cert_file] [key_file] [chain_file]"
    echo ""
    echo "Arguments:"
    echo "  domain      - Domain name for SSL certificate"
    echo "  email       - Email for Let's Encrypt notifications (optional)"
    echo "  cert_type   - Certificate type: letsencrypt, selfsigned, import (default: letsencrypt)"
    echo "  cert_file   - Certificate file path (for import type)"
    echo "  key_file    - Private key file path (for import type)"
    echo "  chain_file  - Certificate chain file path (optional, for import type)"
    echo ""
    echo "Examples:"
    echo "  $0 dashboard.example.com admin@example.com letsencrypt"
    echo "  $0 dashboard.example.com admin@example.com selfsigned"
    echo "  $0 dashboard.example.com admin@example.com import /path/to/cert.pem /path/to/key.pem"
    exit 1
fi

main "$@"