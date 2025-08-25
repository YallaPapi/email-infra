#!/bin/bash

# Mailcow API Authentication Setup
# Handles API key generation, validation, and access control
# Usage: ./setup-api.sh [action] [options]

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/../config"
MAILCOW_DIR="/opt/mailcow-dockerized"
LOG_FILE="/var/log/mailcow-api-setup.log"

# API Configuration
API_CONFIG_FILE="$CONFIG_DIR/api-config.yaml"
API_KEY_FILE="$CONFIG_DIR/api_key"
API_PERMISSIONS_FILE="$CONFIG_DIR/api_permissions.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
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

# Generate secure API key
generate_api_key() {
    local key_length="${1:-32}"
    local key_type="${2:-base64}"
    
    case "$key_type" in
        "base64")
            openssl rand -base64 "$key_length" | tr -d "=+/" | cut -c1-"$key_length"
            ;;
        "hex")
            openssl rand -hex "$key_length"
            ;;
        "uuid")
            uuidgen
            ;;
        *)
            openssl rand -base64 "$key_length" | tr -d "=+/" | cut -c1-"$key_length"
            ;;
    esac
}

# Create API configuration
create_api_config() {
    log "Creating API configuration..."
    
    mkdir -p "$CONFIG_DIR"
    
    # Generate secure API key
    local api_key=$(generate_api_key 48 "base64")
    
    # Create API configuration file
    cat > "$API_CONFIG_FILE" << EOF
# Mailcow API Configuration
# Generated: $(date)

api:
  # Main API key for administrative access
  key: "$api_key"
  
  # API endpoint configuration
  endpoint: "https://{{MAILCOW_HOSTNAME}}/api/v1"
  
  # Rate limiting
  rate_limit:
    enabled: true
    requests_per_minute: 100
    burst_limit: 10
    
  # Access control
  access_control:
    # Allow access from these IP addresses/networks (CIDR notation)
    allowed_networks:
      - "127.0.0.1/32"
      - "10.0.0.0/8"
      - "172.16.0.0/12"
      - "192.168.0.0/16"
    
    # Deny access from these networks
    denied_networks: []
    
    # Require HTTPS
    require_https: true
    
    # Enable CORS
    cors_enabled: false
    cors_origins: []
  
  # Security settings
  security:
    # Enable API request logging
    enable_logging: true
    
    # Log sensitive data (not recommended for production)
    log_sensitive_data: false
    
    # Enable request signing (additional security layer)
    enable_request_signing: false
    signing_secret: "$(generate_api_key 32 hex)"
    
    # Session settings
    session_timeout: 3600
    max_concurrent_sessions: 5
    
  # Feature permissions
  permissions:
    # Domain management
    domain_read: true
    domain_write: true
    domain_delete: true
    
    # Mailbox management
    mailbox_read: true
    mailbox_write: true
    mailbox_delete: true
    
    # Alias management
    alias_read: true
    alias_write: true
    alias_delete: true
    
    # DKIM management
    dkim_read: true
    dkim_write: true
    dkim_delete: true
    
    # System administration
    system_read: true
    system_write: false
    system_restart: false
    
    # Queue management
    queue_read: true
    queue_write: true
    
    # Log access
    logs_read: true
    
    # Backup operations
    backup_create: true
    backup_restore: false

# Additional API keys for specific purposes
additional_keys:
  # Read-only key for monitoring
  readonly:
    key: "$(generate_api_key 32 base64)"
    description: "Read-only access for monitoring"
    permissions:
      domain_read: true
      mailbox_read: true
      system_read: true
      logs_read: true
      queue_read: true
    expires: ""
    
  # Limited key for web interface
  webapp:
    key: "$(generate_api_key 32 base64)"
    description: "Limited access for web application"
    permissions:
      domain_read: true
      domain_write: true
      mailbox_read: true
      mailbox_write: true
      alias_read: true
      alias_write: true
    expires: ""
    
  # Backup key
  backup:
    key: "$(generate_api_key 32 base64)"
    description: "Access for backup operations"
    permissions:
      domain_read: true
      mailbox_read: true
      backup_create: true
    expires: ""

# Webhook configuration
webhooks:
  enabled: false
  endpoints: []
  # Example webhook:
  # - url: "https://example.com/webhook"
  #   events: ["domain.created", "mailbox.created", "mailbox.deleted"]
  #   secret: "webhook_secret_key"
  #   active: true

EOF
    
    chmod 600 "$API_CONFIG_FILE"
    info "API configuration created: $API_CONFIG_FILE"
    
    # Save main API key separately for scripts
    echo "export MAILCOW_API_KEY='$api_key'" > "$API_KEY_FILE"
    chmod 600 "$API_KEY_FILE"
    
    # Extract and save hostname
    local hostname=""
    if [[ -f "$CONFIG_DIR/admin_credentials" ]]; then
        hostname=$(grep "^DOMAIN=" "$CONFIG_DIR/admin_credentials" 2>/dev/null | cut -d'=' -f2 || echo "localhost")
    fi
    
    if [[ -n "$hostname" ]]; then
        sed -i "s/{{MAILCOW_HOSTNAME}}/$hostname/g" "$API_CONFIG_FILE"
    fi
    
    log "API key generated and saved"
    return 0
}

# Configure API in Mailcow
configure_mailcow_api() {
    log "Configuring Mailcow API..."
    
    cd "$MAILCOW_DIR"
    
    # Check if Mailcow is running
    if ! docker-compose ps | grep -q "Up"; then
        error "Mailcow is not running. Start it first."
    fi
    
    # Load API key
    if [[ -f "$API_KEY_FILE" ]]; then
        source "$API_KEY_FILE"
    else
        error "API key not found. Generate configuration first."
    fi
    
    # Update mailcow.conf with API key
    if [[ -f "mailcow.conf" ]]; then
        # Check if API key already exists in config
        if grep -q "MAILCOW_API_KEY=" mailcow.conf; then
            sed -i "s/^MAILCOW_API_KEY=.*/MAILCOW_API_KEY=$MAILCOW_API_KEY/" mailcow.conf
        else
            echo "MAILCOW_API_KEY=$MAILCOW_API_KEY" >> mailcow.conf
        fi
        
        info "API key added to mailcow.conf"
    else
        error "mailcow.conf not found in $MAILCOW_DIR"
    fi
    
    # Configure API access control
    configure_api_access_control
    
    # Restart necessary containers
    log "Restarting Mailcow containers to apply API configuration..."
    docker-compose restart nginx-mailcow php-fpm-mailcow
    
    # Wait for services to be ready
    sleep 10
    
    # Test API access
    test_api_access
    
    log "Mailcow API configuration completed"
}

# Configure API access control
configure_api_access_control() {
    log "Configuring API access control..."
    
    cd "$MAILCOW_DIR"
    
    # Create custom nginx configuration for API access control
    mkdir -p data/conf/nginx
    
    cat > data/conf/nginx/api_access.conf << 'EOF'
# API Access Control Configuration
# This file is managed by the API setup script

# Rate limiting for API endpoints
limit_req_zone $binary_remote_addr zone=api_limit:10m rate=60r/m;
limit_req_zone $binary_remote_addr zone=api_burst:10m rate=10r/s;

# API endpoint configuration
location /api/ {
    # Rate limiting
    limit_req zone=api_limit burst=10 nodelay;
    limit_req zone=api_burst burst=5 nodelay;
    
    # Access control based on IP
    include /etc/nginx/conf.d/api_allowed_ips.conf;
    
    # Security headers for API
    add_header X-API-Version "v1" always;
    add_header X-Rate-Limit "60 requests per minute" always;
    
    # CORS headers (if enabled)
    # add_header Access-Control-Allow-Origin "*" always;
    # add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS" always;
    # add_header Access-Control-Allow-Headers "Authorization, Content-Type, X-API-Key" always;
    
    # Handle OPTIONS requests for CORS
    if ($request_method = 'OPTIONS') {
        add_header Access-Control-Allow-Origin "*";
        add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS";
        add_header Access-Control-Allow-Headers "Authorization, Content-Type, X-API-Key";
        add_header Access-Control-Max-Age 1728000;
        add_header Content-Type "text/plain; charset=utf-8";
        add_header Content-Length 0;
        return 204;
    }
    
    # Pass to PHP-FPM
    try_files $uri $uri/ /index.php$is_args$args;
}

# API documentation endpoint
location /api-docs/ {
    # Less restrictive rate limiting for documentation
    limit_req zone=api_limit burst=20 nodelay;
    
    # Allow access to API documentation
    try_files $uri $uri/ /api-docs/index.html;
}
EOF
    
    # Create allowed IPs configuration
    create_api_ip_whitelist
    
    info "API access control configured"
}

# Create API IP whitelist
create_api_ip_whitelist() {
    cd "$MAILCOW_DIR"
    mkdir -p data/conf/nginx
    
    cat > data/conf/nginx/api_allowed_ips.conf << 'EOF'
# API IP Whitelist Configuration
# Add allowed IP addresses and networks here

# Allow localhost
allow 127.0.0.1;
allow ::1;

# Allow private networks (adjust as needed)
allow 10.0.0.0/8;
allow 172.16.0.0/12;
allow 192.168.0.0/16;

# Allow specific IPs (uncomment and modify as needed)
# allow 203.0.113.1;
# allow 198.51.100.0/24;

# Deny all others
# deny all;
EOF
    
    info "API IP whitelist created"
}

# Test API access
test_api_access() {
    log "Testing API access..."
    
    if [[ -f "$API_KEY_FILE" ]]; then
        source "$API_KEY_FILE"
    else
        error "API key not found"
    fi
    
    local hostname=""
    if [[ -f "$CONFIG_DIR/admin_credentials" ]]; then
        hostname=$(grep "^DOMAIN=" "$CONFIG_DIR/admin_credentials" 2>/dev/null | cut -d'=' -f2 || echo "localhost")
    fi
    
    if [[ -z "$hostname" ]]; then
        hostname="localhost"
    fi
    
    # Test API endpoint
    local api_url="https://$hostname/api/v1/get/status/containers"
    
    log "Testing API endpoint: $api_url"
    
    # Test with curl
    local response=$(curl -k -s -w "%{http_code}" \
        -H "X-API-Key: $MAILCOW_API_KEY" \
        -H "Content-Type: application/json" \
        "$api_url" 2>/dev/null)
    
    local http_code="${response: -3}"
    local response_body="${response%???}"
    
    case "$http_code" in
        "200")
            info "✓ API test successful (HTTP $http_code)"
            info "API is accessible and responding correctly"
            ;;
        "401")
            warning "✗ API test failed: Unauthorized (HTTP $http_code)"
            warning "Check API key configuration"
            ;;
        "403")
            warning "✗ API test failed: Forbidden (HTTP $http_code)"
            warning "Check IP whitelist configuration"
            ;;
        "404")
            warning "✗ API test failed: Not Found (HTTP $http_code)"
            warning "API endpoint may not be available"
            ;;
        "000")
            warning "✗ API test failed: Connection error"
            warning "Check if Mailcow is running and accessible"
            ;;
        *)
            warning "✗ API test failed: HTTP $http_code"
            warning "Response: $response_body"
            ;;
    esac
}

# List API keys
list_api_keys() {
    log "Listing API keys..."
    
    if [[ ! -f "$API_CONFIG_FILE" ]]; then
        error "API configuration not found. Run setup first."
    fi
    
    echo ""
    echo "${BLUE}Mailcow API Keys:${NC}"
    echo "=================="
    echo ""
    
    # Parse YAML configuration (basic parsing)
    local current_key=""
    local current_desc=""
    local in_additional_keys=false
    
    while IFS= read -r line; do
        # Remove leading whitespace
        line=$(echo "$line" | sed 's/^[[:space:]]*//')
        
        # Skip comments and empty lines
        [[ -z "$line" || "$line" =~ ^#.*$ ]] && continue
        
        if [[ "$line" == "additional_keys:" ]]; then
            in_additional_keys=true
            continue
        fi
        
        if [[ "$in_additional_keys" == "true" ]]; then
            if [[ "$line" =~ ^([a-z_]+):$ ]]; then
                current_key="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ ^key:\ \"(.+)\"$ ]]; then
                local key_value="${BASH_REMATCH[1]}"
                printf "%-15s %s\n" "$current_key" "${key_value:0:20}..."
            elif [[ "$line" =~ ^description:\ \"(.+)\"$ ]]; then
                current_desc="${BASH_REMATCH[1]}"
                printf "%-15s %s\n" "" "Description: $current_desc"
                echo ""
            fi
        fi
        
        # Stop at next major section
        if [[ "$line" =~ ^[a-z_]+:$ && "$line" != *"additional_keys:"* && "$in_additional_keys" == "true" ]]; then
            break
        fi
        
    done < "$API_CONFIG_FILE"
    
    # Show main API key
    if [[ -f "$API_KEY_FILE" ]]; then
        source "$API_KEY_FILE"
        echo "Main API Key: ${MAILCOW_API_KEY:0:20}..."
        echo ""
    fi
}

# Generate new API key
generate_new_key() {
    local key_type="${1:-additional}"
    local key_name="${2:-custom}"
    local description="${3:-Custom API key}"
    
    log "Generating new API key: $key_name"
    
    if [[ ! -f "$API_CONFIG_FILE" ]]; then
        error "API configuration not found. Run setup first."
    fi
    
    local new_key=$(generate_api_key 32 "base64")
    
    # Add new key to configuration
    local temp_file=$(mktemp)
    local in_additional_keys=false
    local added=false
    
    while IFS= read -r line; do
        echo "$line" >> "$temp_file"
        
        if [[ "$line" == "additional_keys:" ]]; then
            in_additional_keys=true
        fi
        
        # Add new key after the additional_keys section starts
        if [[ "$in_additional_keys" == "true" && ! "$added" && "$line" =~ ^[[:space:]]*[a-z_]+:$ ]]; then
            cat >> "$temp_file" << EOF
  
  # Custom generated key
  $key_name:
    key: "$new_key"
    description: "$description"
    permissions:
      domain_read: true
      mailbox_read: true
      system_read: true
    expires: ""
EOF
            added=true
        fi
    done < "$API_CONFIG_FILE"
    
    mv "$temp_file" "$API_CONFIG_FILE"
    chmod 600 "$API_CONFIG_FILE"
    
    info "New API key generated: $key_name"
    echo ""
    echo "Key: $new_key"
    echo "Description: $description"
    echo ""
    warning "Save this key securely - it won't be shown again in plain text"
}

# Revoke API key
revoke_api_key() {
    local key_name="$1"
    
    if [[ -z "$key_name" ]]; then
        error "Key name is required"
    fi
    
    log "Revoking API key: $key_name"
    
    if [[ ! -f "$API_CONFIG_FILE" ]]; then
        error "API configuration not found"
    fi
    
    # Remove key from configuration
    local temp_file=$(mktemp)
    local in_key_section=false
    local skip_lines=false
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*$key_name:$ ]]; then
            in_key_section=true
            skip_lines=true
            continue
        fi
        
        if [[ "$skip_lines" == "true" ]]; then
            # Skip lines until next key or section
            if [[ "$line" =~ ^[[:space:]]*[a-z_]+:$ ]] && [[ ! "$line" =~ ^[[:space:]]{4,} ]]; then
                skip_lines=false
                in_key_section=false
            else
                continue
            fi
        fi
        
        echo "$line" >> "$temp_file"
    done < "$API_CONFIG_FILE"
    
    mv "$temp_file" "$API_CONFIG_FILE"
    chmod 600 "$API_CONFIG_FILE"
    
    info "API key revoked: $key_name"
}

# Update IP whitelist
update_ip_whitelist() {
    local action="$1"
    local ip_address="$2"
    
    if [[ -z "$action" || -z "$ip_address" ]]; then
        error "Action and IP address are required"
    fi
    
    log "Updating IP whitelist: $action $ip_address"
    
    cd "$MAILCOW_DIR"
    
    local whitelist_file="data/conf/nginx/api_allowed_ips.conf"
    
    if [[ ! -f "$whitelist_file" ]]; then
        create_api_ip_whitelist
    fi
    
    case "$action" in
        "add")
            # Add IP to whitelist
            if grep -q "$ip_address" "$whitelist_file"; then
                warning "IP address $ip_address already in whitelist"
            else
                sed -i "/# Allow specific IPs/a allow $ip_address;" "$whitelist_file"
                info "Added $ip_address to API whitelist"
            fi
            ;;
        "remove")
            # Remove IP from whitelist
            sed -i "/allow $ip_address;/d" "$whitelist_file"
            info "Removed $ip_address from API whitelist"
            ;;
        *)
            error "Invalid action: $action. Use 'add' or 'remove'"
            ;;
    esac
    
    # Restart nginx to apply changes
    docker-compose restart nginx-mailcow
    
    log "IP whitelist updated and nginx restarted"
}

# Create API documentation
create_api_documentation() {
    log "Creating API documentation..."
    
    mkdir -p "$CONFIG_DIR/docs"
    
    cat > "$CONFIG_DIR/docs/api-usage.md" << 'EOF'
# Mailcow API Usage Guide

## Authentication

All API requests require authentication using an API key in the header:

```bash
curl -X GET \
  -H "X-API-Key: YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  "https://your-mailcow-host/api/v1/endpoint"
```

## Available Endpoints

### Domain Management

#### List Domains
```bash
GET /api/v1/get/domain/all
```

#### Add Domain
```bash
POST /api/v1/add/domain
Content-Type: application/json

{
  "domain": "example.com",
  "description": "Example domain",
  "aliases": 400,
  "mailboxes": 10,
  "quota": 3072,
  "active": 1
}
```

#### Update Domain
```bash
POST /api/v1/edit/domain
Content-Type: application/json

{
  "items": ["example.com"],
  "attr": {
    "quota": 5120,
    "active": 1
  }
}
```

#### Delete Domain
```bash
POST /api/v1/delete/domain
Content-Type: application/json

["example.com"]
```

### Mailbox Management

#### List Mailboxes
```bash
GET /api/v1/get/mailbox/all
GET /api/v1/get/mailbox/domain.com
```

#### Add Mailbox
```bash
POST /api/v1/add/mailbox
Content-Type: application/json

{
  "local_part": "user",
  "domain": "example.com",
  "password": "secure_password",
  "password2": "secure_password",
  "name": "User Name",
  "quota": 1024,
  "active": 1
}
```

#### Update Mailbox
```bash
POST /api/v1/edit/mailbox
Content-Type: application/json

{
  "items": ["user@example.com"],
  "attr": {
    "quota": 2048,
    "active": 1
  }
}
```

#### Delete Mailbox
```bash
POST /api/v1/delete/mailbox
Content-Type: application/json

["user@example.com"]
```

### DKIM Management

#### Get DKIM Key
```bash
GET /api/v1/get/dkim/example.com
```

#### Generate DKIM Key
```bash
POST /api/v1/add/dkim
Content-Type: application/json

{
  "domains": ["example.com"],
  "key_size": 2048,
  "selector": "dkim"
}
```

#### Delete DKIM Key
```bash
POST /api/v1/delete/dkim
Content-Type: application/json

["example.com"]
```

### System Information

#### Get Container Status
```bash
GET /api/v1/get/status/containers
```

#### Get Version Information
```bash
GET /api/v1/get/status/version
```

### Queue Management

#### Get Mail Queue
```bash
GET /api/v1/get/mailq/all
```

#### Flush Mail Queue
```bash
POST /api/v1/edit/mailq
Content-Type: application/json

{
  "action": "flush"
}
```

## Error Handling

The API returns standard HTTP status codes:

- 200: Success
- 400: Bad Request
- 401: Unauthorized (invalid API key)
- 403: Forbidden (insufficient permissions)
- 404: Not Found
- 429: Too Many Requests (rate limited)
- 500: Internal Server Error

Error responses include details:

```json
{
  "type": "error",
  "message": "Error description"
}
```

## Rate Limiting

The API is rate limited to prevent abuse:
- 60 requests per minute per IP address
- Burst limit of 10 requests per second

Rate limit headers are included in responses:
- X-Rate-Limit: Current limit
- X-Rate-Limit-Remaining: Requests remaining
- X-Rate-Limit-Reset: Time when limit resets

## Best Practices

1. **Secure Storage**: Store API keys securely, never in code or version control
2. **HTTPS Only**: Always use HTTPS for API requests
3. **Error Handling**: Implement proper error handling and retry logic
4. **Rate Limiting**: Respect rate limits and implement backoff strategies
5. **Minimal Permissions**: Use API keys with minimal required permissions
6. **Regular Rotation**: Rotate API keys regularly for security

EOF
    
    info "API documentation created: $CONFIG_DIR/docs/api-usage.md"
}

# Show usage
show_usage() {
    cat << EOF
Mailcow API Authentication Setup

Usage: $0 [action] [options]

Actions:
  setup
    Create initial API configuration and keys
    
  configure
    Configure Mailcow with API settings
    
  test
    Test API access and connectivity
    
  list-keys
    List all configured API keys
    
  generate-key <name> [description]
    Generate a new API key
    
  revoke-key <name>
    Revoke an existing API key
    
  whitelist-ip <add|remove> <ip_address>
    Add or remove IP from API whitelist
    
  docs
    Generate API documentation

Options:
  --help          Show this help message

Examples:
  $0 setup
  $0 configure
  $0 test
  $0 list-keys
  $0 generate-key monitoring "Read-only monitoring access"
  $0 revoke-key oldkey
  $0 whitelist-ip add 203.0.113.1
  $0 docs

Configuration files:
  - Main config: $API_CONFIG_FILE
  - API key: $API_KEY_FILE
  - Permissions: $API_PERMISSIONS_FILE

EOF
}

# Main function
main() {
    local action="$1"
    shift
    
    case "$action" in
        "setup")
            create_api_config
            ;;
        "configure")
            configure_mailcow_api
            ;;
        "test")
            test_api_access
            ;;
        "list-keys")
            list_api_keys
            ;;
        "generate-key")
            generate_new_key "additional" "$1" "$2"
            ;;
        "revoke-key")
            revoke_api_key "$1"
            ;;
        "whitelist-ip")
            update_ip_whitelist "$1" "$2"
            ;;
        "docs")
            create_api_documentation
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