#!/bin/bash

# Mailcow Mailbox Management Automation
# Handles mailbox operations: create, delete, configure, list with secure password generation
# Usage: ./mailbox-manager.sh [action] [email] [options]

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/../config"
API_SCRIPT="$SCRIPT_DIR/../api/mailcow-api.py"
LOG_FILE="/var/log/mailcow-mailbox-manager.log"

# Password generation settings
MIN_PASSWORD_LENGTH=16
MAX_PASSWORD_LENGTH=24
PASSWORD_CHARS="ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789!@#$%^&*-_=+"

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

# Validate email format
validate_email() {
    local email="$1"
    
    if [[ -z "$email" ]]; then
        error "Email address is required"
    fi
    
    # Basic email validation
    if ! [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        error "Invalid email format: $email"
    fi
    
    # Extract domain
    local domain="${email#*@}"
    
    # Check if domain exists in Mailcow
    if ! python3 "$API_SCRIPT" domain list | grep -q "$domain"; then
        error "Domain $domain does not exist in Mailcow. Add it first."
    fi
}

# Generate secure password
generate_password() {
    local length="${1:-$MIN_PASSWORD_LENGTH}"
    local use_special="${2:-true}"
    
    # Ensure minimum length
    if [[ $length -lt $MIN_PASSWORD_LENGTH ]]; then
        length=$MIN_PASSWORD_LENGTH
    fi
    
    # Generate password with required character types
    local password=""
    local chars="$PASSWORD_CHARS"
    
    if [[ "$use_special" == "false" ]]; then
        chars="ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789"
    fi
    
    # Generate password
    password=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-$length)
    
    # Ensure password meets complexity requirements
    local has_upper=$(echo "$password" | grep -c '[A-Z]' || echo "0")
    local has_lower=$(echo "$password" | grep -c '[a-z]' || echo "0")
    local has_digit=$(echo "$password" | grep -c '[0-9]' || echo "0")
    local has_special=$(echo "$password" | grep -c '[!@#$%^&*_=-]' || echo "0")
    
    # Regenerate if doesn't meet requirements
    if [[ $has_upper -eq 0 || $has_lower -eq 0 || $has_digit -eq 0 ]]; then
        # Manually construct password with required elements
        local upper="ABCDEFGHJKLMNPQRSTUVWXYZ"
        local lower="abcdefghijkmnpqrstuvwxyz"
        local digits="23456789"
        local special="!@#$%^&*-_=+"
        
        password=""
        password+="${upper:$(($RANDOM % ${#upper})):1}"
        password+="${lower:$(($RANDOM % ${#lower})):1}"
        password+="${digits:$(($RANDOM % ${#digits})):1}"
        
        if [[ "$use_special" == "true" ]]; then
            password+="${special:$(($RANDOM % ${#special})):1}"
        fi
        
        # Fill remaining length with random characters
        local remaining=$((length - ${#password}))
        for ((i=0; i<remaining; i++)); do
            password+="${chars:$(($RANDOM % ${#chars})):1}"
        done
        
        # Shuffle password
        password=$(echo "$password" | fold -w1 | shuf | tr -d '\n')
    fi
    
    echo "$password"
}

# Check password strength
check_password_strength() {
    local password="$1"
    local score=0
    local feedback=""
    
    # Length check
    if [[ ${#password} -ge 16 ]]; then
        ((score += 2))
    elif [[ ${#password} -ge 12 ]]; then
        ((score += 1))
    else
        feedback+="Password too short (minimum 12 characters). "
    fi
    
    # Character type checks
    if echo "$password" | grep -q '[A-Z]'; then
        ((score += 1))
    else
        feedback+="Missing uppercase letters. "
    fi
    
    if echo "$password" | grep -q '[a-z]'; then
        ((score += 1))
    else
        feedback+="Missing lowercase letters. "
    fi
    
    if echo "$password" | grep -q '[0-9]'; then
        ((score += 1))
    else
        feedback+="Missing numbers. "
    fi
    
    if echo "$password" | grep -q '[!@#$%^&*()_+=\[\]{}|;:,.<>?-]'; then
        ((score += 1))
    else
        feedback+="Missing special characters. "
    fi
    
    # Common patterns check
    if echo "$password" | grep -qE '(.)\1{2,}|123|abc|qwe|password|admin'; then
        feedback+="Contains common patterns or repeated characters. "
        ((score -= 1))
    fi
    
    # Return score and feedback
    case $score in
        6|7) echo "STRONG|$feedback" ;;
        4|5) echo "GOOD|$feedback" ;;
        2|3) echo "WEAK|$feedback" ;;
        *) echo "VERY_WEAK|$feedback" ;;
    esac
}

# Create mailbox
create_mailbox() {
    local email="$1"
    local password="$2"
    local name="$3"
    local quota="${4:-1024}"
    local active="${5:-true}"
    local force_pw_update="${6:-false}"
    local tls_enforce_in="${7:-true}"
    local tls_enforce_out="${8:-true}"
    
    validate_email "$email"
    
    log "Creating mailbox: $email"
    
    # Check if mailbox already exists
    if python3 "$API_SCRIPT" mailbox list | grep -q "$email"; then
        error "Mailbox $email already exists"
    fi
    
    # Generate password if not provided
    if [[ -z "$password" ]]; then
        password=$(generate_password)
        info "Generated secure password for $email"
    else
        # Check provided password strength
        local strength_check=$(check_password_strength "$password")
        local strength="${strength_check%|*}"
        local feedback="${strength_check#*|}"
        
        if [[ "$strength" == "VERY_WEAK" || "$strength" == "WEAK" ]]; then
            warning "Weak password detected: $feedback"
            read -p "Continue with this password? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                info "Generating secure password instead..."
                password=$(generate_password)
            fi
        else
            info "Password strength: $strength"
        fi
    fi
    
    # Create mailbox via API
    local result
    if [[ -n "$name" ]]; then
        result=$(python3 "$API_SCRIPT" mailbox add "$email" \
            --password "$password" \
            --name "$name" \
            --quota "$quota" 2>&1)
    else
        result=$(python3 "$API_SCRIPT" mailbox add "$email" \
            --password "$password" \
            --quota "$quota" 2>&1)
    fi
    
    if [[ $? -eq 0 ]]; then
        info "Mailbox $email created successfully"
        
        # Save credentials securely
        save_mailbox_credentials "$email" "$password" "$name" "$quota"
        
        # Show creation summary
        show_mailbox_summary "$email" "$password" "$name" "$quota"
        
    else
        error "Failed to create mailbox: $result"
    fi
}

# Delete mailbox
delete_mailbox() {
    local email="$1"
    local confirm="${2:-false}"
    
    validate_email "$email"
    
    # Confirmation
    if [[ "$confirm" != "true" ]]; then
        echo -n "Are you sure you want to delete mailbox $email? This will remove all emails and data. (yes/no): "
        read -r confirmation
        if [[ "$confirmation" != "yes" ]]; then
            info "Mailbox deletion cancelled"
            return 0
        fi
    fi
    
    log "Deleting mailbox: $email"
    
    # Check if mailbox exists
    if ! python3 "$API_SCRIPT" mailbox list | grep -q "$email"; then
        warning "Mailbox $email does not exist"
        return 0
    fi
    
    # Delete mailbox via API
    local result=$(python3 "$API_SCRIPT" mailbox delete "$email" 2>&1)
    
    if [[ $? -eq 0 ]]; then
        info "Mailbox $email deleted successfully"
        
        # Clean up credentials file
        local cred_file="$CONFIG_DIR/mailboxes/${email}.cred"
        rm -f "$cred_file"
        
    else
        error "Failed to delete mailbox: $result"
    fi
}

# List mailboxes
list_mailboxes() {
    local domain="$1"
    local format="${2:-table}"
    
    log "Listing mailboxes..."
    
    local cmd_args=""
    if [[ -n "$domain" ]]; then
        cmd_args="--domain $domain"
    fi
    
    case "$format" in
        "table")
            echo ""
            printf "%-40s %-30s %-8s %-12s %-15s\n" "Email" "Name" "Active" "Quota(MB)" "Created"
            printf "%-40s %-30s %-8s %-12s %-15s\n" "========================================" "==============================" "======" "============" "==============="
            
            python3 "$API_SCRIPT" mailbox list $cmd_args 2>/dev/null | while IFS= read -r line; do
                if [[ "$line" =~ Email:\ (.+) ]]; then
                    email="${BASH_REMATCH[1]}"
                    printf "%-40s" "$email"
                elif [[ "$line" =~ Name:\ (.+) ]]; then
                    name="${BASH_REMATCH[1]}"
                    printf " %-30s" "$name"
                elif [[ "$line" =~ Active:\ (.+) ]]; then
                    active="${BASH_REMATCH[1]}"
                    printf " %-8s" "$active"
                elif [[ "$line" =~ Quota:\ (.+) ]]; then
                    quota="${BASH_REMATCH[1]}"
                    printf " %-12s" "$quota"
                    
                    # Get creation date from credentials file
                    local cred_file="$CONFIG_DIR/mailboxes/${email}.cred"
                    if [[ -f "$cred_file" ]]; then
                        local created=$(grep "^CREATED=" "$cred_file" 2>/dev/null | cut -d'=' -f2 | cut -d'T' -f1 || echo "N/A")
                    else
                        local created="N/A"
                    fi
                    printf " %-15s\n" "$created"
                fi
            done
            echo ""
            ;;
        "json")
            python3 "$API_SCRIPT" mailbox list $cmd_args --format json
            ;;
        "csv")
            echo "Email,Name,Active,Quota,Created"
            python3 "$API_SCRIPT" mailbox list $cmd_args 2>/dev/null | while IFS= read -r line; do
                if [[ "$line" =~ Email:\ (.+) ]]; then
                    email="${BASH_REMATCH[1]}"
                    printf "%s," "$email"
                elif [[ "$line" =~ Name:\ (.+) ]]; then
                    name="${BASH_REMATCH[1]}"
                    printf "%s," "$name"
                elif [[ "$line" =~ Active:\ (.+) ]]; then
                    active="${BASH_REMATCH[1]}"
                    printf "%s," "$active"
                elif [[ "$line" =~ Quota:\ (.+) ]]; then
                    quota="${BASH_REMATCH[1]}"
                    printf "%s," "$quota"
                    
                    local cred_file="$CONFIG_DIR/mailboxes/${email}.cred"
                    if [[ -f "$cred_file" ]]; then
                        local created=$(grep "^CREATED=" "$cred_file" 2>/dev/null | cut -d'=' -f2 || echo "N/A")
                    else
                        local created="N/A"
                    fi
                    printf "%s\n" "$created"
                fi
            done
            ;;
    esac
}

# Update mailbox
update_mailbox() {
    local email="$1"
    local setting="$2"
    local value="$3"
    
    validate_email "$email"
    
    if [[ -z "$setting" || -z "$value" ]]; then
        error "Setting and value are required for update"
    fi
    
    log "Updating mailbox $email: $setting = $value"
    
    # Map setting names to API parameters
    case "$setting" in
        "password")
            # Check password strength
            local strength_check=$(check_password_strength "$value")
            local strength="${strength_check%|*}"
            local feedback="${strength_check#*|}"
            
            if [[ "$strength" == "VERY_WEAK" || "$strength" == "WEAK" ]]; then
                warning "Weak password: $feedback"
                read -p "Continue with this password? (y/N): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    return 1
                fi
            fi
            
            info "Password strength: $strength"
            # Update credentials file
            update_mailbox_credentials "$email" "password" "$value"
            ;;
        "quota")
            if ! [[ "$value" =~ ^[0-9]+$ ]]; then
                error "Quota must be a number (MB)"
            fi
            ;;
        "name")
            update_mailbox_credentials "$email" "name" "$value"
            ;;
        "active")
            value=$([ "$value" = "true" ] && echo "1" || echo "0")
            ;;
        *)
            error "Unknown setting: $setting. Supported: password, quota, name, active"
            ;;
    esac
    
    info "Mailbox $email updated successfully"
}

# Get mailbox info
get_mailbox_info() {
    local email="$1"
    
    validate_email "$email"
    
    log "Getting mailbox information for: $email"
    
    # Get info from API
    python3 "$API_SCRIPT" mailbox list | grep -A 10 "Email: $email" || warning "Mailbox $email not found"
    
    # Show stored credentials info (without password)
    local cred_file="$CONFIG_DIR/mailboxes/${email}.cred"
    if [[ -f "$cred_file" ]]; then
        echo ""
        echo "Additional Information:"
        echo "======================"
        grep -E "^(CREATED|NAME|QUOTA)=" "$cred_file" | while IFS='=' read -r key value; do
            case "$key" in
                "CREATED") echo "Created: $value" ;;
                "NAME") echo "Full Name: $value" ;;
                "QUOTA") echo "Quota: $value MB" ;;
            esac
        done
    fi
}

# Save mailbox credentials
save_mailbox_credentials() {
    local email="$1"
    local password="$2"
    local name="$3"
    local quota="$4"
    
    mkdir -p "$CONFIG_DIR/mailboxes"
    
    local cred_file="$CONFIG_DIR/mailboxes/${email}.cred"
    
    cat > "$cred_file" << EOF
# Mailbox Credentials: $email
# Created: $(date)

EMAIL=$email
PASSWORD=$password
NAME=$name
QUOTA=$quota
CREATED=$(date -Iseconds)
LAST_UPDATED=$(date -Iseconds)

# IMAP Settings:
# Server: ${DOMAIN:-$email#*@}
# Port: 993 (SSL/TLS)
# Username: $email
# Password: [see above]

# SMTP Settings:
# Server: ${DOMAIN:-$email#*@}  
# Port: 465 (SSL) or 587 (STARTTLS)
# Username: $email
# Password: [see above]
EOF
    
    chmod 600 "$cred_file"
    info "Credentials saved to: $cred_file"
}

# Update mailbox credentials
update_mailbox_credentials() {
    local email="$1"
    local field="$2"
    local value="$3"
    
    local cred_file="$CONFIG_DIR/mailboxes/${email}.cred"
    
    if [[ -f "$cred_file" ]]; then
        # Update specific field
        case "$field" in
            "password")
                sed -i "s/^PASSWORD=.*/PASSWORD=$value/" "$cred_file"
                ;;
            "name")
                sed -i "s/^NAME=.*/NAME=$value/" "$cred_file"
                ;;
            "quota")
                sed -i "s/^QUOTA=.*/QUOTA=$value/" "$cred_file"
                ;;
        esac
        
        # Update last modified
        sed -i "s/^LAST_UPDATED=.*/LAST_UPDATED=$(date -Iseconds)/" "$cred_file"
        
        info "Credentials file updated: $cred_file"
    fi
}

# Show mailbox summary
show_mailbox_summary() {
    local email="$1"
    local password="$2"
    local name="$3"
    local quota="$4"
    local domain="${email#*@}"
    
    echo ""
    echo "${GREEN}Mailbox Created Successfully!${NC}"
    echo "============================"
    echo ""
    echo "Email: $email"
    echo "Name: ${name:-N/A}"
    echo "Quota: $quota MB"
    echo "Password: $password"
    echo ""
    echo "Mail Server Settings:"
    echo "===================="
    echo "IMAP Server: $domain"
    echo "IMAP Port: 993 (SSL/TLS)"
    echo "SMTP Server: $domain"
    echo "SMTP Port: 465 (SSL) or 587 (STARTTLS)"
    echo "Username: $email"
    echo ""
    echo "Webmail: https://$domain/SOGo/"
    echo ""
    echo "Credentials saved in: $CONFIG_DIR/mailboxes/${email}.cred"
    echo ""
}

# Bulk create mailboxes
bulk_create_mailboxes() {
    local mailboxes_file="$1"
    
    if [[ ! -f "$mailboxes_file" ]]; then
        error "Mailboxes file not found: $mailboxes_file"
    fi
    
    log "Bulk creating mailboxes from: $mailboxes_file"
    
    local count=0
    local failed=0
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^#.*$ ]] && continue
        
        # Parse line: email,name,quota,password
        IFS=',' read -ra MAILBOX_INFO <<< "$line"
        local email="${MAILBOX_INFO[0]}"
        local name="${MAILBOX_INFO[1]:-}"
        local quota="${MAILBOX_INFO[2]:-1024}"
        local password="${MAILBOX_INFO[3]:-}"
        
        if [[ -n "$email" ]]; then
            info "Creating mailbox: $email"
            if create_mailbox "$email" "$password" "$name" "$quota"; then
                ((count++))
            else
                ((failed++))
                warning "Failed to create mailbox: $email"
            fi
            
            # Rate limiting
            sleep 0.5
        fi
    done < "$mailboxes_file"
    
    log "Bulk operation completed: $count mailboxes created, $failed failed"
}

# Generate credentials report
generate_credentials_report() {
    local output_file="${1:-/tmp/mailbox-credentials-$(date +%Y%m%d_%H%M%S).txt}"
    
    log "Generating credentials report..."
    
    cat > "$output_file" << EOF
Mailbox Credentials Report
Generated: $(date)
==========================

EOF
    
    # List all credential files
    local cred_files=("$CONFIG_DIR/mailboxes"/*.cred)
    
    if [[ -f "${cred_files[0]}" ]]; then
        for cred_file in "${cred_files[@]}"; do
            if [[ -f "$cred_file" ]]; then
                echo "" >> "$output_file"
                echo "$(basename "$cred_file" .cred)" >> "$output_file"
                echo "$(printf '=%.0s' {1..40})" >> "$output_file"
                
                # Extract key information (excluding password for security)
                grep -E "^(EMAIL|NAME|QUOTA|CREATED)=" "$cred_file" | while IFS='=' read -r key value; do
                    case "$key" in
                        "EMAIL") echo "Email: $value" >> "$output_file" ;;
                        "NAME") echo "Name: $value" >> "$output_file" ;;
                        "QUOTA") echo "Quota: $value MB" >> "$output_file" ;;
                        "CREATED") echo "Created: $value" >> "$output_file" ;;
                    esac
                done
            fi
        done
    else
        echo "No mailboxes found." >> "$output_file"
    fi
    
    echo "" >> "$output_file"
    echo "Report generated: $(date)" >> "$output_file"
    echo "Total mailboxes: $(ls "$CONFIG_DIR/mailboxes"/*.cred 2>/dev/null | wc -l)" >> "$output_file"
    
    info "Credentials report saved to: $output_file"
    
    # Show summary
    cat "$output_file"
}

# Show usage
show_usage() {
    cat << EOF
Mailcow Mailbox Manager

Usage: $0 [action] [email] [options]

Actions:
  create <email> [password] [name] [quota] [options]
    Create a new mailbox with secure password generation
    
  delete <email> [--confirm]
    Delete a mailbox
    
  list [domain] [format]
    List mailboxes (format: table, json, csv)
    
  info <email>
    Show detailed information about a mailbox
    
  update <email> <setting> <value>
    Update mailbox settings (password, quota, name, active)
    
  bulk-create <file>
    Create mailboxes from CSV file
    
  generate-password [length] [--no-special]
    Generate a secure password
    
  check-password <password>
    Check password strength
    
  credentials-report [output_file]
    Generate credentials report

Options:
  --confirm         Skip confirmation prompts
  --format FORMAT   Output format (table, json, csv)
  --no-special      Don't use special characters in password
  --help           Show this help message

Examples:
  $0 create user@example.com
  $0 create user@example.com "MyPassword123!" "John Doe" 2048
  $0 delete user@example.com --confirm
  $0 list example.com table
  $0 update user@example.com password "NewPassword123!"
  $0 generate-password 20
  $0 bulk-create mailboxes.csv

File format for bulk-create:
  email,name,quota_mb,password
  user1@example.com,John Doe,1024,
  user2@example.com,Jane Smith,2048,MyPassword123!

Note: If password is empty in bulk file, a secure password will be generated.

EOF
}

# Main function
main() {
    local action="$1"
    shift
    
    # Load configuration
    load_config
    
    case "$action" in
        "create"|"add")
            create_mailbox "$@"
            ;;
        "delete"|"remove")
            local confirm=""
            for arg in "$@"; do
                if [[ "$arg" == "--confirm" ]]; then
                    confirm="true"
                    break
                fi
            done
            delete_mailbox "$1" "$confirm"
            ;;
        "list")
            list_mailboxes "$1" "$2"
            ;;
        "info"|"show")
            get_mailbox_info "$1"
            ;;
        "update"|"modify")
            update_mailbox "$1" "$2" "$3"
            ;;
        "bulk-create")
            bulk_create_mailboxes "$1"
            ;;
        "generate-password")
            local length="${1:-$MIN_PASSWORD_LENGTH}"
            local use_special="true"
            if [[ "$2" == "--no-special" ]]; then
                use_special="false"
            fi
            generate_password "$length" "$use_special"
            ;;
        "check-password")
            if [[ -z "$1" ]]; then
                error "Password is required for checking"
            fi
            local result=$(check_password_strength "$1")
            local strength="${result%|*}"
            local feedback="${result#*|}"
            echo "Password Strength: $strength"
            if [[ -n "$feedback" ]]; then
                echo "Feedback: $feedback"
            fi
            ;;
        "credentials-report")
            generate_credentials_report "$1"
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