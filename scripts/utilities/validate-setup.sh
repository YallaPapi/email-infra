#!/bin/bash
#
# Validation Script for Cold Email Infrastructure
# Validates the complete installation and configuration
#

set -e

# Source environment setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/setup-environment.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Validation results
VALIDATION_PASSED=0
VALIDATION_FAILED=0
VALIDATION_WARNINGS=0

# Logging functions
log_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((VALIDATION_PASSED++))
}

log_fail() {
    echo -e "${RED}✗${NC} $1"
    ((VALIDATION_FAILED++))
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((VALIDATION_WARNINGS++))
}

log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Test network connectivity
test_connectivity() {
    local host="$1"
    local port="$2"
    timeout 5 bash -c "</dev/tcp/$host/$port" 2>/dev/null
}

# Validate command line arguments
DOMAIN="$1"
SERVER_IP="$2"

if [[ -z "$DOMAIN" ]] || [[ -z "$SERVER_IP" ]]; then
    echo "Usage: $0 <domain> <server_ip>"
    echo "Example: $0 mail.example.com 192.168.1.100"
    exit 1
fi

echo "========================================="
echo "Cold Email Infrastructure Validation"
echo "========================================="
echo "Domain: $DOMAIN"
echo "Server IP: $SERVER_IP"
echo "Environment: $EMAIL_INFRA_ENV"
echo "========================================="

# 1. Directory Structure Validation
log_info "Validating directory structure..."

required_dirs=(
    "$EMAIL_INFRA_SRC"
    "$EMAIL_INFRA_CONFIG"
    "$DNS_PATH"
    "$MAILCOW_PATH"
    "$MONITORING_PATH"
    "$VPS_PATH"
    "$EMAIL_INFRA_LOGS"
    "$EMAIL_INFRA_BACKUPS"
)

for dir in "${required_dirs[@]}"; do
    if [[ -d "$dir" ]]; then
        log_pass "Directory exists: $dir"
    else
        log_fail "Directory missing: $dir"
    fi
done

# 2. Configuration Files Validation
log_info "Validating configuration files..."

config_files=(
    "$EMAIL_INFRA_CONFIG/global-config.yaml"
    "$EMAIL_INFRA_CONFIG/environments/$EMAIL_INFRA_ENV.yaml"
    "$DNS_CONFIG/cloudflare-config.yaml"
    "$MAILCOW_CONFIG/mailcow-config.yaml"
)

for config_file in "${config_files[@]}"; do
    if [[ -f "$config_file" ]]; then
        log_pass "Configuration file exists: $config_file"
        # Test YAML syntax
        if command_exists python3; then
            if python3 -c "import yaml; yaml.safe_load(open('$config_file'))" 2>/dev/null; then
                log_pass "YAML syntax valid: $config_file"
            else
                log_warn "YAML syntax issues: $config_file"
            fi
        fi
    else
        log_warn "Configuration file missing: $config_file"
    fi
done

# 3. Script Permissions Validation
log_info "Validating script permissions..."

script_files=(
    "$DNS_SCRIPTS/record-generator.sh"
    "$MAILCOW_AUTOMATION/install-mailcow.sh"
    "$VPS_SCRIPTS/setup-vps.sh"
    "$EMAIL_INFRA_SCRIPTS/utilities/setup-environment.sh"
)

for script_file in "${script_files[@]}"; do
    if [[ -f "$script_file" ]]; then
        if [[ -x "$script_file" ]]; then
            log_pass "Script executable: $script_file"
        else
            log_warn "Script not executable: $script_file"
        fi
    else
        log_warn "Script missing: $script_file"
    fi
done

# 4. Python Environment Validation
log_info "Validating Python environment..."

if command_exists python3; then
    log_pass "Python3 available"
    python_version=$(python3 --version 2>&1 | cut -d' ' -f2)
    log_info "Python version: $python_version"
    
    # Test Python imports
    python_imports=(
        "yaml"
        "requests"
        "dns.resolver"
    )
    
    for module in "${python_imports[@]}"; do
        if python3 -c "import $module" 2>/dev/null; then
            log_pass "Python module available: $module"
        else
            log_warn "Python module missing: $module"
        fi
    done
    
    # Test email_infrastructure imports
    if PYTHONPATH="$EMAIL_INFRA_SRC" python3 -c "from email_infrastructure.core.config_manager import config_manager" 2>/dev/null; then
        log_pass "Email infrastructure Python package importable"
    else
        log_fail "Email infrastructure Python package import failed"
    fi
else
    log_fail "Python3 not available"
fi

# 5. DNS Resolution Validation
log_info "Validating DNS configuration..."

if command_exists dig; then
    # Test A record
    if dig +short "$DOMAIN" | grep -q "$SERVER_IP"; then
        log_pass "DNS A record resolves correctly: $DOMAIN -> $SERVER_IP"
    else
        log_warn "DNS A record not resolving to expected IP: $DOMAIN"
    fi
    
    # Test MX record
    mx_record=$(dig +short MX "$DOMAIN" | awk '{print $2}' | head -1)
    if [[ -n "$mx_record" ]]; then
        log_pass "MX record exists: $mx_record"
    else
        log_warn "MX record not found for $DOMAIN"
    fi
    
    # Test SPF record
    if dig +short TXT "$DOMAIN" | grep -q "v=spf1"; then
        log_pass "SPF record exists"
    else
        log_warn "SPF record not found"
    fi
    
    # Test DMARC record
    if dig +short TXT "_dmarc.$DOMAIN" | grep -q "v=DMARC1"; then
        log_pass "DMARC record exists"
    else
        log_warn "DMARC record not found"
    fi
else
    log_warn "dig command not available - skipping DNS validation"
fi

# 6. Service Validation
log_info "Validating services..."

# Check for Docker (Mailcow requirement)
if command_exists docker; then
    log_pass "Docker available"
    if systemctl is-active --quiet docker; then
        log_pass "Docker service running"
    else
        log_warn "Docker service not running"
    fi
else
    log_warn "Docker not available"
fi

# Check for docker-compose
if command_exists docker-compose; then
    log_pass "Docker Compose available"
else
    log_warn "Docker Compose not available"
fi

# 7. Network Connectivity Validation
log_info "Validating network connectivity..."

# Test SMTP connectivity (port 25, 587, 465)
smtp_ports=(25 587 465)
for port in "${smtp_ports[@]}"; do
    if test_connectivity "$SERVER_IP" "$port"; then
        log_pass "SMTP port $port accessible"
    else
        log_warn "SMTP port $port not accessible"
    fi
done

# Test HTTP/HTTPS connectivity (port 80, 443)
web_ports=(80 443)
for port in "${web_ports[@]}"; do
    if test_connectivity "$SERVER_IP" "$port"; then
        log_pass "Web port $port accessible"
    else
        log_warn "Web port $port not accessible"
    fi
done

# 8. Mailcow Validation (if installed)
log_info "Validating Mailcow installation..."

mailcow_path="/opt/mailcow-dockerized"
if [[ -d "$mailcow_path" ]]; then
    log_pass "Mailcow directory exists"
    
    if [[ -f "$mailcow_path/docker-compose.yml" ]]; then
        log_pass "Mailcow docker-compose.yml exists"
    else
        log_warn "Mailcow docker-compose.yml missing"
    fi
    
    if [[ -f "$mailcow_path/mailcow.conf" ]]; then
        log_pass "Mailcow configuration file exists"
    else
        log_warn "Mailcow configuration file missing"
    fi
    
    # Check if containers are running
    if command_exists docker-compose; then
        cd "$mailcow_path"
        if docker-compose ps | grep -q "Up"; then
            log_pass "Mailcow containers are running"
        else
            log_warn "Mailcow containers not running"
        fi
    fi
else
    log_warn "Mailcow not installed"
fi

# 9. Final Summary
echo ""
echo "========================================="
echo "Validation Summary"
echo "========================================="
echo -e "Passed: ${GREEN}$VALIDATION_PASSED${NC}"
echo -e "Failed: ${RED}$VALIDATION_FAILED${NC}"
echo -e "Warnings: ${YELLOW}$VALIDATION_WARNINGS${NC}"
echo "========================================="

if [[ $VALIDATION_FAILED -gt 0 ]]; then
    echo -e "${RED}Validation completed with failures${NC}"
    echo "Please review and fix the failed items above."
    exit 1
elif [[ $VALIDATION_WARNINGS -gt 0 ]]; then
    echo -e "${YELLOW}Validation completed with warnings${NC}"
    echo "System should be functional but review warnings above."
    exit 0
else
    echo -e "${GREEN}Validation completed successfully${NC}"
    echo "Cold Email Infrastructure is properly configured!"
    exit 0
fi