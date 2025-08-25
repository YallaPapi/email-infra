#!/bin/bash

# Nginx Setup Script for Cold Email Dashboard
# Configures nginx as a reverse proxy with SSL support

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOMAIN="${1:-dashboard.yourdomain.com}"
EMAIL="${2:-admin@yourdomain.com}"

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

# Install nginx
install_nginx() {
    log_info "Installing nginx..."
    
    apt-get update -qq
    apt-get install -y nginx
    
    # Enable and start nginx
    systemctl enable nginx
    systemctl start nginx
    
    log_success "Nginx installed and started"
}

# Install certbot for SSL certificates
install_certbot() {
    log_info "Installing certbot for SSL certificates..."
    
    apt-get install -y certbot python3-certbot-nginx
    
    log_success "Certbot installed"
}

# Configure firewall
configure_firewall() {
    log_info "Configuring firewall for nginx..."
    
    # Allow nginx through firewall
    ufw allow 'Nginx Full'
    ufw allow 'Nginx HTTP'
    ufw allow 'Nginx HTTPS'
    
    log_success "Firewall configured for nginx"
}

# Backup existing nginx config
backup_nginx_config() {
    log_info "Backing up existing nginx configuration..."
    
    if [[ -f /etc/nginx/nginx.conf ]]; then
        cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup.$(date +%Y%m%d_%H%M%S)
        log_success "Nginx config backed up"
    fi
}

# Install nginx configuration
install_nginx_config() {
    log_info "Installing nginx configuration..."
    
    # Copy main nginx config if it exists
    if [[ -f "$SCRIPT_DIR/nginx.conf" ]]; then
        cp "$SCRIPT_DIR/nginx.conf" /etc/nginx/nginx.conf
        log_success "Main nginx.conf installed"
    fi
    
    # Install dashboard-specific configuration
    if [[ -f "$SCRIPT_DIR/dashboard.conf" ]]; then
        # Update domain in config
        sed "s/dashboard\.yourdomain\.com/$DOMAIN/g" "$SCRIPT_DIR/dashboard.conf" > /etc/nginx/sites-available/dashboard
        
        # Enable the site
        ln -sf /etc/nginx/sites-available/dashboard /etc/nginx/sites-enabled/dashboard
        
        # Remove default site
        rm -f /etc/nginx/sites-enabled/default
        
        log_success "Dashboard nginx config installed"
    else
        log_error "Dashboard nginx config not found at $SCRIPT_DIR/dashboard.conf"
        exit 1
    fi
}

# Create SSL certificate directory
setup_ssl_directories() {
    log_info "Setting up SSL directories..."
    
    mkdir -p /etc/letsencrypt/live/$DOMAIN
    mkdir -p /var/www/certbot
    
    chown -R www-data:www-data /var/www/certbot
    
    log_success "SSL directories created"
}

# Test nginx configuration
test_nginx_config() {
    log_info "Testing nginx configuration..."
    
    if nginx -t; then
        log_success "Nginx configuration is valid"
    else
        log_error "Nginx configuration is invalid"
        exit 1
    fi
}

# Create temporary SSL certificate for initial setup
create_temporary_ssl() {
    log_info "Creating temporary SSL certificate..."
    
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/ssl/private/dashboard-selfsigned.key \
        -out /etc/ssl/certs/dashboard-selfsigned.crt \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=$DOMAIN"
    
    # Create temporary config that uses self-signed cert
    cat > /etc/nginx/sites-available/dashboard-temp << EOF
server {
    listen 80;
    server_name $DOMAIN;
    
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
    
    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

server {
    listen 443 ssl;
    server_name $DOMAIN;
    
    ssl_certificate /etc/ssl/certs/dashboard-selfsigned.crt;
    ssl_certificate_key /etc/ssl/private/dashboard-selfsigned.key;
    
    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
    
    # Use temporary config
    ln -sf /etc/nginx/sites-available/dashboard-temp /etc/nginx/sites-enabled/dashboard
    
    log_success "Temporary SSL certificate created"
}

# Obtain Let's Encrypt certificate
obtain_ssl_certificate() {
    log_info "Obtaining Let's Encrypt SSL certificate..."
    
    # Reload nginx with temporary config
    systemctl reload nginx
    
    # Obtain certificate
    if certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email "$EMAIL" --redirect; then
        log_success "SSL certificate obtained successfully"
        
        # Now switch to the production config
        ln -sf /etc/nginx/sites-available/dashboard /etc/nginx/sites-enabled/dashboard
        
        # Test and reload
        nginx -t && systemctl reload nginx
        
        log_success "Production nginx config activated with SSL"
    else
        log_warning "Failed to obtain SSL certificate. Continuing with self-signed certificate."
    fi
}

# Set up automatic certificate renewal
setup_cert_renewal() {
    log_info "Setting up automatic certificate renewal..."
    
    # Create renewal script
    cat > /etc/cron.d/certbot-renew << 'EOF'
# Automatically renew Let's Encrypt certificates
0 12 * * * root certbot renew --quiet --nginx --post-hook "systemctl reload nginx"
EOF
    
    chmod 644 /etc/cron.d/certbot-renew
    
    log_success "Automatic certificate renewal configured"
}

# Create nginx monitoring script
create_monitoring_script() {
    log_info "Creating nginx monitoring script..."
    
    cat > /usr/local/bin/nginx-monitor.sh << 'EOF'
#!/bin/bash
# Nginx monitoring and auto-restart script

LOGFILE="/var/log/nginx-monitor.log"

log_message() {
    echo "$(date): $1" >> $LOGFILE
}

# Check if nginx is running
if ! systemctl is-active --quiet nginx; then
    log_message "Nginx is not running, attempting to start..."
    systemctl start nginx
    
    if systemctl is-active --quiet nginx; then
        log_message "Nginx started successfully"
    else
        log_message "Failed to start nginx"
        exit 1
    fi
fi

# Check if nginx config is valid
if ! nginx -t >/dev/null 2>&1; then
    log_message "Nginx configuration is invalid"
    exit 1
fi

# Check if the dashboard is responding
if ! curl -s -f http://localhost:5000/api/health >/dev/null; then
    log_message "Dashboard backend is not responding"
    exit 1
fi

log_message "All checks passed"
EOF
    
    chmod +x /usr/local/bin/nginx-monitor.sh
    
    # Add to crontab
    echo "*/5 * * * * root /usr/local/bin/nginx-monitor.sh" > /etc/cron.d/nginx-monitor
    chmod 644 /etc/cron.d/nginx-monitor
    
    log_success "Nginx monitoring script created"
}

# Create log rotation for dashboard logs
setup_log_rotation() {
    log_info "Setting up log rotation..."
    
    cat > /etc/logrotate.d/dashboard-nginx << 'EOF'
/var/log/nginx/dashboard_*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 644 www-data www-data
    postrotate
        if [ -f /var/run/nginx.pid ]; then
            kill -USR1 `cat /var/run/nginx.pid`
        fi
    endscript
}
EOF
    
    log_success "Log rotation configured"
}

# Display summary
show_summary() {
    log_success "Nginx setup completed successfully!"
    
    echo ""
    echo "=== Configuration Summary ==="
    echo "Domain: $DOMAIN"
    echo "Email: $EMAIL"
    echo "Nginx config: /etc/nginx/sites-available/dashboard"
    echo "SSL certificates: /etc/letsencrypt/live/$DOMAIN/"
    echo ""
    echo "=== URLs ==="
    echo "HTTP: http://$DOMAIN"
    echo "HTTPS: https://$DOMAIN"
    echo "Dashboard: https://$DOMAIN"
    echo "Health check: https://$DOMAIN/health"
    echo ""
    echo "=== Management Commands ==="
    echo "Test config: nginx -t"
    echo "Reload nginx: systemctl reload nginx"
    echo "Restart nginx: systemctl restart nginx"
    echo "Check status: systemctl status nginx"
    echo "View logs: tail -f /var/log/nginx/dashboard_access.log"
    echo "Renew SSL: certbot renew --nginx"
    echo ""
    echo "=== Next Steps ==="
    echo "1. Update DNS records to point $DOMAIN to this server"
    echo "2. Ensure the dashboard service is running on port 5000"
    echo "3. Test the configuration: curl -I https://$DOMAIN"
    echo "4. Monitor logs and certificate expiry"
}

# Main function
main() {
    log_info "Setting up nginx for Cold Email Dashboard..."
    log_info "Domain: $DOMAIN"
    log_info "Email: $EMAIL"
    
    check_root
    install_nginx
    install_certbot
    configure_firewall
    backup_nginx_config
    setup_ssl_directories
    create_temporary_ssl
    install_nginx_config
    test_nginx_config
    
    # Start nginx with temporary config
    systemctl reload nginx
    
    # Try to get SSL certificate
    obtain_ssl_certificate
    
    # Set up additional features
    setup_cert_renewal
    create_monitoring_script
    setup_log_rotation
    
    show_summary
    
    log_success "Nginx setup completed!"
}

# Parse command line arguments
if [[ $# -eq 0 ]]; then
    echo "Usage: $0 <domain> [email]"
    echo "Example: $0 dashboard.example.com admin@example.com"
    exit 1
fi

main