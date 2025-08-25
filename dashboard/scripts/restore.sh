#!/bin/bash

# Cold Email Dashboard Restore Script
# Restores dashboard from backup archives

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_BASE_DIR="${BACKUP_BASE_DIR:-/opt/cold-email-dashboard/backups}"
RESTORE_DIR="/tmp/dashboard-restore-$$"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# List available backups
list_backups() {
    log_info "Available backups:"
    
    if [[ -d "$BACKUP_BASE_DIR" ]]; then
        local backups=($(ls -t "$BACKUP_BASE_DIR"/dashboard_backup_*.tar.gz 2>/dev/null || true))
        
        if [[ ${#backups[@]} -eq 0 ]]; then
            log_warning "No backups found in $BACKUP_BASE_DIR"
            return 1
        fi
        
        echo ""
        echo "Local Backups:"
        echo "=============="
        for i in "${!backups[@]}"; do
            local backup_file="${backups[$i]}"
            local backup_name=$(basename "$backup_file" .tar.gz)
            local backup_size=$(du -sh "$backup_file" | cut -f1)
            local backup_date=$(stat -c %y "$backup_file" | cut -d. -f1)
            
            printf "%2d) %s (%s) - %s\n" $((i+1)) "$backup_name" "$backup_size" "$backup_date"
        done
        echo ""
        
        return 0
    else
        log_error "Backup directory not found: $BACKUP_BASE_DIR"
        return 1
    fi
}

# Download backup from S3 (if needed)
download_from_s3() {
    local backup_name="$1"
    
    if [[ -z "$S3_BUCKET" ]]; then
        log_error "S3 bucket not configured"
        return 1
    fi
    
    if ! command -v aws >/dev/null 2>&1; then
        log_error "AWS CLI not installed"
        return 1
    fi
    
    log_info "Downloading backup from S3..."
    
    local s3_path="s3://$S3_BUCKET/dashboard-backups/${backup_name}.tar.gz"
    local local_path="$BACKUP_BASE_DIR/${backup_name}.tar.gz"
    
    if [[ -n "$S3_ENDPOINT" ]]; then
        aws s3 cp "$s3_path" "$local_path" --endpoint-url "$S3_ENDPOINT"
    else
        aws s3 cp "$s3_path" "$local_path"
    fi
    
    log_success "Backup downloaded from S3"
}

# Select backup to restore
select_backup() {
    local backup_file="$1"
    
    if [[ -n "$backup_file" ]]; then
        # Use provided backup file
        if [[ -f "$backup_file" ]]; then
            echo "$backup_file"
            return 0
        elif [[ -f "$BACKUP_BASE_DIR/$backup_file" ]]; then
            echo "$BACKUP_BASE_DIR/$backup_file"
            return 0
        elif [[ -f "$BACKUP_BASE_DIR/${backup_file}.tar.gz" ]]; then
            echo "$BACKUP_BASE_DIR/${backup_file}.tar.gz"
            return 0
        else
            log_error "Backup file not found: $backup_file"
            return 1
        fi
    fi
    
    # Interactive selection
    list_backups || return 1
    
    local backups=($(ls -t "$BACKUP_BASE_DIR"/dashboard_backup_*.tar.gz 2>/dev/null))
    
    echo -n "Select backup to restore [1-${#backups[@]}]: "
    read -r selection
    
    if [[ "$selection" =~ ^[0-9]+$ ]] && [[ $selection -ge 1 ]] && [[ $selection -le ${#backups[@]} ]]; then
        echo "${backups[$((selection-1))]}"
        return 0
    else
        log_error "Invalid selection"
        return 1
    fi
}

# Extract backup
extract_backup() {
    local backup_file="$1"
    
    log_info "Extracting backup: $(basename "$backup_file")"
    
    # Create temporary restore directory
    mkdir -p "$RESTORE_DIR"
    
    # Extract backup
    tar -xzf "$backup_file" -C "$RESTORE_DIR" --strip-components=1
    
    # Verify extraction
    if [[ ! -f "$RESTORE_DIR/metadata/backup-info.json" ]]; then
        log_error "Invalid backup format - missing metadata"
        return 1
    fi
    
    log_success "Backup extracted to: $RESTORE_DIR"
    
    # Display backup information
    if command -v jq >/dev/null 2>&1; then
        log_info "Backup Information:"
        jq -r '
            "  Backup ID: " + .backup_id,
            "  Created: " + .created_at,
            "  Hostname: " + .hostname,
            "  Size: " + (.size_bytes | tostring) + " bytes",
            "  Components: " + ([.components | to_entries[] | select(.value == true) | .key] | join(", "))
        ' "$RESTORE_DIR/metadata/backup-info.json"
    fi
}

# Create pre-restore backup
create_pre_restore_backup() {
    log_info "Creating pre-restore backup..."
    
    local pre_restore_name="pre_restore_backup_$(date +%Y%m%d_%H%M%S)"
    local backup_script="$SCRIPT_DIR/backup.sh"
    
    if [[ -f "$backup_script" ]]; then
        BACKUP_NAME="$pre_restore_name" "$backup_script" full
        log_success "Pre-restore backup created: $pre_restore_name"
    else
        log_warning "Backup script not found, skipping pre-restore backup"
    fi
}

# Stop services
stop_services() {
    log_info "Stopping dashboard services..."
    
    # Stop dashboard service
    if systemctl is-active --quiet cold-email-dashboard 2>/dev/null; then
        systemctl stop cold-email-dashboard
        log_success "Dashboard service stopped"
    else
        log_info "Dashboard service was not running"
    fi
    
    # Stop nginx if needed
    if systemctl is-active --quiet nginx 2>/dev/null; then
        systemctl stop nginx
        log_success "Nginx stopped"
    fi
}

# Restore configuration files
restore_configuration() {
    log_info "Restoring configuration files..."
    
    local config_dir="$RESTORE_DIR/config"
    
    if [[ ! -d "$config_dir" ]]; then
        log_warning "No configuration files to restore"
        return 0
    fi
    
    # Restore dashboard configuration
    if [[ -f "$config_dir/dashboard.env" ]]; then
        mkdir -p /etc/cold-email-dashboard
        cp "$config_dir/dashboard.env" /etc/cold-email-dashboard/
        chown root:dashboard /etc/cold-email-dashboard/dashboard.env
        chmod 640 /etc/cold-email-dashboard/dashboard.env
        log_success "Dashboard configuration restored"
    fi
    
    # Restore systemd service
    if [[ -f "$config_dir/cold-email-dashboard.service" ]]; then
        cp "$config_dir/cold-email-dashboard.service" /etc/systemd/system/
        systemctl daemon-reload
        log_success "Systemd service file restored"
    fi
    
    # Restore nginx configuration
    if [[ -f "$config_dir/nginx-dashboard.conf" ]]; then
        cp "$config_dir/nginx-dashboard.conf" /etc/nginx/sites-available/dashboard
        
        # Enable site if not already enabled
        if [[ ! -L /etc/nginx/sites-enabled/dashboard ]]; then
            ln -s /etc/nginx/sites-available/dashboard /etc/nginx/sites-enabled/dashboard
        fi
        
        log_success "Nginx configuration restored"
    fi
    
    # Restore SSL certificates
    if [[ -d "$config_dir/ssl" ]]; then
        mkdir -p /etc/letsencrypt/live
        cp -r "$config_dir/ssl"/* /etc/letsencrypt/live/ 2>/dev/null || true
        log_success "SSL certificates restored"
    fi
}

# Restore application files
restore_application() {
    log_info "Restoring application files..."
    
    local app_file="$RESTORE_DIR/application/dashboard-app.tar.gz"
    
    if [[ ! -f "$app_file" ]]; then
        log_warning "No application files to restore"
        return 0
    fi
    
    # Backup existing application
    if [[ -d /opt/cold-email-dashboard/dashboard ]]; then
        mv /opt/cold-email-dashboard/dashboard /opt/cold-email-dashboard/dashboard.backup.$(date +%Y%m%d_%H%M%S)
        log_info "Existing application backed up"
    fi
    
    # Extract application
    mkdir -p /opt/cold-email-dashboard
    tar -xzf "$app_file" -C /opt/cold-email-dashboard
    
    # Set ownership
    chown -R dashboard:dashboard /opt/cold-email-dashboard/dashboard
    
    # Make scripts executable
    chmod +x /opt/cold-email-dashboard/dashboard/*.sh 2>/dev/null || true
    
    log_success "Application files restored"
}

# Restore database
restore_database() {
    log_info "Restoring database..."
    
    local db_dir="$RESTORE_DIR/database"
    
    if [[ ! -d "$db_dir" ]]; then
        log_warning "No database files to restore"
        return 0
    fi
    
    # Restore SQLite database
    if [[ -f "$db_dir/dashboard.db" ]]; then
        mkdir -p /opt/cold-email-dashboard/data
        cp "$db_dir/dashboard.db" /opt/cold-email-dashboard/data/
        chown dashboard:dashboard /opt/cold-email-dashboard/data/dashboard.db
        log_success "SQLite database restored"
    fi
    
    # Restore PostgreSQL database
    if [[ -f "$db_dir/postgresql.sql" ]] && command -v psql >/dev/null 2>&1; then
        if [[ -n "${DB_NAME:-}" ]]; then
            psql "${DB_NAME}" < "$db_dir/postgresql.sql"
            log_success "PostgreSQL database restored"
        else
            log_warning "DB_NAME not set, skipping PostgreSQL restore"
        fi
    fi
    
    # Restore Redis data
    if [[ -f "$db_dir/dump.rdb" ]]; then
        systemctl stop redis-server 2>/dev/null || true
        cp "$db_dir/dump.rdb" /var/lib/redis/
        chown redis:redis /var/lib/redis/dump.rdb
        systemctl start redis-server 2>/dev/null || true
        log_success "Redis data restored"
    fi
}

# Restore logs (optional)
restore_logs() {
    log_info "Restoring log files..."
    
    local logs_dir="$RESTORE_DIR/logs"
    
    if [[ ! -d "$logs_dir" ]]; then
        log_warning "No log files to restore"
        return 0
    fi
    
    # Restore application logs
    if [[ -f "$logs_dir/application-logs.tar.gz" ]]; then
        mkdir -p /var/log
        tar -xzf "$logs_dir/application-logs.tar.gz" -C /var/log
        chown -R dashboard:dashboard /var/log/cold-email-dashboard 2>/dev/null || true
        log_success "Application logs restored"
    fi
    
    # Restore nginx logs
    if [[ -d "$logs_dir/nginx" ]]; then
        cp "$logs_dir/nginx"/* /var/log/nginx/ 2>/dev/null || true
        log_success "Nginx logs restored"
    fi
}

# Start services
start_services() {
    log_info "Starting dashboard services..."
    
    # Test nginx configuration
    if command -v nginx >/dev/null 2>&1; then
        if nginx -t; then
            systemctl start nginx
            log_success "Nginx started"
        else
            log_error "Nginx configuration is invalid"
        fi
    fi
    
    # Start dashboard service
    systemctl enable cold-email-dashboard
    systemctl start cold-email-dashboard
    
    # Wait for service to start
    sleep 5
    
    if systemctl is-active --quiet cold-email-dashboard; then
        log_success "Dashboard service started"
    else
        log_error "Dashboard service failed to start"
        log_info "Service status:"
        systemctl status cold-email-dashboard --no-pager
        return 1
    fi
}

# Verify restore
verify_restore() {
    log_info "Verifying restore..."
    
    local errors=0
    
    # Check if dashboard is responding
    if ! curl -s -f http://localhost:5000/api/health >/dev/null; then
        log_error "Dashboard health check failed"
        ((errors++))
    else
        log_success "Dashboard is responding"
    fi
    
    # Check service status
    if ! systemctl is-active --quiet cold-email-dashboard; then
        log_error "Dashboard service is not running"
        ((errors++))
    else
        log_success "Dashboard service is running"
    fi
    
    # Check nginx status
    if command -v nginx >/dev/null 2>&1; then
        if ! systemctl is-active --quiet nginx; then
            log_warning "Nginx is not running"
        else
            log_success "Nginx is running"
        fi
    fi
    
    # Check file permissions
    if [[ -f /etc/cold-email-dashboard/dashboard.env ]]; then
        local perms=$(stat -c %a /etc/cold-email-dashboard/dashboard.env)
        if [[ "$perms" != "640" ]]; then
            log_warning "Configuration file permissions may be incorrect: $perms"
        fi
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_success "Restore verification completed successfully"
        return 0
    else
        log_error "Restore verification failed with $errors errors"
        return 1
    fi
}

# Cleanup restore files
cleanup_restore() {
    log_info "Cleaning up temporary files..."
    
    if [[ -d "$RESTORE_DIR" ]]; then
        rm -rf "$RESTORE_DIR"
        log_success "Temporary files cleaned up"
    fi
}

# Show restore summary
show_summary() {
    log_success "Restore completed!"
    
    echo ""
    echo "=== Restore Summary ==="
    echo "Services Status:"
    systemctl is-active cold-email-dashboard && echo "  Dashboard: Running" || echo "  Dashboard: Not Running"
    systemctl is-active nginx && echo "  Nginx: Running" || echo "  Nginx: Not Running"
    echo ""
    echo "=== Access Information ==="
    echo "Dashboard: http://localhost:5000"
    echo "Health Check: http://localhost:5000/api/health"
    echo ""
    echo "=== Next Steps ==="
    echo "1. Verify all functionality is working"
    echo "2. Check logs: journalctl -u cold-email-dashboard -f"
    echo "3. Update configuration if needed"
    echo "4. Monitor system performance"
}

# Main restore function
main() {
    local backup_file="$1"
    local restore_mode="${2:-full}"
    
    log_info "Starting Cold Email Dashboard restore..."
    
    check_root
    
    # Select backup
    local selected_backup
    selected_backup=$(select_backup "$backup_file") || exit 1
    
    log_info "Selected backup: $(basename "$selected_backup")"
    
    # Confirm restore
    echo ""
    log_warning "This will restore the dashboard from backup and may overwrite current configuration."
    echo -n "Continue with restore? [y/N]: "
    read -r confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "Restore cancelled"
        exit 0
    fi
    
    # Extract backup
    extract_backup "$selected_backup" || exit 1
    
    # Create pre-restore backup
    create_pre_restore_backup
    
    # Stop services
    stop_services
    
    # Restore components based on mode
    case "$restore_mode" in
        full)
            restore_configuration
            restore_application
            restore_database
            ;;
        config)
            restore_configuration
            ;;
        app)
            restore_application
            ;;
        db)
            restore_database
            ;;
    esac
    
    # Start services
    start_services
    
    # Verify restore
    verify_restore
    
    # Cleanup
    cleanup_restore
    
    # Show summary
    show_summary
    
    log_success "Restore completed successfully!"
}

# Error handler
error_handler() {
    local exit_code=$?
    log_error "Restore failed with exit code $exit_code"
    
    # Try to start services if they were stopped
    systemctl start cold-email-dashboard 2>/dev/null || true
    systemctl start nginx 2>/dev/null || true
    
    # Cleanup
    cleanup_restore
    
    exit $exit_code
}

# Set up error handling
trap error_handler ERR

# Parse command line arguments
case "${1:-}" in
    list)
        list_backups
        ;;
    download)
        if [[ -n "${2:-}" ]]; then
            download_from_s3 "$2"
        else
            log_error "Please provide backup name to download"
            exit 1
        fi
        ;;
    *)
        main "$@"
        ;;
esac