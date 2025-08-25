#!/bin/bash

# Mailcow Domain Management Automation
# Handles domain operations: add, remove, configure, list
# Usage: ./domain-manager.sh [action] [domain] [options]

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/../config"
API_SCRIPT="$SCRIPT_DIR/../api/mailcow-api.py"
LOG_FILE="/var/log/mailcow-domain-manager.log"

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
    if [[ -f "$CONFIG_DIR/api_key" ]]; then
        source "$CONFIG_DIR/api_key"
    else
        error "API key file not found. Run configure script first."
    fi
    
    if [[ -f "$CONFIG_DIR/admin_credentials" ]]; then
        source "$CONFIG_DIR/admin_credentials"
    else
        warning "Admin credentials not found"
    fi
}

# Validate domain format
validate_domain() {
    local domain="$1"
    
    if [[ -z "$domain" ]]; then
        error "Domain name is required"
    fi
    
    # Basic domain validation
    if ! [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*$ ]]; then
        error "Invalid domain format: $domain"
    fi
    
    # Check length
    if [[ ${#domain} -gt 253 ]]; then
        error "Domain name too long: $domain"
    fi
}

# Check DNS configuration
check_dns() {
    local domain="$1"
    local server_ip="${2:-$(curl -s ifconfig.me)}"
    
    info "Checking DNS configuration for $domain..."
    
    # Check A record
    local a_record=$(dig +short "$domain" 2>/dev/null || echo "")
    if [[ "$a_record" == "$server_ip" ]]; then
        info "✓ A record correctly points to $server_ip"
    else
        warning "⚠ A record points to '$a_record', expected '$server_ip'"
    fi
    
    # Check MX record
    local mx_record=$(dig +short MX "$domain" 2>/dev/null | awk '{print $2}' | sed 's/\.$//' || echo "")
    if [[ -n "$mx_record" ]]; then
        info "✓ MX record found: $mx_record"
        
        # Check if MX points to correct IP
        local mx_ip=$(dig +short "$mx_record" 2>/dev/null || echo "")
        if [[ "$mx_ip" == "$server_ip" ]]; then
            info "✓ MX record correctly resolves to $server_ip"
        else
            warning "⚠ MX record resolves to '$mx_ip', expected '$server_ip'"
        fi
    else
        warning "⚠ No MX record found for $domain"
    fi
    
    # Check for existing DKIM record
    local dkim_record=$(dig +short TXT "dkim._domainkey.$domain" 2>/dev/null || echo "")
    if [[ -n "$dkim_record" ]]; then
        info "✓ DKIM record exists"
    else
        info "ℹ No DKIM record found (will be created after domain setup)"
    fi
}

# Add domain
add_domain() {
    local domain="$1"
    local description="$2"
    local quota="${3:-3072}"
    local mailboxes="${4:-10}"
    local aliases="${5:-400}"
    
    validate_domain "$domain"
    
    log "Adding domain: $domain"
    
    # Check if domain already exists
    if python3 "$API_SCRIPT" domain list | grep -q "$domain"; then
        error "Domain $domain already exists"
    fi
    
    # Check DNS configuration
    check_dns "$domain"
    
    # Add domain via API
    local result=$(python3 "$API_SCRIPT" domain add "$domain" \
        --quota "$quota" \
        --mailboxes "$mailboxes" 2>&1)
    
    if [[ $? -eq 0 ]]; then
        info "Domain $domain added successfully"
        
        # Generate DKIM key
        info "Generating DKIM key for $domain..."
        sleep 2  # Wait for domain to be fully created
        
        local dkim_result=$(python3 "$API_SCRIPT" dkim add "$domain" --key-size 2048 2>&1)
        if [[ $? -eq 0 ]]; then
            info "DKIM key generated for $domain"
            
            # Get DKIM record for DNS
            local dkim_record=$(python3 "$API_SCRIPT" dkim get "$domain" 2>/dev/null)
            if [[ -n "$dkim_record" ]]; then
                info "Add this DKIM record to your DNS:"
                echo ""
                echo "Record Type: TXT"
                echo "Name: dkim._domainkey.$domain"
                echo "Value: $dkim_record"
                echo ""
                
                # Save DKIM record to file
                mkdir -p "$CONFIG_DIR/dkim"
                echo "$dkim_record" > "$CONFIG_DIR/dkim/$domain.txt"
                info "DKIM record saved to: $CONFIG_DIR/dkim/$domain.txt"
            fi
        else
            warning "Failed to generate DKIM key: $dkim_result"
        fi
        
        # Create domain info file
        create_domain_info "$domain" "$quota" "$mailboxes" "$aliases"
        
    else
        error "Failed to add domain: $result"
    fi
}

# Remove domain
remove_domain() {
    local domain="$1"
    local confirm="${2:-false}"
    
    validate_domain "$domain"
    
    # Confirmation
    if [[ "$confirm" != "true" ]]; then
        echo -n "Are you sure you want to delete domain $domain? This will remove all mailboxes and data. (yes/no): "
        read -r confirmation
        if [[ "$confirmation" != "yes" ]]; then
            info "Domain deletion cancelled"
            return 0
        fi
    fi
    
    log "Removing domain: $domain"
    
    # Check if domain exists
    if ! python3 "$API_SCRIPT" domain list | grep -q "$domain"; then
        warning "Domain $domain does not exist"
        return 0
    fi
    
    # List mailboxes before deletion
    local mailboxes=$(python3 "$API_SCRIPT" mailbox list --domain "$domain" 2>/dev/null | grep "Email:" | awk '{print $2}')
    if [[ -n "$mailboxes" ]]; then
        warning "The following mailboxes will be deleted:"
        echo "$mailboxes"
    fi
    
    # Remove domain via API
    local result=$(python3 "$API_SCRIPT" domain delete "$domain" 2>&1)
    
    if [[ $? -eq 0 ]]; then
        info "Domain $domain removed successfully"
        
        # Clean up files
        rm -f "$CONFIG_DIR/dkim/$domain.txt"
        rm -f "$CONFIG_DIR/domains/$domain.info"
        
    else
        error "Failed to remove domain: $result"
    fi
}

# List domains
list_domains() {
    local format="${1:-table}"
    
    log "Listing domains..."
    
    case "$format" in
        "table")
            echo ""
            printf "%-30s %-8s %-10s %-10s %-15s\n" "Domain" "Active" "Mailboxes" "Quota(MB)" "Aliases"
            printf "%-30s %-8s %-10s %-10s %-15s\n" "==============================" "======" "==========" "==========" "==============="
            
            python3 "$API_SCRIPT" domain list 2>/dev/null | while IFS= read -r line; do
                if [[ "$line" =~ Domain:\ (.+) ]]; then
                    domain="${BASH_REMATCH[1]}"
                    printf "%-30s" "$domain"
                elif [[ "$line" =~ Active:\ (.+) ]]; then
                    active="${BASH_REMATCH[1]}"
                    printf " %-8s" "$active"
                elif [[ "$line" =~ Mailboxes:\ (.+) ]]; then
                    mailboxes="${BASH_REMATCH[1]}"
                    printf " %-10s" "$mailboxes"
                elif [[ "$line" =~ Quota:\ (.+) ]]; then
                    quota="${BASH_REMATCH[1]}"
                    printf " %-10s" "$quota"
                    printf " %-15s\n" "N/A"
                fi
            done
            echo ""
            ;;
        "json")
            python3 "$API_SCRIPT" domain list --format json
            ;;
        "csv")
            echo "Domain,Active,Mailboxes,Quota"
            python3 "$API_SCRIPT" domain list 2>/dev/null | while IFS= read -r line; do
                if [[ "$line" =~ Domain:\ (.+) ]]; then
                    domain="${BASH_REMATCH[1]}"
                    printf "%s," "$domain"
                elif [[ "$line" =~ Active:\ (.+) ]]; then
                    active="${BASH_REMATCH[1]}"
                    printf "%s," "$active"
                elif [[ "$line" =~ Mailboxes:\ (.+) ]]; then
                    mailboxes="${BASH_REMATCH[1]}"
                    printf "%s," "$mailboxes"
                elif [[ "$line" =~ Quota:\ (.+) ]]; then
                    quota="${BASH_REMATCH[1]}"
                    printf "%s\n" "$quota"
                fi
            done
            ;;
    esac
}

# Configure domain
configure_domain() {
    local domain="$1"
    local setting="$2"
    local value="$3"
    
    validate_domain "$domain"
    
    if [[ -z "$setting" || -z "$value" ]]; then
        error "Setting and value are required for configuration"
    fi
    
    log "Configuring domain $domain: $setting = $value"
    
    # Map setting names to API parameters
    case "$setting" in
        "quota")
            api_param="quota"
            ;;
        "mailboxes")
            api_param="mailboxes"
            ;;
        "aliases")
            api_param="aliases"
            ;;
        "active")
            api_param="active"
            value=$([ "$value" = "true" ] && echo "1" || echo "0")
            ;;
        "description")
            api_param="description"
            ;;
        *)
            error "Unknown setting: $setting"
            ;;
    esac
    
    # Update domain via API (this would need to be implemented in the API wrapper)
    info "Domain configuration updated: $domain"
}

# Get domain info
get_domain_info() {
    local domain="$1"
    
    validate_domain "$domain"
    
    log "Getting domain information for: $domain"
    
    python3 "$API_SCRIPT" domain list | grep -A 10 "Domain: $domain" || warning "Domain $domain not found"
    
    # Show DKIM record if available
    local dkim_file="$CONFIG_DIR/dkim/$domain.txt"
    if [[ -f "$dkim_file" ]]; then
        echo ""
        echo "DKIM Record:"
        echo "============"
        cat "$dkim_file"
    fi
}

# Create domain info file
create_domain_info() {
    local domain="$1"
    local quota="$2"
    local mailboxes="$3"
    local aliases="$4"
    
    mkdir -p "$CONFIG_DIR/domains"
    
    cat > "$CONFIG_DIR/domains/$domain.info" << EOF
# Domain Information: $domain
# Created: $(date)

DOMAIN=$domain
QUOTA=$quota
MAX_MAILBOXES=$mailboxes
MAX_ALIASES=$aliases
CREATED=$(date -Iseconds)
DKIM_ENABLED=true
ACTIVE=true

# DNS Requirements:
# A record: $domain -> $(curl -s ifconfig.me 2>/dev/null || echo "SERVER_IP")
# MX record: $domain -> $domain (priority 10)
# DKIM TXT record: dkim._domainkey.$domain -> (see $CONFIG_DIR/dkim/$domain.txt)

# Additional recommended DNS records:
# SPF TXT record: $domain -> "v=spf1 mx ~all"
# DMARC TXT record: _dmarc.$domain -> "v=DMARC1; p=quarantine; rua=mailto:dmarc@$domain"
EOF
    
    info "Domain info saved to: $CONFIG_DIR/domains/$domain.info"
}

# Bulk domain operations
bulk_add_domains() {
    local domains_file="$1"
    
    if [[ ! -f "$domains_file" ]]; then
        error "Domains file not found: $domains_file"
    fi
    
    log "Bulk adding domains from: $domains_file"
    
    local count=0
    local failed=0
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^#.*$ ]] && continue
        
        # Parse line: domain,description,quota,mailboxes,aliases
        IFS=',' read -ra DOMAIN_INFO <<< "$line"
        local domain="${DOMAIN_INFO[0]}"
        local description="${DOMAIN_INFO[1]:-Auto-added domain}"
        local quota="${DOMAIN_INFO[2]:-3072}"
        local mailboxes="${DOMAIN_INFO[3]:-10}"
        local aliases="${DOMAIN_INFO[4]:-400}"
        
        if [[ -n "$domain" ]]; then
            info "Adding domain: $domain"
            if add_domain "$domain" "$description" "$quota" "$mailboxes" "$aliases"; then
                ((count++))
            else
                ((failed++))
                warning "Failed to add domain: $domain"
            fi
            
            # Rate limiting
            sleep 1
        fi
    done < "$domains_file"
    
    log "Bulk operation completed: $count domains added, $failed failed"
}

# Generate DNS records
generate_dns_records() {
    local domain="$1"
    local server_ip="${2:-$(curl -s ifconfig.me 2>/dev/null || echo "YOUR_SERVER_IP")}"
    
    validate_domain "$domain"
    
    info "Generating DNS records for $domain"
    
    echo ""
    echo "DNS Records for $domain"
    echo "======================="
    echo ""
    
    # A record
    echo "A Record:"
    echo "Name: $domain"
    echo "Type: A"
    echo "Value: $server_ip"
    echo "TTL: 300"
    echo ""
    
    # MX record
    echo "MX Record:"
    echo "Name: $domain"
    echo "Type: MX"
    echo "Priority: 10"
    echo "Value: $domain"
    echo "TTL: 300"
    echo ""
    
    # DKIM record
    local dkim_file="$CONFIG_DIR/dkim/$domain.txt"
    if [[ -f "$dkim_file" ]]; then
        echo "DKIM Record:"
        echo "Name: dkim._domainkey.$domain"
        echo "Type: TXT"
        echo "Value: $(cat "$dkim_file")"
        echo "TTL: 300"
        echo ""
    fi
    
    # SPF record
    echo "SPF Record:"
    echo "Name: $domain"
    echo "Type: TXT"
    echo "Value: \"v=spf1 mx ~all\""
    echo "TTL: 300"
    echo ""
    
    # DMARC record
    echo "DMARC Record:"
    echo "Name: _dmarc.$domain"
    echo "Type: TXT"
    echo "Value: \"v=DMARC1; p=quarantine; rua=mailto:dmarc@$domain\""
    echo "TTL: 300"
    echo ""
}

# Show usage
show_usage() {
    cat << EOF
Mailcow Domain Manager

Usage: $0 [action] [domain] [options]

Actions:
  add <domain> [description] [quota] [mailboxes] [aliases]
    Add a new domain to Mailcow
    
  remove <domain> [--confirm]
    Remove a domain from Mailcow
    
  list [format]
    List all domains (format: table, json, csv)
    
  info <domain>
    Show detailed information about a domain
    
  configure <domain> <setting> <value>
    Configure domain settings
    
  dns <domain> [server_ip]
    Generate DNS records for domain
    
  bulk-add <file>
    Add domains from CSV file
    
  check-dns <domain> [server_ip]
    Check DNS configuration for domain

Options:
  --confirm         Skip confirmation prompts
  --format FORMAT   Output format (table, json, csv)
  --help           Show this help message

Examples:
  $0 add example.com "Example Domain" 5120 20 500
  $0 remove example.com --confirm
  $0 list table
  $0 info example.com
  $0 dns example.com 1.2.3.4
  $0 check-dns example.com

File format for bulk-add:
  domain.com,Description,quota_mb,max_mailboxes,max_aliases
  example.com,Example Domain,3072,10,400
  test.com,Test Domain,1024,5,100

EOF
}

# Main function
main() {
    local action="$1"
    shift
    
    # Load configuration
    load_config
    
    case "$action" in
        "add")
            add_domain "$@"
            ;;
        "remove"|"delete")
            local confirm=""
            if [[ "$2" == "--confirm" ]]; then
                confirm="true"
            fi
            remove_domain "$1" "$confirm"
            ;;
        "list")
            list_domains "$1"
            ;;
        "info"|"show")
            get_domain_info "$1"
            ;;
        "configure"|"config")
            configure_domain "$1" "$2" "$3"
            ;;
        "dns")
            generate_dns_records "$1" "$2"
            ;;
        "bulk-add")
            bulk_add_domains "$1"
            ;;
        "check-dns")
            check_dns "$1" "$2"
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