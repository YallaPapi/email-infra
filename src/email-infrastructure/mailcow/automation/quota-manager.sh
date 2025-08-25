#!/bin/bash

# Mailcow Quota and Policy Management
# Handles quota operations and policy enforcement
# Usage: ./quota-manager.sh [action] [target] [options]

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/../config"
API_SCRIPT="$SCRIPT_DIR/../api/mailcow-api.py"
LOG_FILE="/var/log/mailcow-quota-manager.log"

# Default quotas (in MB)
DEFAULT_DOMAIN_QUOTA=10240
DEFAULT_MAILBOX_QUOTA=2048
MIN_QUOTA=100
MAX_QUOTA=102400

# Policy settings
QUOTA_WARNING_THRESHOLD=80
QUOTA_CRITICAL_THRESHOLD=95

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
    
    # Load quota policies if available
    if [[ -f "$CONFIG_DIR/quota_policies.conf" ]]; then
        source "$CONFIG_DIR/quota_policies.conf"
    fi
}

# Validate quota value
validate_quota() {
    local quota="$1"
    local target_type="${2:-mailbox}"
    
    if [[ -z "$quota" ]]; then
        error "Quota value is required"
    fi
    
    # Check if numeric
    if ! [[ "$quota" =~ ^[0-9]+$ ]]; then
        error "Quota must be a positive integer (MB)"
    fi
    
    # Check minimum quota
    if [[ $quota -lt $MIN_QUOTA ]]; then
        error "Quota too small. Minimum: ${MIN_QUOTA}MB"
    fi
    
    # Check maximum quota
    if [[ $quota -gt $MAX_QUOTA ]]; then
        error "Quota too large. Maximum: ${MAX_QUOTA}MB"
    fi
    
    # Additional validation for domain vs mailbox quotas
    if [[ "$target_type" == "domain" && $quota -lt 1024 ]]; then
        warning "Domain quota less than 1GB may be insufficient"
    fi
}

# Set mailbox quota
set_mailbox_quota() {
    local email="$1"
    local quota="$2"
    local force="${3:-false}"
    
    if [[ -z "$email" ]]; then
        error "Email address is required"
    fi
    
    validate_quota "$quota" "mailbox"
    
    log "Setting mailbox quota: $email = ${quota}MB"
    
    # Check if mailbox exists
    if ! python3 "$API_SCRIPT" mailbox list | grep -q "$email"; then
        error "Mailbox $email does not exist"
    fi
    
    # Get current quota usage if possible
    local current_usage=$(get_mailbox_usage "$email" 2>/dev/null || echo "0")
    
    # Warn if new quota is less than current usage
    if [[ $current_usage -gt $quota && "$force" != "true" ]]; then
        warning "New quota (${quota}MB) is less than current usage (${current_usage}MB)"
        echo -n "Continue anyway? (y/N): "
        read -r confirmation
        if [[ "$confirmation" != "y" && "$confirmation" != "Y" ]]; then
            info "Quota update cancelled"
            return 0
        fi
    fi
    
    # Update quota via Python API wrapper
    if python3 -c "
import sys
sys.path.append('$SCRIPT_DIR/../api')
from mailcow_api import MailcowAPI, load_config

try:
    config = load_config()
    api = MailcowAPI(config.hostname, config.api_key, config.verify_ssl)
    result = api.update_mailbox('$email', quota=$quota)
    print('Quota updated successfully')
except Exception as e:
    print(f'Error: {e}')
    sys.exit(1)
"; then
        info "Mailbox quota updated successfully: $email = ${quota}MB"
        
        # Update local tracking
        update_quota_tracking "$email" "mailbox" "$quota"
        
    else
        error "Failed to update mailbox quota"
    fi
}

# Set domain quota
set_domain_quota() {
    local domain="$1"
    local quota="$2"
    local force="${3:-false}"
    
    if [[ -z "$domain" ]]; then
        error "Domain name is required"
    fi
    
    validate_quota "$quota" "domain"
    
    log "Setting domain quota: $domain = ${quota}MB"
    
    # Check if domain exists
    if ! python3 "$API_SCRIPT" domain list | grep -q "$domain"; then
        error "Domain $domain does not exist"
    fi
    
    # Get current domain usage
    local current_usage=$(get_domain_usage "$domain" 2>/dev/null || echo "0")
    
    # Warn if new quota is less than current usage
    if [[ $current_usage -gt $quota && "$force" != "true" ]]; then
        warning "New quota (${quota}MB) is less than current usage (${current_usage}MB)"
        echo -n "Continue anyway? (y/N): "
        read -r confirmation
        if [[ "$confirmation" != "y" && "$confirmation" != "Y" ]]; then
            info "Quota update cancelled"
            return 0
        fi
    fi
    
    # Update quota via Python API wrapper
    if python3 -c "
import sys
sys.path.append('$SCRIPT_DIR/../api')
from mailcow_api import MailcowAPI, load_config

try:
    config = load_config()
    api = MailcowAPI(config.hostname, config.api_key, config.verify_ssl)
    result = api.update_domain('$domain', quota=$quota)
    print('Domain quota updated successfully')
except Exception as e:
    print(f'Error: {e}')
    sys.exit(1)
"; then
        info "Domain quota updated successfully: $domain = ${quota}MB"
        
        # Update local tracking
        update_quota_tracking "$domain" "domain" "$quota"
        
    else
        error "Failed to update domain quota"
    fi
}

# Get mailbox quota usage
get_mailbox_usage() {
    local email="$1"
    
    if [[ -z "$email" ]]; then
        error "Email address is required"
    fi
    
    # This would need to be implemented in the API wrapper
    # For now, return a placeholder
    python3 -c "
import sys
sys.path.append('$SCRIPT_DIR/../api')
from mailcow_api import MailcowAPI, load_config

try:
    config = load_config()
    api = MailcowAPI(config.hostname, config.api_key, config.verify_ssl)
    mailbox = api.get_mailbox('$email')
    if 'quota_used' in mailbox:
        print(int(mailbox['quota_used'] / 1024 / 1024))  # Convert to MB
    else:
        print(0)
except Exception as e:
    print(0)
" 2>/dev/null || echo "0"
}

# Get domain quota usage
get_domain_usage() {
    local domain="$1"
    
    if [[ -z "$domain" ]]; then
        error "Domain name is required"
    fi
    
    # Sum up all mailbox usage in domain
    local total_usage=0
    local mailboxes=$(python3 "$API_SCRIPT" mailbox list --domain "$domain" 2>/dev/null | grep "Email:" | awk '{print $2}')
    
    for mailbox in $mailboxes; do
        local usage=$(get_mailbox_usage "$mailbox")
        total_usage=$((total_usage + usage))
    done
    
    echo "$total_usage"
}

# List quota usage
list_quota_usage() {
    local target_type="${1:-both}"
    local format="${2:-table}"
    local show_warnings="${3:-true}"
    
    log "Listing quota usage..."
    
    case "$target_type" in
        "mailbox"|"mailboxes")
            list_mailbox_quotas "$format" "$show_warnings"
            ;;
        "domain"|"domains")
            list_domain_quotas "$format" "$show_warnings"
            ;;
        "both"|"all")
            list_domain_quotas "$format" "$show_warnings"
            echo ""
            list_mailbox_quotas "$format" "$show_warnings"
            ;;
        *)
            error "Invalid target type: $target_type. Use: mailbox, domain, or both"
            ;;
    esac
}

# List mailbox quotas
list_mailbox_quotas() {
    local format="${1:-table}"
    local show_warnings="${2:-true}"
    
    case "$format" in
        "table")
            echo ""
            echo "${BLUE}Mailbox Quota Usage:${NC}"
            printf "%-40s %-10s %-10s %-10s %-10s\n" "Email" "Used(MB)" "Quota(MB)" "Usage%" "Status"
            printf "%-40s %-10s %-10s %-10s %-10s\n" "========================================" "==========" "==========" "==========" "=========="
            
            # Get all mailboxes
            local mailboxes=$(python3 "$API_SCRIPT" mailbox list 2>/dev/null | grep "Email:" | awk '{print $2}')
            
            for email in $mailboxes; do
                # Get quota info from API
                local quota_info=$(python3 "$API_SCRIPT" mailbox list | grep -A 5 "Email: $email" | grep "Quota:" | awk '{print $2}')
                local quota_mb=$(echo "$quota_info" | cut -d'M' -f1)
                local used_mb=$(get_mailbox_usage "$email")
                local usage_percent=0
                
                if [[ $quota_mb -gt 0 ]]; then
                    usage_percent=$((used_mb * 100 / quota_mb))
                fi
                
                # Determine status
                local status="OK"
                local color="$NC"
                
                if [[ $usage_percent -ge $QUOTA_CRITICAL_THRESHOLD ]]; then
                    status="CRITICAL"
                    color="$RED"
                elif [[ $usage_percent -ge $QUOTA_WARNING_THRESHOLD ]]; then
                    status="WARNING"
                    color="$YELLOW"
                fi
                
                printf "${color}%-40s %-10s %-10s %-10s %-10s${NC}\n" "$email" "$used_mb" "$quota_mb" "${usage_percent}%" "$status"
                
                # Show warnings if enabled
                if [[ "$show_warnings" == "true" && "$status" != "OK" ]]; then
                    case "$status" in
                        "CRITICAL")
                            warning "Mailbox $email is at ${usage_percent}% capacity"
                            ;;
                        "WARNING")
                            info "Mailbox $email is at ${usage_percent}% capacity"
                            ;;
                    esac
                fi
            done
            echo ""
            ;;
        "json")
            echo "["
            local first=true
            local mailboxes=$(python3 "$API_SCRIPT" mailbox list 2>/dev/null | grep "Email:" | awk '{print $2}')
            
            for email in $mailboxes; do
                local quota_info=$(python3 "$API_SCRIPT" mailbox list | grep -A 5 "Email: $email" | grep "Quota:" | awk '{print $2}')
                local quota_mb=$(echo "$quota_info" | cut -d'M' -f1)
                local used_mb=$(get_mailbox_usage "$email")
                local usage_percent=0
                
                if [[ $quota_mb -gt 0 ]]; then
                    usage_percent=$((used_mb * 100 / quota_mb))
                fi
                
                if [[ "$first" != "true" ]]; then
                    echo ","
                fi
                first=false
                
                echo "  {"
                echo "    \"email\": \"$email\","
                echo "    \"used_mb\": $used_mb,"
                echo "    \"quota_mb\": $quota_mb,"
                echo "    \"usage_percent\": $usage_percent"
                echo -n "  }"
            done
            echo ""
            echo "]"
            ;;
        "csv")
            echo "Email,Used_MB,Quota_MB,Usage_Percent"
            local mailboxes=$(python3 "$API_SCRIPT" mailbox list 2>/dev/null | grep "Email:" | awk '{print $2}')
            
            for email in $mailboxes; do
                local quota_info=$(python3 "$API_SCRIPT" mailbox list | grep -A 5 "Email: $email" | grep "Quota:" | awk '{print $2}')
                local quota_mb=$(echo "$quota_info" | cut -d'M' -f1)
                local used_mb=$(get_mailbox_usage "$email")
                local usage_percent=0
                
                if [[ $quota_mb -gt 0 ]]; then
                    usage_percent=$((used_mb * 100 / quota_mb))
                fi
                
                echo "$email,$used_mb,$quota_mb,$usage_percent"
            done
            ;;
    esac
}

# List domain quotas
list_domain_quotas() {
    local format="${1:-table}"
    local show_warnings="${2:-true}"
    
    case "$format" in
        "table")
            echo ""
            echo "${BLUE}Domain Quota Usage:${NC}"
            printf "%-30s %-10s %-10s %-10s %-10s %-10s\n" "Domain" "Used(MB)" "Quota(MB)" "Usage%" "Mailboxes" "Status"
            printf "%-30s %-10s %-10s %-10s %-10s %-10s\n" "==============================" "==========" "==========" "==========" "==========" "=========="
            
            # Get all domains
            local domains=$(python3 "$API_SCRIPT" domain list 2>/dev/null | grep "Domain:" | awk '{print $2}')
            
            for domain in $domains; do
                # Get domain quota info
                local quota_info=$(python3 "$API_SCRIPT" domain list | grep -A 5 "Domain: $domain" | grep "Quota:" | awk '{print $2}')
                local quota_mb=$(echo "$quota_info" | cut -d'M' -f1)
                local used_mb=$(get_domain_usage "$domain")
                local mailbox_count=$(python3 "$API_SCRIPT" mailbox list --domain "$domain" 2>/dev/null | grep -c "Email:" || echo "0")
                local usage_percent=0
                
                if [[ $quota_mb -gt 0 ]]; then
                    usage_percent=$((used_mb * 100 / quota_mb))
                fi
                
                # Determine status
                local status="OK"
                local color="$NC"
                
                if [[ $usage_percent -ge $QUOTA_CRITICAL_THRESHOLD ]]; then
                    status="CRITICAL"
                    color="$RED"
                elif [[ $usage_percent -ge $QUOTA_WARNING_THRESHOLD ]]; then
                    status="WARNING"
                    color="$YELLOW"
                fi
                
                printf "${color}%-30s %-10s %-10s %-10s %-10s %-10s${NC}\n" "$domain" "$used_mb" "$quota_mb" "${usage_percent}%" "$mailbox_count" "$status"
                
                # Show warnings if enabled
                if [[ "$show_warnings" == "true" && "$status" != "OK" ]]; then
                    case "$status" in
                        "CRITICAL")
                            warning "Domain $domain is at ${usage_percent}% capacity"
                            ;;
                        "WARNING")
                            info "Domain $domain is at ${usage_percent}% capacity"
                            ;;
                    esac
                fi
            done
            echo ""
            ;;
    esac
}

# Set quota policies
set_quota_policies() {
    local warning_threshold="${1:-$QUOTA_WARNING_THRESHOLD}"
    local critical_threshold="${2:-$QUOTA_CRITICAL_THRESHOLD}"
    
    log "Setting quota policies: Warning=${warning_threshold}%, Critical=${critical_threshold}%"
    
    # Validate thresholds
    if [[ ! "$warning_threshold" =~ ^[0-9]+$ ]] || [[ ! "$critical_threshold" =~ ^[0-9]+$ ]]; then
        error "Thresholds must be numeric (percentage)"
    fi
    
    if [[ $warning_threshold -ge $critical_threshold ]]; then
        error "Warning threshold must be less than critical threshold"
    fi
    
    if [[ $warning_threshold -lt 50 || $warning_threshold -gt 95 ]]; then
        error "Warning threshold must be between 50-95%"
    fi
    
    if [[ $critical_threshold -lt 80 || $critical_threshold -gt 99 ]]; then
        error "Critical threshold must be between 80-99%"
    fi
    
    # Save policies to config file
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_DIR/quota_policies.conf" << EOF
# Quota Policy Configuration
# Generated: $(date)

QUOTA_WARNING_THRESHOLD=$warning_threshold
QUOTA_CRITICAL_THRESHOLD=$critical_threshold

# Default quotas (MB)
DEFAULT_DOMAIN_QUOTA=$DEFAULT_DOMAIN_QUOTA
DEFAULT_MAILBOX_QUOTA=$DEFAULT_MAILBOX_QUOTA
MIN_QUOTA=$MIN_QUOTA
MAX_QUOTA=$MAX_QUOTA

# Notification settings
ENABLE_QUOTA_NOTIFICATIONS=true
NOTIFICATION_EMAIL=${ADMIN_EMAIL:-admin@localhost}
EOF
    
    info "Quota policies updated successfully"
    info "Warning threshold: ${warning_threshold}%"
    info "Critical threshold: ${critical_threshold}%"
}

# Update quota tracking
update_quota_tracking() {
    local target="$1"
    local type="$2"
    local quota="$3"
    
    mkdir -p "$CONFIG_DIR/quota_tracking"
    
    local tracking_file="$CONFIG_DIR/quota_tracking/${target}.track"
    
    cat > "$tracking_file" << EOF
# Quota tracking for: $target
TYPE=$type
QUOTA=$quota
LAST_UPDATED=$(date -Iseconds)
UPDATED_BY=$(whoami)
EOF
    
    chmod 600 "$tracking_file"
}

# Generate quota report
generate_quota_report() {
    local output_file="${1:-/tmp/quota-report-$(date +%Y%m%d_%H%M%S).txt}"
    local include_details="${2:-true}"
    
    log "Generating quota report..."
    
    cat > "$output_file" << EOF
Mailcow Quota Usage Report
Generated: $(date)
==========================

Configuration:
- Warning Threshold: ${QUOTA_WARNING_THRESHOLD}%
- Critical Threshold: ${QUOTA_CRITICAL_THRESHOLD}%
- Default Domain Quota: ${DEFAULT_DOMAIN_QUOTA}MB
- Default Mailbox Quota: ${DEFAULT_MAILBOX_QUOTA}MB

EOF
    
    # Domain summary
    echo "Domain Summary:" >> "$output_file"
    echo "===============" >> "$output_file"
    
    local total_domains=0
    local warning_domains=0
    local critical_domains=0
    
    local domains=$(python3 "$API_SCRIPT" domain list 2>/dev/null | grep "Domain:" | awk '{print $2}')
    
    for domain in $domains; do
        ((total_domains++))
        
        local quota_info=$(python3 "$API_SCRIPT" domain list | grep -A 5 "Domain: $domain" | grep "Quota:" | awk '{print $2}')
        local quota_mb=$(echo "$quota_info" | cut -d'M' -f1)
        local used_mb=$(get_domain_usage "$domain")
        local usage_percent=0
        
        if [[ $quota_mb -gt 0 ]]; then
            usage_percent=$((used_mb * 100 / quota_mb))
        fi
        
        if [[ $usage_percent -ge $QUOTA_CRITICAL_THRESHOLD ]]; then
            ((critical_domains++))
        elif [[ $usage_percent -ge $QUOTA_WARNING_THRESHOLD ]]; then
            ((warning_domains++))
        fi
        
        if [[ "$include_details" == "true" ]]; then
            printf "%-30s %6d MB / %6d MB (%3d%%)\n" "$domain" "$used_mb" "$quota_mb" "$usage_percent" >> "$output_file"
        fi
    done
    
    echo "" >> "$output_file"
    echo "Total Domains: $total_domains" >> "$output_file"
    echo "Warning Level: $warning_domains" >> "$output_file"
    echo "Critical Level: $critical_domains" >> "$output_file"
    echo "" >> "$output_file"
    
    # Mailbox summary
    echo "Mailbox Summary:" >> "$output_file"
    echo "================" >> "$output_file"
    
    local total_mailboxes=0
    local warning_mailboxes=0
    local critical_mailboxes=0
    
    local mailboxes=$(python3 "$API_SCRIPT" mailbox list 2>/dev/null | grep "Email:" | awk '{print $2}')
    
    for email in $mailboxes; do
        ((total_mailboxes++))
        
        local quota_info=$(python3 "$API_SCRIPT" mailbox list | grep -A 5 "Email: $email" | grep "Quota:" | awk '{print $2}')
        local quota_mb=$(echo "$quota_info" | cut -d'M' -f1)
        local used_mb=$(get_mailbox_usage "$email")
        local usage_percent=0
        
        if [[ $quota_mb -gt 0 ]]; then
            usage_percent=$((used_mb * 100 / quota_mb))
        fi
        
        if [[ $usage_percent -ge $QUOTA_CRITICAL_THRESHOLD ]]; then
            ((critical_mailboxes++))
        elif [[ $usage_percent -ge $QUOTA_WARNING_THRESHOLD ]]; then
            ((warning_mailboxes++))
        fi
        
        if [[ "$include_details" == "true" && $usage_percent -ge $QUOTA_WARNING_THRESHOLD ]]; then
            printf "%-40s %6d MB / %6d MB (%3d%%)\n" "$email" "$used_mb" "$quota_mb" "$usage_percent" >> "$output_file"
        fi
    done
    
    echo "" >> "$output_file"
    echo "Total Mailboxes: $total_mailboxes" >> "$output_file"
    echo "Warning Level: $warning_mailboxes" >> "$output_file"
    echo "Critical Level: $critical_mailboxes" >> "$output_file"
    echo "" >> "$output_file"
    
    # Recommendations
    if [[ $critical_domains -gt 0 || $critical_mailboxes -gt 0 ]]; then
        echo "Recommendations:" >> "$output_file"
        echo "================" >> "$output_file"
        echo "- Immediate action required for critical quota usage" >> "$output_file"
        echo "- Consider increasing quotas or cleaning up old emails" >> "$output_file"
        echo "- Review quota policies and thresholds" >> "$output_file"
        echo "" >> "$output_file"
    fi
    
    echo "Report generated: $(date)" >> "$output_file"
    
    info "Quota report saved to: $output_file"
    cat "$output_file"
}

# Show usage
show_usage() {
    cat << EOF
Mailcow Quota and Policy Manager

Usage: $0 [action] [target] [options]

Actions:
  set-mailbox <email> <quota_mb> [--force]
    Set quota for a specific mailbox
    
  set-domain <domain> <quota_mb> [--force]
    Set quota for a domain
    
  list [type] [format] [--no-warnings]
    List quota usage (type: mailbox, domain, both)
    
  usage <email|domain>
    Show current usage for mailbox or domain
    
  policies [warning_percent] [critical_percent]
    Set or view quota policies
    
  report [output_file] [--no-details]
    Generate comprehensive quota report

Options:
  --force           Apply quota even if less than current usage
  --format FORMAT   Output format (table, json, csv)
  --no-warnings     Don't show quota warnings
  --no-details      Exclude detailed usage in report
  --help           Show this help message

Quota Limits:
  Minimum: ${MIN_QUOTA}MB
  Maximum: ${MAX_QUOTA}MB
  
Default Quotas:
  Domain: ${DEFAULT_DOMAIN_QUOTA}MB
  Mailbox: ${DEFAULT_MAILBOX_QUOTA}MB

Policy Thresholds:
  Warning: ${QUOTA_WARNING_THRESHOLD}%
  Critical: ${QUOTA_CRITICAL_THRESHOLD}%

Examples:
  $0 set-mailbox user@example.com 2048
  $0 set-domain example.com 10240 --force
  $0 list mailbox table
  $0 usage user@example.com
  $0 policies 75 90
  $0 report /tmp/quota-report.txt

EOF
}

# Main function
main() {
    local action="$1"
    shift
    
    # Load configuration
    load_config
    
    case "$action" in
        "set-mailbox")
            local force=""
            for arg in "$@"; do
                if [[ "$arg" == "--force" ]]; then
                    force="true"
                    break
                fi
            done
            set_mailbox_quota "$1" "$2" "$force"
            ;;
        "set-domain")
            local force=""
            for arg in "$@"; do
                if [[ "$arg" == "--force" ]]; then
                    force="true"
                    break
                fi
            done
            set_domain_quota "$1" "$2" "$force"
            ;;
        "list")
            local no_warnings=""
            for arg in "$@"; do
                if [[ "$arg" == "--no-warnings" ]]; then
                    no_warnings="false"
                    break
                fi
            done
            list_quota_usage "$1" "$2" "${no_warnings:-true}"
            ;;
        "usage")
            if [[ "$1" =~ @ ]]; then
                # It's an email address
                local usage=$(get_mailbox_usage "$1")
                echo "Current usage for $1: ${usage}MB"
            else
                # It's a domain
                local usage=$(get_domain_usage "$1")
                echo "Current usage for $1: ${usage}MB"
            fi
            ;;
        "policies")
            if [[ -n "$1" && -n "$2" ]]; then
                set_quota_policies "$1" "$2"
            else
                echo "Current Quota Policies:"
                echo "======================"
                echo "Warning threshold: ${QUOTA_WARNING_THRESHOLD}%"
                echo "Critical threshold: ${QUOTA_CRITICAL_THRESHOLD}%"
                echo "Default domain quota: ${DEFAULT_DOMAIN_QUOTA}MB"
                echo "Default mailbox quota: ${DEFAULT_MAILBOX_QUOTA}MB"
            fi
            ;;
        "report")
            local no_details=""
            for arg in "$@"; do
                if [[ "$arg" == "--no-details" ]]; then
                    no_details="false"
                    break
                fi
            done
            generate_quota_report "$1" "${no_details:-true}"
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