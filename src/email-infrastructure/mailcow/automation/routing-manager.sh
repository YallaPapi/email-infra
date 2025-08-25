#!/bin/bash

# Mailcow Mail Routing Rules Manager
# Handles mail routing, transport maps, and delivery rules
# Usage: ./routing-manager.sh [action] [options]

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/../config"
MAILCOW_DIR="/opt/mailcow-dockerized"
ROUTING_CONFIG_DIR="$CONFIG_DIR/routing"
LOG_FILE="/var/log/mailcow-routing-manager.log"

# Postfix configuration paths
POSTFIX_CONFIG_DIR="$MAILCOW_DIR/data/conf/postfix"
TRANSPORT_MAPS="$POSTFIX_CONFIG_DIR/transport_maps"
SENDER_DEPENDENT_TRANSPORT="$POSTFIX_CONFIG_DIR/sender_dependent_default_transport_maps"
ROUTING_RULES="$POSTFIX_CONFIG_DIR/routing_rules"

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

# Load configuration
load_config() {
    if [[ -f "$CONFIG_DIR/admin_credentials" ]]; then
        source "$CONFIG_DIR/admin_credentials"
    else
        warning "Admin credentials not found"
    fi
    
    # Create routing configuration directory
    mkdir -p "$ROUTING_CONFIG_DIR" "$POSTFIX_CONFIG_DIR"
    
    # Load routing configuration if available
    if [[ -f "$ROUTING_CONFIG_DIR/routing.conf" ]]; then
        source "$ROUTING_CONFIG_DIR/routing.conf"
    else
        create_routing_config
    fi
}

# Create routing configuration
create_routing_config() {
    log "Creating routing configuration..."
    
    mkdir -p "$ROUTING_CONFIG_DIR"
    
    cat > "$ROUTING_CONFIG_DIR/routing.conf" << EOF
# Mail Routing Configuration
# Generated: $(date)

# Default transport method
DEFAULT_TRANSPORT="smtp"

# Relay configuration
RELAY_ENABLED=false
RELAY_HOST=""
RELAY_PORT=587
RELAY_USERNAME=""
RELAY_PASSWORD=""
RELAY_USE_TLS=true

# Route specific domains through different transports
DOMAIN_ROUTING_ENABLED=true

# Sender-dependent routing
SENDER_ROUTING_ENABLED=false

# Rate limiting
RATE_LIMITING_ENABLED=true
DEFAULT_RATE_LIMIT="100/hour"

# Backup MX configuration
BACKUP_MX_ENABLED=false
BACKUP_MX_DOMAINS=""

# Advanced routing options
CONTENT_FILTER_ENABLED=false
CONTENT_FILTER_TRANSPORT=""

# Routing rules file
ROUTING_RULES_FILE="$ROUTING_CONFIG_DIR/routing_rules.txt"

# Transport maps file
TRANSPORT_MAPS_FILE="$ROUTING_CONFIG_DIR/transport_maps.txt"
EOF
    
    chmod 600 "$ROUTING_CONFIG_DIR/routing.conf"
    info "Routing configuration created: $ROUTING_CONFIG_DIR/routing.conf"
}

# Initialize routing system
initialize_routing() {
    log "Initializing mail routing system..."
    
    cd "$MAILCOW_DIR"
    
    # Check if Postfix container is running
    if ! docker-compose ps | grep -q "postfix-mailcow.*Up"; then
        error "Postfix container is not running"
    fi
    
    # Create Postfix configuration directories
    mkdir -p "$POSTFIX_CONFIG_DIR"
    
    # Initialize transport maps
    create_default_transport_maps
    
    # Initialize routing rules
    create_default_routing_rules
    
    # Initialize sender-dependent transport
    create_sender_dependent_transport
    
    # Update Postfix main configuration
    update_postfix_main_config
    
    # Reload Postfix configuration
    reload_postfix_config
    
    log "Mail routing system initialized"
}

# Create default transport maps
create_default_transport_maps() {
    log "Creating default transport maps..."
    
    cat > "$TRANSPORT_MAPS" << 'EOF'
# Transport Maps Configuration
# Format: pattern transport:nexthop
# 
# Examples:
# example.com smtp:mail.example.com:587
# .backup.com relay:[backup-mx.example.com]:25
# user@special.com smtp:special-relay.example.com:465

# Default entries (uncomment and modify as needed)
# .example.com smtp:relay.example.com:587
EOF
    
    # Create hash database
    docker-compose exec -T postfix-mailcow postmap /opt/postfix/conf/transport_maps
    
    info "Default transport maps created"
}

# Create default routing rules
create_default_routing_rules() {
    log "Creating default routing rules..."
    
    cat > "$ROUTING_RULES" << 'EOF'
# Mail Routing Rules Configuration
# This file defines custom routing rules for different scenarios

# Rate limiting rules
# Format: pattern rate_limit
# example.com 50/hour
# .bulk.com 10/minute

# Content filtering rules  
# Format: pattern content_filter
# spam.com filter:spamassassin
# .marketing.com filter:content-filter

# Backup MX rules
# Format: pattern backup_mx_priority
# .backup.example.com 10

# Custom routing rules can be added here
EOF
    
    info "Default routing rules created"
}

# Create sender-dependent transport
create_sender_dependent_transport() {
    log "Creating sender-dependent transport maps..."
    
    cat > "$SENDER_DEPENDENT_TRANSPORT" << 'EOF'
# Sender Dependent Default Transport Maps
# Format: sender_pattern transport:nexthop
#
# Route emails from specific senders through different transports
# Examples:
# marketing@example.com smtp:bulk-relay.example.com:587
# support@example.com smtp:priority-relay.example.com:587
# @newsletter.example.com smtp:newsletter-relay.example.com:587

# Default entries (uncomment and modify as needed)
EOF
    
    # Create hash database
    docker-compose exec -T postfix-mailcow postmap /opt/postfix/conf/sender_dependent_default_transport_maps 2>/dev/null || true
    
    info "Sender-dependent transport maps created"
}

# Update Postfix main configuration
update_postfix_main_config() {
    log "Updating Postfix main configuration..."
    
    cd "$MAILCOW_DIR"
    
    # Create custom Postfix configuration
    mkdir -p data/conf/postfix
    
    cat > data/conf/postfix/extra_main.cf << EOF
# Custom Mail Routing Configuration
# Generated by routing-manager.sh

# Transport maps
transport_maps = hash:/opt/postfix/conf/transport_maps

# Sender-dependent transport (uncomment if using)
# sender_dependent_default_transport_maps = hash:/opt/postfix/conf/sender_dependent_default_transport_maps

# Rate limiting (if enabled)
anvil_rate_time_unit = 60s
anvil_status_update_time = 600s

# Additional routing settings
default_transport = smtp
relay_transport = relay

# Custom header checks (for routing based on headers)
# header_checks = regexp:/opt/postfix/conf/header_checks

# Custom body checks (for content-based routing)
# body_checks = regexp:/opt/postfix/conf/body_checks

# Milter settings (for advanced content filtering)
# milter_default_action = accept
# milter_protocol = 6

# Backup MX settings (if enabled)
# relay_domains = \$mydestination, hash:/opt/postfix/conf/relay_domains

EOF
    
    info "Postfix main configuration updated"
}

# Add transport rule
add_transport_rule() {
    local pattern="$1"
    local transport="$2"
    local nexthop="$3"
    local description="${4:-Custom transport rule}"
    
    if [[ -z "$pattern" || -z "$transport" ]]; then
        error "Pattern and transport are required"
    fi
    
    log "Adding transport rule: $pattern -> $transport:$nexthop"
    
    # Validate pattern format
    if ! [[ "$pattern" =~ ^[a-zA-Z0-9@._-]+$ ]]; then
        error "Invalid pattern format: $pattern"
    fi
    
    # Validate transport
    case "$transport" in
        "smtp"|"relay"|"local"|"virtual"|"discard"|"error")
            # Valid transport
            ;;
        *)
            warning "Unknown transport type: $transport"
            ;;
    esac
    
    # Build transport entry
    local transport_entry="$pattern"
    if [[ -n "$nexthop" ]]; then
        transport_entry="$pattern $transport:$nexthop"
    else
        transport_entry="$pattern $transport"
    fi
    
    # Add to transport maps
    if grep -q "^$pattern " "$TRANSPORT_MAPS" 2>/dev/null; then
        # Update existing entry
        sed -i "s/^$pattern .*/$transport_entry/" "$TRANSPORT_MAPS"
        info "Updated existing transport rule for $pattern"
    else
        # Add new entry
        echo "# $description" >> "$TRANSPORT_MAPS"
        echo "$transport_entry" >> "$TRANSPORT_MAPS"
        info "Added new transport rule for $pattern"
    fi
    
    # Update hash database
    rebuild_transport_maps
}

# Remove transport rule
remove_transport_rule() {
    local pattern="$1"
    
    if [[ -z "$pattern" ]]; then
        error "Pattern is required"
    fi
    
    log "Removing transport rule: $pattern"
    
    if grep -q "^$pattern " "$TRANSPORT_MAPS" 2>/dev/null; then
        # Remove the rule and its comment
        sed -i "/^# .*$pattern/d; /^$pattern /d" "$TRANSPORT_MAPS"
        info "Removed transport rule for $pattern"
        
        # Update hash database
        rebuild_transport_maps
    else
        warning "Transport rule for $pattern not found"
    fi
}

# Add sender-dependent rule
add_sender_rule() {
    local sender_pattern="$1"
    local transport="$2" 
    local nexthop="$3"
    local description="${4:-Sender-dependent routing rule}"
    
    if [[ -z "$sender_pattern" || -z "$transport" ]]; then
        error "Sender pattern and transport are required"
    fi
    
    log "Adding sender-dependent rule: $sender_pattern -> $transport:$nexthop"
    
    # Build transport entry
    local transport_entry
    if [[ -n "$nexthop" ]]; then
        transport_entry="$sender_pattern $transport:$nexthop"
    else
        transport_entry="$sender_pattern $transport"
    fi
    
    # Add to sender-dependent transport maps
    if grep -q "^$sender_pattern " "$SENDER_DEPENDENT_TRANSPORT" 2>/dev/null; then
        # Update existing entry
        sed -i "s/^$sender_pattern .*/$transport_entry/" "$SENDER_DEPENDENT_TRANSPORT"
        info "Updated existing sender rule for $sender_pattern"
    else
        # Add new entry
        echo "# $description" >> "$SENDER_DEPENDENT_TRANSPORT"
        echo "$transport_entry" >> "$SENDER_DEPENDENT_TRANSPORT"
        info "Added new sender rule for $sender_pattern"
    fi
    
    # Update hash database
    rebuild_sender_maps
    
    # Enable sender-dependent transport in main.cf if not already enabled
    enable_sender_dependent_transport
}

# Setup relay configuration
setup_relay() {
    local relay_host="$1"
    local relay_port="${2:-587}"
    local username="$3"
    local password="$4"
    local use_tls="${5:-true}"
    
    if [[ -z "$relay_host" ]]; then
        error "Relay host is required"
    fi
    
    log "Setting up relay configuration: $relay_host:$relay_port"
    
    cd "$MAILCOW_DIR"
    
    # Create SASL password map if credentials provided
    if [[ -n "$username" && -n "$password" ]]; then
        echo "[$relay_host]:$relay_port $username:$password" > data/conf/postfix/sasl_passwd
        chmod 600 data/conf/postfix/sasl_passwd
        
        # Create hash database
        docker-compose exec -T postfix-mailcow postmap /opt/postfix/conf/sasl_passwd
        
        info "SASL authentication configured"
    fi
    
    # Update main.cf with relay settings
    cat >> data/conf/postfix/extra_main.cf << EOF

# Relay configuration
relayhost = [$relay_host]:$relay_port

# SASL authentication for relay
smtp_sasl_auth_enable = yes
smtp_sasl_password_maps = hash:/opt/postfix/conf/sasl_passwd
smtp_sasl_security_options = noanonymous

# TLS configuration for relay
EOF
    
    if [[ "$use_tls" == "true" ]]; then
        cat >> data/conf/postfix/extra_main.cf << EOF
smtp_use_tls = yes
smtp_tls_security_level = encrypt
smtp_tls_note_starttls_offer = yes
smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt
EOF
    fi
    
    # Reload configuration
    reload_postfix_config
    
    info "Relay configuration completed"
}

# Configure rate limiting
setup_rate_limiting() {
    local default_limit="${1:-100/hour}"
    local enable="${2:-true}"
    
    log "Setting up rate limiting: $default_limit"
    
    cd "$MAILCOW_DIR"
    
    if [[ "$enable" == "true" ]]; then
        # Configure anvil for rate limiting
        cat >> data/conf/postfix/extra_main.cf << EOF

# Rate limiting configuration
anvil_rate_time_unit = 3600s
anvil_status_update_time = 600s

# Client connection rate limiting
smtpd_client_connection_rate_limit = 10
smtpd_client_message_rate_limit = 100
smtpd_client_recipient_rate_limit = 100
smtpd_client_event_limit_exceptions = \$mynetworks

# Policy service for rate limiting (if using external service)
# check_policy_service = inet:127.0.0.1:10030
EOF
        
        info "Rate limiting enabled with default limit: $default_limit"
    else
        info "Rate limiting disabled"
    fi
    
    reload_postfix_config
}

# List current routing rules
list_routing_rules() {
    local format="${1:-table}"
    
    log "Listing current routing rules..."
    
    case "$format" in
        "table")
            echo ""
            echo "${BLUE}Transport Maps:${NC}"
            echo "==============="
            
            if [[ -f "$TRANSPORT_MAPS" ]]; then
                while IFS= read -r line; do
                    # Skip empty lines and comments
                    [[ -z "$line" || "$line" =~ ^#.*$ ]] && continue
                    
                    echo "$line"
                done < "$TRANSPORT_MAPS"
            else
                echo "No transport maps configured"
            fi
            
            echo ""
            echo "${BLUE}Sender-Dependent Transport Maps:${NC}"
            echo "================================="
            
            if [[ -f "$SENDER_DEPENDENT_TRANSPORT" ]]; then
                local has_rules=false
                while IFS= read -r line; do
                    # Skip empty lines and comments
                    [[ -z "$line" || "$line" =~ ^#.*$ ]] && continue
                    
                    echo "$line"
                    has_rules=true
                done < "$SENDER_DEPENDENT_TRANSPORT"
                
                if [[ "$has_rules" == "false" ]]; then
                    echo "No sender-dependent rules configured"
                fi
            else
                echo "No sender-dependent transport maps configured"
            fi
            echo ""
            ;;
        "json")
            echo "{"
            echo '  "transport_maps": ['
            
            if [[ -f "$TRANSPORT_MAPS" ]]; then
                local first=true
                while IFS= read -r line; do
                    [[ -z "$line" || "$line" =~ ^#.*$ ]] && continue
                    
                    if [[ "$first" != "true" ]]; then
                        echo ","
                    fi
                    first=false
                    
                    local pattern=$(echo "$line" | awk '{print $1}')
                    local transport=$(echo "$line" | awk '{print $2}')
                    
                    echo -n "    {\"pattern\": \"$pattern\", \"transport\": \"$transport\"}"
                done < "$TRANSPORT_MAPS"
                echo ""
            fi
            
            echo '  ],'
            echo '  "sender_dependent_maps": ['
            
            if [[ -f "$SENDER_DEPENDENT_TRANSPORT" ]]; then
                local first=true
                while IFS= read -r line; do
                    [[ -z "$line" || "$line" =~ ^#.*$ ]] && continue
                    
                    if [[ "$first" != "true" ]]; then
                        echo ","
                    fi
                    first=false
                    
                    local pattern=$(echo "$line" | awk '{print $1}')
                    local transport=$(echo "$line" | awk '{print $2}')
                    
                    echo -n "    {\"sender\": \"$pattern\", \"transport\": \"$transport\"}"
                done < "$SENDER_DEPENDENT_TRANSPORT"
                echo ""
            fi
            
            echo '  ]'
            echo "}"
            ;;
    esac
}

# Test routing rules
test_routing() {
    local test_address="$1"
    local sender_address="${2:-test@localhost}"
    
    if [[ -z "$test_address" ]]; then
        error "Test address is required"
    fi
    
    log "Testing routing for: $test_address (sender: $sender_address)"
    
    cd "$MAILCOW_DIR"
    
    # Test transport lookup
    echo ""
    echo "${BLUE}Transport Lookup Test:${NC}"
    echo "======================"
    
    local transport_result=$(docker-compose exec -T postfix-mailcow postmap -q "$test_address" /opt/postfix/conf/transport_maps 2>/dev/null || echo "No specific transport")
    echo "Address: $test_address"
    echo "Transport: $transport_result"
    
    # Test sender-dependent transport
    if [[ -f "$SENDER_DEPENDENT_TRANSPORT" ]]; then
        echo ""
        echo "${BLUE}Sender-Dependent Transport Test:${NC}"
        echo "================================="
        
        local sender_transport=$(docker-compose exec -T postfix-mailcow postmap -q "$sender_address" /opt/postfix/conf/sender_dependent_default_transport_maps 2>/dev/null || echo "No sender-specific transport")
        echo "Sender: $sender_address"
        echo "Transport: $sender_transport"
    fi
    
    # Show effective routing decision
    echo ""
    echo "${BLUE}Routing Decision:${NC}"
    echo "=================="
    
    if [[ "$transport_result" != "No specific transport" ]]; then
        echo "Route: $test_address will use transport '$transport_result'"
    elif [[ "$sender_transport" != "No sender-specific transport" ]]; then
        echo "Route: Email from $sender_address will use transport '$sender_transport'"
    else
        echo "Route: $test_address will use default transport (local delivery or relay)"
    fi
}

# Rebuild transport maps databases
rebuild_transport_maps() {
    log "Rebuilding transport maps databases..."
    
    cd "$MAILCOW_DIR"
    
    # Rebuild transport maps
    if [[ -f "$TRANSPORT_MAPS" ]]; then
        docker-compose exec -T postfix-mailcow postmap /opt/postfix/conf/transport_maps
        info "Transport maps database rebuilt"
    fi
}

# Rebuild sender maps databases  
rebuild_sender_maps() {
    log "Rebuilding sender-dependent transport maps..."
    
    cd "$MAILCOW_DIR"
    
    # Rebuild sender-dependent transport maps
    if [[ -f "$SENDER_DEPENDENT_TRANSPORT" ]]; then
        docker-compose exec -T postfix-mailcow postmap /opt/postfix/conf/sender_dependent_default_transport_maps
        info "Sender-dependent transport maps database rebuilt"
    fi
}

# Enable sender-dependent transport
enable_sender_dependent_transport() {
    log "Enabling sender-dependent transport..."
    
    cd "$MAILCOW_DIR"
    
    # Check if already enabled in main.cf
    if ! grep -q "sender_dependent_default_transport_maps" data/conf/postfix/extra_main.cf 2>/dev/null; then
        echo "" >> data/conf/postfix/extra_main.cf
        echo "# Sender-dependent transport maps" >> data/conf/postfix/extra_main.cf
        echo "sender_dependent_default_transport_maps = hash:/opt/postfix/conf/sender_dependent_default_transport_maps" >> data/conf/postfix/extra_main.cf
        
        reload_postfix_config
        info "Sender-dependent transport enabled"
    else
        info "Sender-dependent transport already enabled"
    fi
}

# Reload Postfix configuration
reload_postfix_config() {
    log "Reloading Postfix configuration..."
    
    cd "$MAILCOW_DIR"
    
    # Reload Postfix
    docker-compose exec -T postfix-mailcow postfix reload
    
    # Wait a moment for reload to complete
    sleep 2
    
    info "Postfix configuration reloaded"
}

# Show routing status
show_routing_status() {
    log "Checking routing system status..."
    
    cd "$MAILCOW_DIR"
    
    echo ""
    echo "${BLUE}Postfix Configuration Status:${NC}"
    echo "============================="
    
    # Check if Postfix is running
    if docker-compose ps | grep -q "postfix-mailcow.*Up"; then
        echo "Postfix Status: Running"
    else
        echo "Postfix Status: Not Running"
        return 1
    fi
    
    # Show transport maps status
    echo ""
    echo "${BLUE}Transport Maps:${NC}"
    echo "==============="
    
    if [[ -f "$TRANSPORT_MAPS" ]]; then
        local rule_count=$(grep -c "^[^#]" "$TRANSPORT_MAPS" 2>/dev/null || echo "0")
        echo "Transport rules: $rule_count"
        echo "Database file: $(ls -la "$TRANSPORT_MAPS.db" 2>/dev/null | awk '{print $5" bytes ("$6" "$7" "$8")"}' || echo "Not found")"
    else
        echo "Transport maps: Not configured"
    fi
    
    # Show sender-dependent maps status
    echo ""
    echo "${BLUE}Sender-Dependent Transport:${NC}"
    echo "============================"
    
    if [[ -f "$SENDER_DEPENDENT_TRANSPORT" ]]; then
        local sender_rule_count=$(grep -c "^[^#]" "$SENDER_DEPENDENT_TRANSPORT" 2>/dev/null || echo "0")
        echo "Sender rules: $sender_rule_count"
        echo "Database file: $(ls -la "$SENDER_DEPENDENT_TRANSPORT.db" 2>/dev/null | awk '{print $5" bytes ("$6" "$7" "$8")"}' || echo "Not found")"
    else
        echo "Sender-dependent transport: Not configured"
    fi
    
    # Show main.cf custom settings
    echo ""
    echo "${BLUE}Custom Configuration:${NC}"
    echo "======================"
    
    if [[ -f "data/conf/postfix/extra_main.cf" ]]; then
        echo "Custom main.cf: Configured"
        echo "Configuration size: $(wc -l < data/conf/postfix/extra_main.cf) lines"
    else
        echo "Custom main.cf: Not configured"
    fi
}

# Show usage
show_usage() {
    cat << EOF
Mailcow Mail Routing Rules Manager

Usage: $0 [action] [options]

Actions:
  init
    Initialize mail routing system
    
  add-transport <pattern> <transport> [nexthop] [description]
    Add transport routing rule
    
  remove-transport <pattern>
    Remove transport routing rule
    
  add-sender <sender_pattern> <transport> [nexthop] [description]
    Add sender-dependent routing rule
    
  setup-relay <relay_host> [port] [username] [password] [use_tls]
    Configure relay host
    
  setup-rate-limiting [rate_limit] [enable]
    Configure rate limiting
    
  list [format]
    List current routing rules (format: table, json)
    
  test <test_address> [sender_address]
    Test routing for specific address
    
  reload
    Reload Postfix configuration
    
  status
    Show routing system status

Transport Types:
  smtp        - SMTP delivery
  relay       - Relay to another server
  local       - Local delivery
  virtual     - Virtual delivery
  discard     - Discard message
  error       - Reject with error

Examples:
  $0 init
  $0 add-transport example.com smtp relay.example.com:587
  $0 add-sender marketing@company.com smtp bulk-relay.com:587
  $0 setup-relay smtp.gmail.com 587 username password true
  $0 setup-rate-limiting "50/hour" true
  $0 list table
  $0 test user@example.com sender@company.com
  $0 reload
  $0 status

Configuration files:
  - Main config: $ROUTING_CONFIG_DIR/routing.conf
  - Transport maps: $TRANSPORT_MAPS
  - Sender maps: $SENDER_DEPENDENT_TRANSPORT

EOF
}

# Main function
main() {
    local action="$1"
    shift
    
    # Load configuration
    load_config
    
    case "$action" in
        "init")
            initialize_routing
            ;;
        "add-transport")
            add_transport_rule "$1" "$2" "$3" "$4"
            ;;
        "remove-transport")
            remove_transport_rule "$1"
            ;;
        "add-sender")
            add_sender_rule "$1" "$2" "$3" "$4"
            ;;
        "setup-relay")
            setup_relay "$1" "$2" "$3" "$4" "$5"
            ;;
        "setup-rate-limiting")
            setup_rate_limiting "$1" "$2"
            ;;
        "list")
            list_routing_rules "$1"
            ;;
        "test")
            test_routing "$1" "$2"
            ;;
        "reload")
            reload_postfix_config
            ;;
        "status")
            show_routing_status
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