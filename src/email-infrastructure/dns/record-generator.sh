#!/bin/bash

# DNS Record Generator for Cold Email Infrastructure
# Generates all required DNS records for email deliverability

set -euo pipefail

# Script directory and configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}"
LOG_FILE="/var/log/dns-record-generator.log"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log "ERROR: $1"
    exit 1
}

# Usage information
usage() {
    cat << EOF
DNS Record Generator for Cold Email Infrastructure

Usage: $0 [OPTIONS]

OPTIONS:
    -d, --domain DOMAIN         Target domain name (required)
    -s, --subdomain SUBDOMAIN   Mail subdomain (default: mail)
    -i, --ip IP_ADDRESS         Server IP address (required)
    -p, --ptr-ip PTR_IP         PTR record IP (default: same as server IP)
    -k, --dkim-selector SELECTOR DKIM selector (default: default)
    -m, --mx-priority PRIORITY  MX record priority (default: 10)
    -t, --ttl TTL               DNS record TTL (default: 300)
    -f, --format FORMAT         Output format (json|yaml|bind|cloudflare) (default: json)
    -o, --output FILE           Output file path
    --backup                    Create backup file
    --validate                  Validate generated records
    --deploy                    Deploy records to Cloudflare
    --spf-include INCLUDES      Additional SPF includes (comma-separated)
    --dmarc-policy POLICY       DMARC policy (none|quarantine|reject) (default: quarantine)
    --dmarc-email EMAIL         DMARC report email
    --reverse-dns RDNS          Reverse DNS hostname
    --help                      Show this help message

Examples:
    $0 -d example.com -i 192.168.1.100
    $0 -d example.com -i 192.168.1.100 -s mail -k selector1 --deploy
    $0 -d example.com -i 192.168.1.100 --format yaml -o records.yaml

EOF
}

# Default values
DOMAIN=""
SUBDOMAIN="mail"
SERVER_IP=""
PTR_IP=""
DKIM_SELECTOR="default"
MX_PRIORITY=10
TTL=300
OUTPUT_FORMAT="json"
OUTPUT_FILE=""
CREATE_BACKUP=false
VALIDATE_RECORDS=false
DEPLOY_RECORDS=false
SPF_INCLUDES=""
DMARC_POLICY="quarantine"
DMARC_EMAIL=""
REVERSE_DNS=""

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--domain)
                DOMAIN="$2"
                shift 2
                ;;
            -s|--subdomain)
                SUBDOMAIN="$2"
                shift 2
                ;;
            -i|--ip)
                SERVER_IP="$2"
                shift 2
                ;;
            -p|--ptr-ip)
                PTR_IP="$2"
                shift 2
                ;;
            -k|--dkim-selector)
                DKIM_SELECTOR="$2"
                shift 2
                ;;
            -m|--mx-priority)
                MX_PRIORITY="$2"
                shift 2
                ;;
            -t|--ttl)
                TTL="$2"
                shift 2
                ;;
            -f|--format)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            --backup)
                CREATE_BACKUP=true
                shift
                ;;
            --validate)
                VALIDATE_RECORDS=true
                shift
                ;;
            --deploy)
                DEPLOY_RECORDS=true
                shift
                ;;
            --spf-include)
                SPF_INCLUDES="$2"
                shift 2
                ;;
            --dmarc-policy)
                DMARC_POLICY="$2"
                shift 2
                ;;
            --dmarc-email)
                DMARC_EMAIL="$2"
                shift 2
                ;;
            --reverse-dns)
                REVERSE_DNS="$2"
                shift 2
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                error_exit "Unknown option: $1"
                ;;
        esac
    done
}

# Validate required parameters
validate_params() {
    [[ -z "$DOMAIN" ]] && error_exit "Domain is required (-d/--domain)"
    [[ -z "$SERVER_IP" ]] && error_exit "Server IP is required (-i/--ip)"
    
    # Set default values
    [[ -z "$PTR_IP" ]] && PTR_IP="$SERVER_IP"
    [[ -z "$REVERSE_DNS" ]] && REVERSE_DNS="${SUBDOMAIN}.${DOMAIN}"
    [[ -z "$DMARC_EMAIL" ]] && DMARC_EMAIL="postmaster@${DOMAIN}"
    
    # Validate IP address format
    if ! [[ $SERVER_IP =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        error_exit "Invalid IP address format: $SERVER_IP"
    fi
    
    # Validate domain format
    if ! [[ $DOMAIN =~ ^[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9]*\.[a-zA-Z]{2,}$ ]]; then
        error_exit "Invalid domain format: $DOMAIN"
    fi
    
    # Validate DMARC policy
    if ! [[ $DMARC_POLICY =~ ^(none|quarantine|reject)$ ]]; then
        error_exit "Invalid DMARC policy. Must be: none, quarantine, or reject"
    fi
    
    log "Validated parameters for domain: $DOMAIN"
}

# Generate DKIM public key placeholder
generate_dkim_key() {
    local selector="$1"
    
    # Check if DKIM keys exist
    local private_key="/etc/opendkim/keys/${DOMAIN}/${selector}.private"
    local public_key="/etc/opendkim/keys/${DOMAIN}/${selector}.txt"
    
    if [[ -f "$public_key" ]]; then
        # Extract public key from existing file
        grep -o 'v=DKIM1;[^"]*' "$public_key" 2>/dev/null || echo "v=DKIM1;k=rsa;p=PLACEHOLDER_PUBLIC_KEY"
    else
        echo "v=DKIM1;k=rsa;p=PLACEHOLDER_PUBLIC_KEY"
    fi
}

# Generate SPF record
generate_spf_record() {
    local spf_record="v=spf1"
    
    # Add IP addresses
    spf_record+=" ip4:${SERVER_IP}"
    
    # Add mail server
    spf_record+=" a:${SUBDOMAIN}.${DOMAIN}"
    
    # Add additional includes if specified
    if [[ -n "$SPF_INCLUDES" ]]; then
        IFS=',' read -ra INCLUDES <<< "$SPF_INCLUDES"
        for include in "${INCLUDES[@]}"; do
            spf_record+=" include:${include}"
        done
    fi
    
    # Add default includes for common email services
    spf_record+=" include:_spf.google.com"
    spf_record+=" include:amazonses.com"
    
    # Fail policy
    spf_record+=" ~all"
    
    echo "$spf_record"
}

# Generate DMARC record
generate_dmarc_record() {
    local dmarc_record="v=DMARC1"
    dmarc_record+=";p=${DMARC_POLICY}"
    dmarc_record+=";rua=mailto:${DMARC_EMAIL}"
    dmarc_record+=";ruf=mailto:${DMARC_EMAIL}"
    dmarc_record+=";fo=1"
    dmarc_record+=";adkim=r"
    dmarc_record+=";aspf=r"
    dmarc_record+=";pct=100"
    dmarc_record+=";rf=afrf"
    dmarc_record+=";ri=86400"
    
    echo "$dmarc_record"
}

# Generate all DNS records
generate_dns_records() {
    log "Generating DNS records for $DOMAIN"
    
    local dkim_public_key
    dkim_public_key=$(generate_dkim_key "$DKIM_SELECTOR")
    
    local spf_record
    spf_record=$(generate_spf_record)
    
    local dmarc_record
    dmarc_record=$(generate_dmarc_record)
    
    # Create records array based on format
    case "$OUTPUT_FORMAT" in
        "json")
            generate_json_records "$spf_record" "$dmarc_record" "$dkim_public_key"
            ;;
        "yaml")
            generate_yaml_records "$spf_record" "$dmarc_record" "$dkim_public_key"
            ;;
        "bind")
            generate_bind_records "$spf_record" "$dmarc_record" "$dkim_public_key"
            ;;
        "cloudflare")
            generate_cloudflare_records "$spf_record" "$dmarc_record" "$dkim_public_key"
            ;;
        *)
            error_exit "Unsupported output format: $OUTPUT_FORMAT"
            ;;
    esac
}

# Generate JSON format records
generate_json_records() {
    local spf_record="$1"
    local dmarc_record="$2"
    local dkim_public_key="$3"
    
    cat << EOF
{
  "domain": "${DOMAIN}",
  "generated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "records": [
    {
      "type": "A",
      "name": "${DOMAIN}",
      "content": "${SERVER_IP}",
      "ttl": ${TTL},
      "comment": "Main domain A record"
    },
    {
      "type": "A",
      "name": "${SUBDOMAIN}",
      "content": "${SERVER_IP}",
      "ttl": ${TTL},
      "comment": "Mail server A record"
    },
    {
      "type": "A",
      "name": "www",
      "content": "${SERVER_IP}",
      "ttl": ${TTL},
      "comment": "WWW subdomain A record"
    },
    {
      "type": "MX",
      "name": "${DOMAIN}",
      "content": "${SUBDOMAIN}.${DOMAIN}",
      "priority": ${MX_PRIORITY},
      "ttl": ${TTL},
      "comment": "Primary mail exchanger"
    },
    {
      "type": "MX",
      "name": "${DOMAIN}",
      "content": "${SUBDOMAIN}.${DOMAIN}",
      "priority": $((MX_PRIORITY + 10)),
      "ttl": ${TTL},
      "comment": "Backup mail exchanger"
    },
    {
      "type": "TXT",
      "name": "${DOMAIN}",
      "content": "${spf_record}",
      "ttl": ${TTL},
      "comment": "SPF record for email authentication"
    },
    {
      "type": "TXT",
      "name": "_dmarc",
      "content": "${dmarc_record}",
      "ttl": ${TTL},
      "comment": "DMARC policy record"
    },
    {
      "type": "TXT",
      "name": "${DKIM_SELECTOR}._domainkey",
      "content": "${dkim_public_key}",
      "ttl": ${TTL},
      "comment": "DKIM public key"
    },
    {
      "type": "TXT",
      "name": "_domainkey",
      "content": "o=~",
      "ttl": ${TTL},
      "comment": "Domain key policy"
    },
    {
      "type": "CNAME",
      "name": "autoconfig",
      "content": "${SUBDOMAIN}.${DOMAIN}",
      "ttl": ${TTL},
      "comment": "Thunderbird autoconfig"
    },
    {
      "type": "CNAME",
      "name": "autodiscover",
      "content": "${SUBDOMAIN}.${DOMAIN}",
      "ttl": ${TTL},
      "comment": "Outlook autodiscover"
    },
    {
      "type": "SRV",
      "name": "_submission._tcp",
      "content": "0 1 587 ${SUBDOMAIN}.${DOMAIN}",
      "ttl": ${TTL},
      "comment": "Mail submission service"
    },
    {
      "type": "SRV",
      "name": "_imap._tcp",
      "content": "0 1 143 ${SUBDOMAIN}.${DOMAIN}",
      "ttl": ${TTL},
      "comment": "IMAP service"
    },
    {
      "type": "SRV",
      "name": "_imaps._tcp",
      "content": "0 1 993 ${SUBDOMAIN}.${DOMAIN}",
      "ttl": ${TTL},
      "comment": "IMAPS service"
    },
    {
      "type": "SRV",
      "name": "_pop3._tcp",
      "content": "0 1 110 ${SUBDOMAIN}.${DOMAIN}",
      "ttl": ${TTL},
      "comment": "POP3 service"
    },
    {
      "type": "SRV",
      "name": "_pop3s._tcp",
      "content": "0 1 995 ${SUBDOMAIN}.${DOMAIN}",
      "ttl": ${TTL},
      "comment": "POP3S service"
    }
  ]
}
EOF
}

# Generate YAML format records
generate_yaml_records() {
    local spf_record="$1"
    local dmarc_record="$2"
    local dkim_public_key="$3"
    
    cat << EOF
domain: ${DOMAIN}
generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
delete_extra: false
records:
  - type: A
    name: ${DOMAIN}
    content: ${SERVER_IP}
    ttl: ${TTL}
    comment: "Main domain A record"
    
  - type: A
    name: ${SUBDOMAIN}
    content: ${SERVER_IP}
    ttl: ${TTL}
    comment: "Mail server A record"
    
  - type: A
    name: www
    content: ${SERVER_IP}
    ttl: ${TTL}
    comment: "WWW subdomain A record"
    
  - type: MX
    name: ${DOMAIN}
    content: ${SUBDOMAIN}.${DOMAIN}
    priority: ${MX_PRIORITY}
    ttl: ${TTL}
    comment: "Primary mail exchanger"
    
  - type: MX
    name: ${DOMAIN}
    content: ${SUBDOMAIN}.${DOMAIN}
    priority: $((MX_PRIORITY + 10))
    ttl: ${TTL}
    comment: "Backup mail exchanger"
    
  - type: TXT
    name: ${DOMAIN}
    content: "${spf_record}"
    ttl: ${TTL}
    comment: "SPF record for email authentication"
    
  - type: TXT
    name: _dmarc
    content: "${dmarc_record}"
    ttl: ${TTL}
    comment: "DMARC policy record"
    
  - type: TXT
    name: ${DKIM_SELECTOR}._domainkey
    content: "${dkim_public_key}"
    ttl: ${TTL}
    comment: "DKIM public key"
    
  - type: TXT
    name: _domainkey
    content: "o=~"
    ttl: ${TTL}
    comment: "Domain key policy"
    
  - type: CNAME
    name: autoconfig
    content: ${SUBDOMAIN}.${DOMAIN}
    ttl: ${TTL}
    comment: "Thunderbird autoconfig"
    
  - type: CNAME
    name: autodiscover
    content: ${SUBDOMAIN}.${DOMAIN}
    ttl: ${TTL}
    comment: "Outlook autodiscover"
    
  - type: SRV
    name: _submission._tcp
    content: "0 1 587 ${SUBDOMAIN}.${DOMAIN}"
    ttl: ${TTL}
    comment: "Mail submission service"
    
  - type: SRV
    name: _imap._tcp
    content: "0 1 143 ${SUBDOMAIN}.${DOMAIN}"
    ttl: ${TTL}
    comment: "IMAP service"
    
  - type: SRV
    name: _imaps._tcp
    content: "0 1 993 ${SUBDOMAIN}.${DOMAIN}"
    ttl: ${TTL}
    comment: "IMAPS service"
    
  - type: SRV
    name: _pop3._tcp
    content: "0 1 110 ${SUBDOMAIN}.${DOMAIN}"
    ttl: ${TTL}
    comment: "POP3 service"
    
  - type: SRV
    name: _pop3s._tcp
    content: "0 1 995 ${SUBDOMAIN}.${DOMAIN}"
    ttl: ${TTL}
    comment: "POP3S service"
EOF
}

# Generate BIND zone file format
generate_bind_records() {
    local spf_record="$1"
    local dmarc_record="$2"
    local dkim_public_key="$3"
    
    cat << EOF
; DNS Zone File for ${DOMAIN}
; Generated on $(date)
; Cold Email Infrastructure

\$TTL ${TTL}
@       IN      SOA     ${SUBDOMAIN}.${DOMAIN}. postmaster.${DOMAIN}. (
                        $(date +%Y%m%d%H)  ; Serial
                        7200               ; Refresh
                        3600               ; Retry
                        604800             ; Expire
                        86400 )            ; Minimum TTL

; Name servers
@       IN      NS      ns1.cloudflare.com.
@       IN      NS      ns2.cloudflare.com.

; A records
@       IN      A       ${SERVER_IP}
${SUBDOMAIN}    IN      A       ${SERVER_IP}
www     IN      A       ${SERVER_IP}

; MX records
@       IN      MX      ${MX_PRIORITY}      ${SUBDOMAIN}.${DOMAIN}.
@       IN      MX      $((MX_PRIORITY + 10))  ${SUBDOMAIN}.${DOMAIN}.

; TXT records
@       IN      TXT     "${spf_record}"
_dmarc  IN      TXT     "${dmarc_record}"
${DKIM_SELECTOR}._domainkey IN TXT "${dkim_public_key}"
_domainkey IN   TXT     "o=~"

; CNAME records
autoconfig      IN      CNAME   ${SUBDOMAIN}.${DOMAIN}.
autodiscover    IN      CNAME   ${SUBDOMAIN}.${DOMAIN}.

; SRV records
_submission._tcp IN     SRV     0 1 587 ${SUBDOMAIN}.${DOMAIN}.
_imap._tcp      IN      SRV     0 1 143 ${SUBDOMAIN}.${DOMAIN}.
_imaps._tcp     IN      SRV     0 1 993 ${SUBDOMAIN}.${DOMAIN}.
_pop3._tcp      IN      SRV     0 1 110 ${SUBDOMAIN}.${DOMAIN}.
_pop3s._tcp     IN      SRV     0 1 995 ${SUBDOMAIN}.${DOMAIN}.
EOF
}

# Generate Cloudflare-specific format
generate_cloudflare_records() {
    local spf_record="$1"
    local dmarc_record="$2"
    local dkim_public_key="$3"
    
    cat << EOF
# Cloudflare DNS Records for ${DOMAIN}
# Generated on $(date)
# Use with: wrangler dns record create

# A Records
wrangler dns record create ${DOMAIN} --type A --name @ --content ${SERVER_IP} --ttl ${TTL}
wrangler dns record create ${DOMAIN} --type A --name ${SUBDOMAIN} --content ${SERVER_IP} --ttl ${TTL}
wrangler dns record create ${DOMAIN} --type A --name www --content ${SERVER_IP} --ttl ${TTL}

# MX Records
wrangler dns record create ${DOMAIN} --type MX --name @ --content "${SUBDOMAIN}.${DOMAIN}" --priority ${MX_PRIORITY} --ttl ${TTL}

# TXT Records
wrangler dns record create ${DOMAIN} --type TXT --name @ --content "${spf_record}" --ttl ${TTL}
wrangler dns record create ${DOMAIN} --type TXT --name _dmarc --content "${dmarc_record}" --ttl ${TTL}
wrangler dns record create ${DOMAIN} --type TXT --name ${DKIM_SELECTOR}._domainkey --content "${dkim_public_key}" --ttl ${TTL}
wrangler dns record create ${DOMAIN} --type TXT --name _domainkey --content "o=~" --ttl ${TTL}

# CNAME Records
wrangler dns record create ${DOMAIN} --type CNAME --name autoconfig --content "${SUBDOMAIN}.${DOMAIN}" --ttl ${TTL}
wrangler dns record create ${DOMAIN} --type CNAME --name autodiscover --content "${SUBDOMAIN}.${DOMAIN}" --ttl ${TTL}

# SRV Records
wrangler dns record create ${DOMAIN} --type SRV --name _submission._tcp --content "0 1 587 ${SUBDOMAIN}.${DOMAIN}" --ttl ${TTL}
wrangler dns record create ${DOMAIN} --type SRV --name _imap._tcp --content "0 1 143 ${SUBDOMAIN}.${DOMAIN}" --ttl ${TTL}
wrangler dns record create ${DOMAIN} --type SRV --name _imaps._tcp --content "0 1 993 ${SUBDOMAIN}.${DOMAIN}" --ttl ${TTL}
wrangler dns record create ${DOMAIN} --type SRV --name _pop3._tcp --content "0 1 110 ${SUBDOMAIN}.${DOMAIN}" --ttl ${TTL}
wrangler dns record create ${DOMAIN} --type SRV --name _pop3s._tcp --content "0 1 995 ${SUBDOMAIN}.${DOMAIN}" --ttl ${TTL}
EOF
}

# Create backup of existing records
create_backup() {
    if [[ "$CREATE_BACKUP" == "true" ]]; then
        log "Creating backup of existing DNS records"
        
        local backup_file="${DOMAIN}-dns-backup-$(date +%Y%m%d-%H%M%S).json"
        
        if command -v python3 >/dev/null 2>&1 && [[ -f "${SCRIPT_DIR}/dns-manager.py" ]]; then
            python3 "${SCRIPT_DIR}/dns-manager.py" backup --domain "$DOMAIN" --backup "$backup_file" || {
                log "Warning: Could not create backup using dns-manager.py"
            }
        else
            log "Warning: dns-manager.py not found, skipping backup"
        fi
    fi
}

# Validate generated records
validate_generated_records() {
    if [[ "$VALIDATE_RECORDS" == "true" ]]; then
        log "Validating generated DNS records"
        
        # Basic validation checks
        local validation_errors=0
        
        # Check if SPF record is not too long (max 255 characters)
        local spf_record
        spf_record=$(generate_spf_record)
        if [[ ${#spf_record} -gt 255 ]]; then
            log "ERROR: SPF record too long (${#spf_record} characters, max 255)"
            ((validation_errors++))
        fi
        
        # Check DMARC record format
        local dmarc_record
        dmarc_record=$(generate_dmarc_record)
        if ! [[ $dmarc_record =~ ^v=DMARC1 ]]; then
            log "ERROR: Invalid DMARC record format"
            ((validation_errors++))
        fi
        
        # Check domain format in records
        if ! [[ $DOMAIN =~ ^[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9]*\.[a-zA-Z]{2,}$ ]]; then
            log "ERROR: Invalid domain format in records"
            ((validation_errors++))
        fi
        
        if [[ $validation_errors -eq 0 ]]; then
            log "Validation passed: All records appear valid"
        else
            log "Validation failed: $validation_errors errors found"
            return 1
        fi
    fi
    
    return 0
}

# Deploy records to Cloudflare
deploy_to_cloudflare() {
    if [[ "$DEPLOY_RECORDS" == "true" ]]; then
        log "Deploying DNS records to Cloudflare"
        
        if ! command -v python3 >/dev/null 2>&1; then
            error_exit "Python3 is required for deployment"
        fi
        
        if [[ ! -f "${SCRIPT_DIR}/dns-manager.py" ]]; then
            error_exit "dns-manager.py not found in script directory"
        fi
        
        # Generate records in YAML format for deployment
        local temp_file="/tmp/${DOMAIN}-records-$(date +%s).yaml"
        generate_yaml_records "$(generate_spf_record)" "$(generate_dmarc_record)" "$(generate_dkim_key "$DKIM_SELECTOR")" > "$temp_file"
        
        # Deploy using DNS manager
        if python3 "${SCRIPT_DIR}/dns-manager.py" sync --domain "$DOMAIN" --template "$temp_file"; then
            log "Successfully deployed DNS records to Cloudflare"
            rm -f "$temp_file"
        else
            error_exit "Failed to deploy DNS records to Cloudflare"
        fi
    fi
}

# Generate PTR record information
generate_ptr_info() {
    log "PTR Record Information:"
    log "IP Address: $PTR_IP"
    log "Hostname: $REVERSE_DNS"
    log ""
    log "Contact your hosting provider to set up the following PTR record:"
    log "PTR $PTR_IP -> $REVERSE_DNS"
    log ""
    log "Reverse DNS zone: $(echo "$PTR_IP" | awk -F. '{print $3"."$2"."$1".in-addr.arpa"}')"
}

# Output results
output_records() {
    local content
    content=$(generate_dns_records)
    
    if [[ -n "$OUTPUT_FILE" ]]; then
        echo "$content" > "$OUTPUT_FILE"
        log "DNS records saved to: $OUTPUT_FILE"
    else
        echo "$content"
    fi
    
    # Generate PTR information
    echo ""
    generate_ptr_info
    
    # Show summary
    echo ""
    log "DNS Records Summary for $DOMAIN:"
    log "- Domain: $DOMAIN"
    log "- Mail Server: ${SUBDOMAIN}.${DOMAIN}"
    log "- Server IP: $SERVER_IP"
    log "- DKIM Selector: $DKIM_SELECTOR"
    log "- MX Priority: $MX_PRIORITY"
    log "- TTL: $TTL"
    log "- Format: $OUTPUT_FORMAT"
}

# Main execution function
main() {
    log "Starting DNS record generation"
    
    parse_args "$@"
    validate_params
    
    # Create backup if requested
    create_backup
    
    # Validate records if requested
    if ! validate_generated_records; then
        error_exit "Record validation failed"
    fi
    
    # Output the records
    output_records
    
    # Deploy if requested
    deploy_to_cloudflare
    
    log "DNS record generation completed successfully"
}

# Execute main function with all arguments
main "$@"