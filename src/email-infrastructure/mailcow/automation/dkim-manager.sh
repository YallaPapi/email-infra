#!/bin/bash

# Mailcow DKIM Management Automation
# Handles DKIM operations: generate, retrieve, manage, validate
# Usage: ./dkim-manager.sh [action] [domain] [options]

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/../config"
API_SCRIPT="$SCRIPT_DIR/../api/mailcow-api.py"
LOG_FILE="/var/log/mailcow-dkim-manager.log"

# DKIM Configuration
DEFAULT_KEY_SIZE=2048
DEFAULT_SELECTOR="dkim"
SUPPORTED_KEY_SIZES=(1024 2048 4096)

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
    
    # Check if domain exists in Mailcow
    if ! python3 "$API_SCRIPT" domain list | grep -q "$domain"; then
        error "Domain $domain does not exist in Mailcow. Add it first."
    fi
}

# Validate key size
validate_key_size() {
    local key_size="$1"
    
    if [[ -z "$key_size" ]]; then
        key_size=$DEFAULT_KEY_SIZE
    fi
    
    # Check if key size is supported
    local supported=false
    for size in "${SUPPORTED_KEY_SIZES[@]}"; do
        if [[ "$size" == "$key_size" ]]; then
            supported=true
            break
        fi
    done
    
    if [[ "$supported" != "true" ]]; then
        error "Unsupported key size: $key_size. Supported sizes: ${SUPPORTED_KEY_SIZES[*]}"
    fi
    
    echo "$key_size"
}

# Generate DKIM key
generate_dkim_key() {
    local domain="$1"
    local key_size="${2:-$DEFAULT_KEY_SIZE}"
    local selector="${3:-$DEFAULT_SELECTOR}"
    local force="${4:-false}"
    
    validate_domain "$domain"
    key_size=$(validate_key_size "$key_size")
    
    log "Generating DKIM key for domain: $domain (key size: $key_size, selector: $selector)"
    
    # Check if DKIM key already exists
    local existing_key=$(python3 "$API_SCRIPT" dkim get "$domain" 2>/dev/null || echo "")
    if [[ -n "$existing_key" ]] && [[ "$force" != "true" ]]; then
        warning "DKIM key already exists for $domain"
        echo -n "Overwrite existing key? (y/N): "
        read -r confirmation
        if [[ "$confirmation" != "y" && "$confirmation" != "Y" ]]; then
            info "DKIM key generation cancelled"
            return 0
        fi
        
        # Delete existing key first
        info "Removing existing DKIM key..."
        python3 "$API_SCRIPT" dkim delete "$domain" >/dev/null 2>&1 || warning "Failed to delete existing key"
        sleep 2
    fi
    
    # Generate new DKIM key
    local result=$(python3 "$API_SCRIPT" dkim add "$domain" --key-size "$key_size" --selector "$selector" 2>&1)
    
    if [[ $? -eq 0 ]]; then
        info "DKIM key generated successfully for $domain"
        
        # Wait a moment for key to be available
        sleep 3
        
        # Retrieve and save the public key
        retrieve_dkim_key "$domain" "save"
        
        # Validate the generated key
        validate_dkim_key "$domain"
        
    else
        error "Failed to generate DKIM key: $result"
    fi
}

# Retrieve DKIM key
retrieve_dkim_key() {
    local domain="$1"
    local action="${2:-display}"  # display, save, dns
    
    validate_domain "$domain"
    
    log "Retrieving DKIM key for domain: $domain"
    
    # Get DKIM public key
    local dkim_record=$(python3 "$API_SCRIPT" dkim get "$domain" 2>/dev/null)
    
    if [[ -z "$dkim_record" ]]; then
        warning "No DKIM key found for $domain. Generate one first."
        return 1
    fi
    
    case "$action" in
        "display")
            echo ""
            echo "${GREEN}DKIM Public Key for $domain:${NC}"
            echo "==============================="
            echo ""
            echo "$dkim_record"
            echo ""
            ;;
        "save")
            mkdir -p "$CONFIG_DIR/dkim"
            echo "$dkim_record" > "$CONFIG_DIR/dkim/$domain.txt"
            info "DKIM key saved to: $CONFIG_DIR/dkim/$domain.txt"
            ;;
        "dns")
            show_dns_record "$domain" "$dkim_record"
            ;;
    esac
}

# Show DNS record format
show_dns_record() {
    local domain="$1"
    local dkim_record="$2"
    local selector="${3:-$DEFAULT_SELECTOR}"
    
    echo ""
    echo "${GREEN}DNS Record for $domain DKIM:${NC}"
    echo "============================="
    echo ""
    echo "Record Type: TXT"
    echo "Name: ${selector}._domainkey.${domain}"
    echo "Value: $dkim_record"
    echo "TTL: 300"
    echo ""
    echo "${YELLOW}Instructions:${NC}"
    echo "1. Add this TXT record to your DNS provider"
    echo "2. Wait for DNS propagation (up to 48 hours)"
    echo "3. Test DKIM validation using: $0 test $domain"
    echo ""
}

# Delete DKIM key
delete_dkim_key() {
    local domain="$1"
    local confirm="${2:-false}"
    
    validate_domain "$domain"
    
    # Confirmation
    if [[ "$confirm" != "true" ]]; then
        echo -n "Are you sure you want to delete DKIM key for $domain? (yes/no): "
        read -r confirmation
        if [[ "$confirmation" != "yes" ]]; then
            info "DKIM key deletion cancelled"
            return 0
        fi
    fi
    
    log "Deleting DKIM key for domain: $domain"
    
    # Check if DKIM key exists
    local existing_key=$(python3 "$API_SCRIPT" dkim get "$domain" 2>/dev/null || echo "")
    if [[ -z "$existing_key" ]]; then
        warning "No DKIM key found for $domain"
        return 0
    fi
    
    # Delete DKIM key via API
    local result=$(python3 "$API_SCRIPT" dkim delete "$domain" 2>&1)
    
    if [[ $? -eq 0 ]]; then
        info "DKIM key deleted successfully for $domain"
        
        # Clean up saved key file
        rm -f "$CONFIG_DIR/dkim/$domain.txt"
        
    else
        error "Failed to delete DKIM key: $result"
    fi
}

# Test DKIM configuration
test_dkim() {
    local domain="$1"
    local selector="${2:-$DEFAULT_SELECTOR}"
    
    validate_domain "$domain"
    
    log "Testing DKIM configuration for domain: $domain"
    
    # Check if DKIM key exists in Mailcow
    local mailcow_key=$(python3 "$API_SCRIPT" dkim get "$domain" 2>/dev/null || echo "")
    if [[ -z "$mailcow_key" ]]; then
        error "No DKIM key configured in Mailcow for $domain"
    fi
    
    info "✓ DKIM key found in Mailcow"
    
    # Check DNS record
    local dns_record="${selector}._domainkey.${domain}"
    info "Checking DNS record: $dns_record"
    
    # Query DNS for DKIM record
    local dns_result=$(dig +short TXT "$dns_record" 2>/dev/null | tr -d '"' | tr -d ' ' || echo "")
    
    if [[ -z "$dns_result" ]]; then
        warning "✗ No DKIM DNS record found for $dns_record"
        echo ""
        echo "Please add the following DNS record:"
        show_dns_record "$domain" "$mailcow_key" "$selector"
        return 1
    fi
    
    info "✓ DKIM DNS record found"
    
    # Compare keys (basic check)
    # Extract public key from both records for comparison
    local mailcow_pubkey=$(echo "$mailcow_key" | grep -o 'p=[^;]*' | cut -d'=' -f2 | tr -d ' ')
    local dns_pubkey=$(echo "$dns_result" | grep -o 'p=[^;]*' | cut -d'=' -f2 | tr -d ' ')
    
    if [[ "$mailcow_pubkey" == "$dns_pubkey" ]]; then
        info "✓ DNS DKIM record matches Mailcow key"
        echo ""
        echo "${GREEN}DKIM Configuration Test: PASSED${NC}"
        echo "Domain: $domain"
        echo "Selector: $selector"
        echo "DNS Record: $dns_record"
        echo "Status: Ready for mail signing"
        echo ""
    else
        warning "✗ DNS DKIM record does not match Mailcow key"
        echo ""
        echo "${RED}DKIM Configuration Test: FAILED${NC}"
        echo "The DNS record exists but doesn't match the Mailcow key."
        echo "Please update your DNS record with the correct key:"
        show_dns_record "$domain" "$mailcow_key" "$selector"
        return 1
    fi
}

# Validate DKIM key format
validate_dkim_key() {
    local domain="$1"
    
    validate_domain "$domain"
    
    log "Validating DKIM key format for domain: $domain"
    
    # Get DKIM key
    local dkim_record=$(python3 "$API_SCRIPT" dkim get "$domain" 2>/dev/null || echo "")
    
    if [[ -z "$dkim_record" ]]; then
        error "No DKIM key found for $domain"
    fi
    
    # Check DKIM record format
    local errors=()
    
    # Check for required parameters
    if ! echo "$dkim_record" | grep -q "v=DKIM1"; then
        errors+=("Missing version (v=DKIM1)")
    fi
    
    if ! echo "$dkim_record" | grep -q "k=rsa"; then
        errors+=("Missing key type (k=rsa)")
    fi
    
    if ! echo "$dkim_record" | grep -q "p="; then
        errors+=("Missing public key (p=)")
    fi
    
    # Check public key format
    local pubkey=$(echo "$dkim_record" | grep -o 'p=[^;]*' | cut -d'=' -f2 | tr -d ' ')
    if [[ ${#pubkey} -lt 200 ]]; then
        errors+=("Public key appears too short")
    fi
    
    # Check for recommended parameters
    if ! echo "$dkim_record" | grep -q "t=s"; then
        warning "Missing strict mode (t=s) - recommended for security"
    fi
    
    if [[ ${#errors[@]} -eq 0 ]]; then
        info "✓ DKIM key format validation passed"
        return 0
    else
        error "DKIM key format validation failed:"
        for error in "${errors[@]}"; do
            echo "  - $error"
        done
        return 1
    fi
}

# List DKIM keys for all domains
list_dkim_keys() {
    local format="${1:-table}"
    
    log "Listing DKIM keys for all domains..."
    
    # Get all domains
    local domains=$(python3 "$API_SCRIPT" domain list 2>/dev/null | grep "Domain:" | awk '{print $2}')
    
    case "$format" in
        "table")
            echo ""
            printf "%-30s %-10s %-15s %-20s\n" "Domain" "DKIM Key" "DNS Status" "Last Updated"
            printf "%-30s %-10s %-15s %-20s\n" "==============================" "==========" "===============" "===================="
            
            for domain in $domains; do
                local has_key="No"
                local dns_status="Not Checked"
                local last_updated="N/A"
                
                # Check if DKIM key exists
                local dkim_key=$(python3 "$API_SCRIPT" dkim get "$domain" 2>/dev/null || echo "")
                if [[ -n "$dkim_key" ]]; then
                    has_key="Yes"
                    
                    # Check DNS status
                    local dns_record="${DEFAULT_SELECTOR}._domainkey.${domain}"
                    local dns_result=$(dig +short TXT "$dns_record" 2>/dev/null | tr -d '"' | tr -d ' ' || echo "")
                    if [[ -n "$dns_result" ]]; then
                        dns_status="Found"
                    else
                        dns_status="Missing"
                    fi
                    
                    # Get last updated from file if available
                    local key_file="$CONFIG_DIR/dkim/$domain.txt"
                    if [[ -f "$key_file" ]]; then
                        last_updated=$(stat -c %y "$key_file" 2>/dev/null | cut -d' ' -f1 || echo "N/A")
                    fi
                fi
                
                printf "%-30s %-10s %-15s %-20s\n" "$domain" "$has_key" "$dns_status" "$last_updated"
            done
            echo ""
            ;;
        "json")
            echo "["
            local first=true
            for domain in $domains; do
                local dkim_key=$(python3 "$API_SCRIPT" dkim get "$domain" 2>/dev/null || echo "")
                local has_key=$([ -n "$dkim_key" ] && echo "true" || echo "false")
                
                if [[ "$first" != "true" ]]; then
                    echo ","
                fi
                first=false
                
                echo "  {"
                echo "    \"domain\": \"$domain\","
                echo "    \"has_dkim_key\": $has_key,"
                echo "    \"dkim_record\": \"$dkim_key\""
                echo -n "  }"
            done
            echo ""
            echo "]"
            ;;
        "csv")
            echo "Domain,Has_DKIM_Key,DNS_Status"
            for domain in $domains; do
                local has_key="No"
                local dns_status="Not Checked"
                
                local dkim_key=$(python3 "$API_SCRIPT" dkim get "$domain" 2>/dev/null || echo "")
                if [[ -n "$dkim_key" ]]; then
                    has_key="Yes"
                    
                    local dns_record="${DEFAULT_SELECTOR}._domainkey.${domain}"
                    local dns_result=$(dig +short TXT "$dns_record" 2>/dev/null || echo "")
                    if [[ -n "$dns_result" ]]; then
                        dns_status="Found"
                    else
                        dns_status="Missing"
                    fi
                fi
                
                echo "$domain,$has_key,$dns_status"
            done
            ;;
    esac
}

# Bulk generate DKIM keys
bulk_generate_keys() {
    local domains_file="$1"
    local key_size="${2:-$DEFAULT_KEY_SIZE}"
    local selector="${3:-$DEFAULT_SELECTOR}"
    
    if [[ ! -f "$domains_file" ]]; then
        error "Domains file not found: $domains_file"
    fi
    
    key_size=$(validate_key_size "$key_size")
    
    log "Bulk generating DKIM keys from: $domains_file"
    
    local count=0
    local failed=0
    
    while IFS= read -r domain || [[ -n "$domain" ]]; do
        # Skip empty lines and comments
        [[ -z "$domain" || "$domain" =~ ^#.*$ ]] && continue
        
        # Remove any whitespace
        domain=$(echo "$domain" | xargs)
        
        if [[ -n "$domain" ]]; then
            info "Generating DKIM key for: $domain"
            if generate_dkim_key "$domain" "$key_size" "$selector" "true"; then
                ((count++))
            else
                ((failed++))
                warning "Failed to generate DKIM key for: $domain"
            fi
            
            # Rate limiting
            sleep 2
        fi
    done < "$domains_file"
    
    log "Bulk operation completed: $count keys generated, $failed failed"
}

# Generate DNS zone file entries
generate_dns_zone() {
    local domain="$1"
    local output_file="${2:-/tmp/dkim-dns-${domain}-$(date +%Y%m%d_%H%M%S).txt}"
    
    if [[ -z "$domain" ]]; then
        # Generate for all domains
        log "Generating DNS zone entries for all domains..."
        
        local domains=$(python3 "$API_SCRIPT" domain list 2>/dev/null | grep "Domain:" | awk '{print $2}')
        
        cat > "$output_file" << EOF
; DKIM DNS Records for Mailcow Domains
; Generated: $(date)
; Instructions: Add these TXT records to your DNS zone

EOF
        
        for dom in $domains; do
            local dkim_key=$(python3 "$API_SCRIPT" dkim get "$dom" 2>/dev/null || echo "")
            if [[ -n "$dkim_key" ]]; then
                echo "; DKIM record for $dom" >> "$output_file"
                echo "${DEFAULT_SELECTOR}._domainkey.$dom. IN TXT \"$dkim_key\"" >> "$output_file"
                echo "" >> "$output_file"
            fi
        done
        
    else
        validate_domain "$domain"
        
        log "Generating DNS zone entry for domain: $domain"
        
        local dkim_key=$(python3 "$API_SCRIPT" dkim get "$domain" 2>/dev/null || echo "")
        if [[ -z "$dkim_key" ]]; then
            error "No DKIM key found for $domain"
        fi
        
        cat > "$output_file" << EOF
; DKIM DNS Record for $domain
; Generated: $(date)

${DEFAULT_SELECTOR}._domainkey.$domain. IN TXT "$dkim_key"
EOF
    fi
    
    info "DNS zone file generated: $output_file"
    cat "$output_file"
}

# Show usage
show_usage() {
    cat << EOF
Mailcow DKIM Manager

Usage: $0 [action] [domain] [options]

Actions:
  generate <domain> [key_size] [selector] [--force]
    Generate DKIM key for domain
    
  get <domain> [action]
    Retrieve DKIM key (action: display, save, dns)
    
  delete <domain> [--confirm]
    Delete DKIM key for domain
    
  test <domain> [selector]
    Test DKIM configuration and DNS setup
    
  validate <domain>
    Validate DKIM key format
    
  list [format]
    List DKIM keys for all domains (format: table, json, csv)
    
  bulk-generate <file> [key_size] [selector]
    Generate DKIM keys for domains in file
    
  dns-zone [domain] [output_file]
    Generate DNS zone file entries

Options:
  --force           Overwrite existing DKIM keys
  --confirm         Skip confirmation prompts
  --format FORMAT   Output format (table, json, csv)
  --help           Show this help message

Key Sizes: ${SUPPORTED_KEY_SIZES[*]} (default: $DEFAULT_KEY_SIZE)
Default Selector: $DEFAULT_SELECTOR

Examples:
  $0 generate example.com
  $0 generate example.com 2048 dkim --force
  $0 get example.com dns
  $0 test example.com
  $0 list table
  $0 bulk-generate domains.txt 2048
  $0 dns-zone example.com

File format for bulk-generate:
  example.com
  test.com
  another.com

EOF
}

# Main function
main() {
    local action="$1"
    shift
    
    # Load configuration
    load_config
    
    case "$action" in
        "generate"|"create")
            local force=""
            for arg in "$@"; do
                if [[ "$arg" == "--force" ]]; then
                    force="true"
                    break
                fi
            done
            generate_dkim_key "$1" "$2" "$3" "$force"
            ;;
        "get"|"retrieve")
            retrieve_dkim_key "$1" "$2"
            ;;
        "delete"|"remove")
            local confirm=""
            for arg in "$@"; do
                if [[ "$arg" == "--confirm" ]]; then
                    confirm="true"
                    break
                fi
            done
            delete_dkim_key "$1" "$confirm"
            ;;
        "test"|"check")
            test_dkim "$1" "$2"
            ;;
        "validate")
            validate_dkim_key "$1"
            ;;
        "list")
            list_dkim_keys "$1"
            ;;
        "bulk-generate")
            bulk_generate_keys "$1" "$2" "$3"
            ;;
        "dns-zone")
            generate_dns_zone "$1" "$2"
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