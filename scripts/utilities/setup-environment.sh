#!/bin/bash
#
# Environment Setup Script for Cold Email Infrastructure
# Sets up all necessary environment variables and paths
#

# Determine script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export EMAIL_INFRA_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Core directory paths
export EMAIL_INFRA_SRC="$EMAIL_INFRA_ROOT/src/email-infrastructure"
export EMAIL_INFRA_CONFIG="$EMAIL_INFRA_ROOT/config"
export EMAIL_INFRA_DOCS="$EMAIL_INFRA_ROOT/docs"
export EMAIL_INFRA_SCRIPTS="$EMAIL_INFRA_ROOT/scripts"
export EMAIL_INFRA_DATA="$EMAIL_INFRA_ROOT/data"

# Data subdirectories
export EMAIL_INFRA_LOGS="$EMAIL_INFRA_DATA/logs"
export EMAIL_INFRA_BACKUPS="$EMAIL_INFRA_DATA/backups"
export EMAIL_INFRA_CACHE="$EMAIL_INFRA_DATA/cache"
export EMAIL_INFRA_DATABASES="$EMAIL_INFRA_DATA/databases"

# Component-specific paths
export DNS_PATH="$EMAIL_INFRA_SRC/dns"
export DNS_CONFIG="$DNS_PATH/config"
export DNS_SCRIPTS="$DNS_PATH/scripts"

export MAILCOW_PATH="$EMAIL_INFRA_SRC/mailcow"
export MAILCOW_CONFIG="$MAILCOW_PATH/config"
export MAILCOW_AUTOMATION="$MAILCOW_PATH/automation"

export MONITORING_PATH="$EMAIL_INFRA_SRC/monitoring"
export MONITORING_CONFIG="$MONITORING_PATH/config"
export MONITORING_SCRIPTS="$MONITORING_PATH/scripts"

export VPS_PATH="$EMAIL_INFRA_SRC/vps"
export VPS_CONFIG="$VPS_PATH/config"
export VPS_SCRIPTS="$VPS_PATH/scripts"

# Environment detection
if [[ -z "$EMAIL_INFRA_ENV" ]]; then
    if [[ -f "$EMAIL_INFRA_CONFIG/environments/production.yaml" ]]; then
        export EMAIL_INFRA_ENV="production"
    elif [[ -f "$EMAIL_INFRA_CONFIG/environments/staging.yaml" ]]; then
        export EMAIL_INFRA_ENV="staging"
    else
        export EMAIL_INFRA_ENV="development"
    fi
fi

echo "Email Infrastructure Environment: $EMAIL_INFRA_ENV"

# Create necessary directories
mkdir -p "$EMAIL_INFRA_LOGS" "$EMAIL_INFRA_BACKUPS" "$EMAIL_INFRA_CACHE" "$EMAIL_INFRA_DATABASES"

# Add component scripts to PATH for easy execution
export PATH="$DNS_SCRIPTS:$PATH"
export PATH="$MAILCOW_AUTOMATION:$PATH"
export PATH="$MONITORING_SCRIPTS:$PATH"
export PATH="$VPS_SCRIPTS:$PATH"
export PATH="$EMAIL_INFRA_SCRIPTS:$PATH"

# Python path for imports
export PYTHONPATH="$EMAIL_INFRA_SRC:$PYTHONPATH"

# Logging configuration
export EMAIL_INFRA_LOG_LEVEL="${EMAIL_INFRA_LOG_LEVEL:-INFO}"
export EMAIL_INFRA_LOG_FORMAT="${EMAIL_INFRA_LOG_FORMAT:-%Y-%m-%d %H:%M:%S}"

# Function to verify environment setup
verify_environment() {
    echo "=== Email Infrastructure Environment Verification ==="
    echo "Project Root: $EMAIL_INFRA_ROOT"
    echo "Environment: $EMAIL_INFRA_ENV"
    echo "Source Directory: $EMAIL_INFRA_SRC"
    echo "Configuration Directory: $EMAIL_INFRA_CONFIG"
    echo "Logs Directory: $EMAIL_INFRA_LOGS"
    echo ""
    
    # Check critical directories exist
    local critical_dirs=(
        "$EMAIL_INFRA_SRC"
        "$EMAIL_INFRA_CONFIG"
        "$DNS_PATH"
        "$MAILCOW_PATH"
        "$MONITORING_PATH"
        "$VPS_PATH"
    )
    
    for dir in "${critical_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            echo "✓ $dir exists"
        else
            echo "✗ $dir missing"
        fi
    done
    
    echo "=== Environment Setup Complete ==="
}

# Auto-verify if run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    verify_environment
fi