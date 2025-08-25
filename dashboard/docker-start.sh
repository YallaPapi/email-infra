#!/bin/bash

# Docker Quick Start Script for Cold Email Dashboard
set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="cold-email-dashboard"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if Docker is installed and running
check_docker() {
    log_info "Checking Docker installation..."
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        log_error "Docker is not running. Please start Docker service."
        exit 1
    fi
    
    log_success "Docker is available and running"
}

# Check if Docker Compose is installed
check_docker_compose() {
    log_info "Checking Docker Compose installation..."
    
    if command -v docker-compose &> /dev/null; then
        COMPOSE_CMD="docker-compose"
    elif docker compose version &> /dev/null; then
        COMPOSE_CMD="docker compose"
    else
        log_error "Docker Compose is not installed. Please install Docker Compose."
        exit 1
    fi
    
    log_success "Docker Compose is available: $COMPOSE_CMD"
}

# Create environment file if it doesn't exist
setup_environment() {
    log_info "Setting up environment configuration..."
    
    if [[ ! -f "$SCRIPT_DIR/.env" ]]; then
        log_warning ".env file not found. Creating from example..."
        cp "$SCRIPT_DIR/.env.example" "$SCRIPT_DIR/.env"
        log_warning "Please edit .env file with your configuration before running in production"
    fi
    
    log_success "Environment configuration ready"
}

# Create nginx directory and config
setup_nginx() {
    log_info "Setting up Nginx configuration..."
    
    mkdir -p "$SCRIPT_DIR/nginx/ssl"
    
    if [[ ! -f "$SCRIPT_DIR/nginx/nginx.conf" ]]; then
        cat > "$SCRIPT_DIR/nginx/nginx.conf" << 'EOF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
    use epoll;
    multi_accept on;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    server_tokens off;

    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types
        text/plain
        text/css
        text/xml
        text/javascript
        application/json
        application/javascript
        application/xml+rss
        application/atom+xml
        image/svg+xml;

    include /etc/nginx/conf.d/*.conf;
}
EOF
    fi
    
    if [[ ! -f "$SCRIPT_DIR/nginx/dashboard.conf" ]]; then
        cat > "$SCRIPT_DIR/nginx/dashboard.conf" << 'EOF'
# Health check endpoint
server {
    listen 80;
    server_name _;
    
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
    
    location / {
        return 301 https://$host$request_uri;
    }
}

# Main dashboard proxy
server {
    listen 80;
    server_name localhost;

    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Referrer-Policy "strict-origin-when-cross-origin";

    # Proxy to Flask app
    location / {
        proxy_pass http://dashboard:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_redirect off;
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # Buffer settings
        proxy_buffer_size 4k;
        proxy_buffers 8 4k;
        proxy_busy_buffers_size 8k;
    }

    # Static files
    location /static {
        proxy_pass http://dashboard:5000;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
EOF
    fi
    
    log_success "Nginx configuration created"
}

# Build and start containers
start_containers() {
    log_info "Building and starting containers..."
    
    cd "$SCRIPT_DIR"
    
    # Pull latest images
    $COMPOSE_CMD pull
    
    # Build the dashboard image
    $COMPOSE_CMD build dashboard
    
    # Start services
    $COMPOSE_CMD up -d
    
    log_success "Containers started"
}

# Wait for services to be ready
wait_for_services() {
    log_info "Waiting for services to be ready..."
    
    # Wait for dashboard
    max_attempts=30
    attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        if curl -s -f http://localhost:5000/api/health > /dev/null 2>&1; then
            log_success "Dashboard is ready"
            break
        fi
        
        ((attempt++))
        log_info "Waiting for dashboard... ($attempt/$max_attempts)"
        sleep 2
    done
    
    if [[ $attempt -eq $max_attempts ]]; then
        log_error "Dashboard failed to start within expected time"
        log_info "Checking container logs..."
        $COMPOSE_CMD logs dashboard
        exit 1
    fi
    
    # Wait for nginx
    if curl -s -f http://localhost/health > /dev/null 2>&1; then
        log_success "Nginx proxy is ready"
    else
        log_warning "Nginx proxy may not be ready yet"
    fi
}

# Display status and access information
show_status() {
    log_success "Cold Email Dashboard is running!"
    
    echo ""
    echo "=== Access Information ==="
    echo "Dashboard (direct): http://localhost:5000"
    echo "Dashboard (via proxy): http://localhost"
    echo "Health Check: http://localhost:5000/api/health"
    echo ""
    
    echo "=== Container Status ==="
    $COMPOSE_CMD ps
    echo ""
    
    echo "=== Useful Commands ==="
    echo "View logs: $COMPOSE_CMD logs -f"
    echo "Stop services: $COMPOSE_CMD down"
    echo "Restart services: $COMPOSE_CMD restart"
    echo "Update services: $COMPOSE_CMD pull && $COMPOSE_CMD up -d"
    echo ""
    
    log_warning "For production deployment:"
    log_warning "1. Edit .env file with your actual configuration"
    log_warning "2. Set up SSL certificates"
    log_warning "3. Configure proper domain name"
    log_warning "4. Set up monitoring and backups"
}

# Main execution
main() {
    log_info "Starting Cold Email Dashboard with Docker..."
    
    check_docker
    check_docker_compose
    setup_environment
    setup_nginx
    start_containers
    wait_for_services
    show_status
}

# Parse command line arguments
case "${1:-start}" in
    start)
        main
        ;;
    stop)
        log_info "Stopping services..."
        $COMPOSE_CMD down
        log_success "Services stopped"
        ;;
    restart)
        log_info "Restarting services..."
        $COMPOSE_CMD restart
        log_success "Services restarted"
        ;;
    logs)
        $COMPOSE_CMD logs -f
        ;;
    status)
        $COMPOSE_CMD ps
        ;;
    update)
        log_info "Updating services..."
        $COMPOSE_CMD pull
        $COMPOSE_CMD up -d
        log_success "Services updated"
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|logs|status|update}"
        echo "  start   - Start all services (default)"
        echo "  stop    - Stop all services"
        echo "  restart - Restart all services"
        echo "  logs    - View live logs"
        echo "  status  - Show container status"
        echo "  update  - Update and restart services"
        exit 1
        ;;
esac