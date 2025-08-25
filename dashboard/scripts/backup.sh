#!/bin/bash

# Cold Email Dashboard Backup Script
# Creates comprehensive backups of configuration, data, and logs

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_BASE_DIR="${BACKUP_BASE_DIR:-/opt/cold-email-dashboard/backups}"
BACKUP_NAME="dashboard_backup_$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="$BACKUP_BASE_DIR/$BACKUP_NAME"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
COMPRESSION_LEVEL="${COMPRESSION_LEVEL:-6}"

# S3 Configuration (optional)
S3_BUCKET="${BACKUP_S3_BUCKET:-}"
S3_REGION="${BACKUP_S3_REGION:-us-east-1}"
S3_ENDPOINT="${BACKUP_S3_ENDPOINT:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$BACKUP_DIR/backup.log"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$BACKUP_DIR/backup.log"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$BACKUP_DIR/backup.log"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" | tee -a "$BACKUP_DIR/backup.log"; }

# Create backup directory structure
create_backup_structure() {
    log_info "Creating backup directory structure..."
    
    mkdir -p "$BACKUP_DIR"/{config,application,logs,database,system,metadata}
    
    # Create backup log
    echo "Cold Email Dashboard Backup - $(date)" > "$BACKUP_DIR/backup.log"
    echo "Backup ID: $BACKUP_NAME" >> "$BACKUP_DIR/backup.log"
    echo "Started: $(date -Iseconds)" >> "$BACKUP_DIR/backup.log"
    
    log_success "Backup directory created: $BACKUP_DIR"
}

# Backup configuration files
backup_configuration() {
    log_info "Backing up configuration files..."
    
    # Dashboard environment configuration
    if [[ -f /etc/cold-email-dashboard/dashboard.env ]]; then
        cp /etc/cold-email-dashboard/dashboard.env "$BACKUP_DIR/config/"
        log_success "Dashboard configuration backed up"
    else
        log_warning "Dashboard configuration file not found"
    fi
    
    # Project .env file
    if [[ -f "$PROJECT_DIR/.env" ]]; then
        cp "$PROJECT_DIR/.env" "$BACKUP_DIR/config/project.env"
        log_success "Project .env file backed up"
    fi
    
    # Systemd service file
    if [[ -f /etc/systemd/system/cold-email-dashboard.service ]]; then
        cp /etc/systemd/system/cold-email-dashboard.service "$BACKUP_DIR/config/"
        log_success "Systemd service file backed up"
    fi
    
    # Nginx configuration
    if [[ -f /etc/nginx/sites-available/dashboard ]]; then
        cp /etc/nginx/sites-available/dashboard "$BACKUP_DIR/config/nginx-dashboard.conf"
        log_success "Nginx configuration backed up"
    fi
    
    # SSL certificates
    if [[ -d /etc/letsencrypt/live ]]; then
        mkdir -p "$BACKUP_DIR/config/ssl"
        cp -r /etc/letsencrypt/live/* "$BACKUP_DIR/config/ssl/" 2>/dev/null || true
        cp -r /etc/letsencrypt/renewal/* "$BACKUP_DIR/config/ssl/" 2>/dev/null || true
        log_success "SSL certificates backed up"
    fi
    
    # Firewall rules
    if command -v ufw >/dev/null 2>&1; then
        ufw status numbered > "$BACKUP_DIR/config/ufw-rules.txt" 2>/dev/null || true
        log_success "Firewall rules backed up"
    fi
}

# Backup application files
backup_application() {
    log_info "Backing up application files..."
    
    # Application directory
    if [[ -d /opt/cold-email-dashboard/dashboard ]]; then
        tar -czf "$BACKUP_DIR/application/dashboard-app.tar.gz" \
            -C /opt/cold-email-dashboard dashboard \
            --exclude='dashboard/__pycache__' \
            --exclude='dashboard/*.pyc' \
            --exclude='dashboard/logs' \
            --exclude='dashboard/.git'
        log_success "Application files backed up"
    elif [[ -d "$PROJECT_DIR" ]]; then
        tar -czf "$BACKUP_DIR/application/dashboard-app.tar.gz" \
            -C "$(dirname "$PROJECT_DIR")" "$(basename "$PROJECT_DIR")" \
            --exclude='__pycache__' \
            --exclude='*.pyc' \
            --exclude='logs' \
            --exclude='.git'
        log_success "Application files backed up from project directory"
    else
        log_warning "Application directory not found"
    fi
    
    # Python virtual environment requirements
    if [[ -f /opt/cold-email-dashboard/venv/pyvenv.cfg ]]; then
        /opt/cold-email-dashboard/venv/bin/pip freeze > "$BACKUP_DIR/application/requirements-frozen.txt"
        log_success "Python requirements backed up"
    fi
}

# Backup logs
backup_logs() {
    log_info "Backing up log files..."
    
    # Application logs
    if [[ -d /var/log/cold-email-dashboard ]]; then
        tar -czf "$BACKUP_DIR/logs/application-logs.tar.gz" \
            -C /var/log cold-email-dashboard
        log_success "Application logs backed up"
    fi
    
    # Nginx logs
    if [[ -f /var/log/nginx/dashboard_access.log ]] || [[ -f /var/log/nginx/dashboard_error.log ]]; then
        mkdir -p "$BACKUP_DIR/logs/nginx"
        cp /var/log/nginx/dashboard_*.log "$BACKUP_DIR/logs/nginx/" 2>/dev/null || true
        log_success "Nginx logs backed up"
    fi
    
    # System logs (last 1000 lines)
    if command -v journalctl >/dev/null 2>&1; then
        journalctl -u cold-email-dashboard --no-pager -n 1000 > "$BACKUP_DIR/logs/systemd.log" 2>/dev/null || true
        log_success "Systemd logs backed up"
    fi
    
    # Backup monitoring logs
    if [[ -f /var/log/nginx-monitor.log ]]; then
        cp /var/log/nginx-monitor.log "$BACKUP_DIR/logs/" 2>/dev/null || true
    fi
}

# Backup database (if applicable)
backup_database() {
    log_info "Checking for database backups..."
    
    # Check for SQLite databases
    if [[ -f /opt/cold-email-dashboard/data/dashboard.db ]]; then
        mkdir -p "$BACKUP_DIR/database"
        cp /opt/cold-email-dashboard/data/dashboard.db "$BACKUP_DIR/database/"
        log_success "SQLite database backed up"
    fi
    
    # Check for PostgreSQL
    if command -v pg_dump >/dev/null 2>&1 && [[ -n "${DB_NAME:-}" ]]; then
        pg_dump "${DB_NAME}" > "$BACKUP_DIR/database/postgresql.sql" 2>/dev/null || true
        log_success "PostgreSQL database backed up"
    fi
    
    # Check for Redis data
    if [[ -f /var/lib/redis/dump.rdb ]]; then
        cp /var/lib/redis/dump.rdb "$BACKUP_DIR/database/" 2>/dev/null || true
        log_success "Redis data backed up"
    fi
}

# Backup system information
backup_system_info() {
    log_info "Backing up system information..."
    
    # System information
    cat > "$BACKUP_DIR/system/system-info.txt" << EOF
System Information - $(date)
================================

Hostname: $(hostname)
OS: $(lsb_release -d 2>/dev/null | cut -f2 || echo "Unknown")
Kernel: $(uname -r)
Architecture: $(uname -m)
Uptime: $(uptime)

Disk Usage:
$(df -h)

Memory Usage:
$(free -h)

Network Interfaces:
$(ip addr show)

Installed Packages (Dashboard related):
$(dpkg -l | grep -E "(python3|nginx|certbot|redis)" || echo "No packages found")

Running Services:
$(systemctl list-units --type=service --state=running | grep -E "(nginx|dashboard|redis)" || echo "No services found")

Process List (Dashboard related):
$(ps aux | grep -E "(python|nginx|redis)" | grep -v grep || echo "No processes found")

Open Ports:
$(ss -tlnp | grep -E ":80|:443|:5000" || echo "No relevant ports found")

Crontab:
$(crontab -l 2>/dev/null || echo "No crontab entries")

Environment Variables (non-sensitive):
$(env | grep -E "^(PATH|USER|HOME|PWD)" | sort)
EOF
    
    # Network configuration
    if [[ -f /etc/hosts ]]; then
        cp /etc/hosts "$BACKUP_DIR/system/"
    fi
    
    # Cron jobs
    if [[ -d /etc/cron.d ]]; then
        mkdir -p "$BACKUP_DIR/system/cron"
        cp /etc/cron.d/* "$BACKUP_DIR/system/cron/" 2>/dev/null || true
    fi
    
    log_success "System information backed up"
}

# Create backup metadata
create_backup_metadata() {
    log_info "Creating backup metadata..."
    
    cat > "$BACKUP_DIR/metadata/backup-info.json" << EOF
{
    "backup_id": "$BACKUP_NAME",
    "created_at": "$(date -Iseconds)",
    "hostname": "$(hostname)",
    "backup_type": "full",
    "version": "1.0.0",
    "components": {
        "configuration": true,
        "application": true,
        "logs": true,
        "database": true,
        "system_info": true
    },
    "size_bytes": 0,
    "compression": "gzip",
    "retention_days": $RETENTION_DAYS
}
EOF
    
    # Create file list
    find "$BACKUP_DIR" -type f -exec ls -la {} \; > "$BACKUP_DIR/metadata/file-list.txt"
    
    # Calculate backup size
    BACKUP_SIZE=$(du -sb "$BACKUP_DIR" | cut -f1)
    sed -i "s/\"size_bytes\": 0/\"size_bytes\": $BACKUP_SIZE/" "$BACKUP_DIR/metadata/backup-info.json"
    
    log_success "Backup metadata created"
}

# Compress backup
compress_backup() {
    log_info "Compressing backup archive..."
    
    cd "$BACKUP_BASE_DIR"
    tar -czf "${BACKUP_NAME}.tar.gz" "$BACKUP_NAME" --remove-files
    
    # Calculate final size
    COMPRESSED_SIZE=$(du -sh "${BACKUP_NAME}.tar.gz" | cut -f1)
    
    log_success "Backup compressed: ${BACKUP_NAME}.tar.gz ($COMPRESSED_SIZE)"
}

# Upload to S3 (optional)
upload_to_s3() {
    if [[ -z "$S3_BUCKET" ]]; then
        log_info "S3 upload not configured, skipping..."
        return 0
    fi
    
    log_info "Uploading backup to S3..."
    
    if command -v aws >/dev/null 2>&1; then
        local s3_path="s3://$S3_BUCKET/dashboard-backups/${BACKUP_NAME}.tar.gz"
        
        if [[ -n "$S3_ENDPOINT" ]]; then
            aws s3 cp "${BACKUP_BASE_DIR}/${BACKUP_NAME}.tar.gz" "$s3_path" --endpoint-url "$S3_ENDPOINT"
        else
            aws s3 cp "${BACKUP_BASE_DIR}/${BACKUP_NAME}.tar.gz" "$s3_path"
        fi
        
        log_success "Backup uploaded to S3: $s3_path"
    else
        log_warning "AWS CLI not installed, cannot upload to S3"
    fi
}

# Clean old backups
cleanup_old_backups() {
    log_info "Cleaning up old backups (retention: $RETENTION_DAYS days)..."
    
    # Clean local backups
    find "$BACKUP_BASE_DIR" -name "dashboard_backup_*.tar.gz" -type f -mtime +$RETENTION_DAYS -delete 2>/dev/null || true
    
    local deleted_count=$(find "$BACKUP_BASE_DIR" -name "dashboard_backup_*.tar.gz" -type f -mtime +$RETENTION_DAYS 2>/dev/null | wc -l)
    
    if [[ $deleted_count -gt 0 ]]; then
        log_success "Cleaned up $deleted_count old backups"
    else
        log_info "No old backups to clean up"
    fi
    
    # Clean S3 backups (if configured)
    if [[ -n "$S3_BUCKET" ]] && command -v aws >/dev/null 2>&1; then
        local cutoff_date=$(date -d "$RETENTION_DAYS days ago" +%Y-%m-%d)
        log_info "Cleaning up S3 backups older than $cutoff_date..."
        
        # List and delete old S3 backups (this is a simplified approach)
        aws s3 ls "s3://$S3_BUCKET/dashboard-backups/" | while read -r line; do
            local file_date=$(echo "$line" | awk '{print $1}')
            local file_name=$(echo "$line" | awk '{print $4}')
            
            if [[ "$file_date" < "$cutoff_date" ]] && [[ "$file_name" == dashboard_backup_*.tar.gz ]]; then
                aws s3 rm "s3://$S3_BUCKET/dashboard-backups/$file_name"
                log_info "Deleted old S3 backup: $file_name"
            fi
        done 2>/dev/null || true
    fi
}

# Verify backup integrity
verify_backup() {
    log_info "Verifying backup integrity..."
    
    local backup_file="${BACKUP_BASE_DIR}/${BACKUP_NAME}.tar.gz"
    
    if [[ -f "$backup_file" ]]; then
        if tar -tzf "$backup_file" >/dev/null 2>&1; then
            log_success "Backup archive integrity verified"
        else
            log_error "Backup archive is corrupted!"
            return 1
        fi
    else
        log_error "Backup file not found: $backup_file"
        return 1
    fi
}

# Send notification (if configured)
send_notification() {
    local status="$1"
    local message="$2"
    
    # Email notification (if configured)
    if command -v mail >/dev/null 2>&1 && [[ -n "${NOTIFICATION_EMAIL:-}" ]]; then
        echo "$message" | mail -s "Dashboard Backup $status" "$NOTIFICATION_EMAIL" 2>/dev/null || true
    fi
    
    # Webhook notification (if configured)
    if [[ -n "${NOTIFICATION_WEBHOOK:-}" ]]; then
        curl -X POST "$NOTIFICATION_WEBHOOK" \
            -H "Content-Type: application/json" \
            -d "{\"status\":\"$status\",\"message\":\"$message\",\"hostname\":\"$(hostname)\",\"timestamp\":\"$(date -Iseconds)\"}" \
            2>/dev/null || true
    fi
}

# Main backup function
main() {
    local start_time=$(date +%s)
    
    log_info "Starting Cold Email Dashboard backup..."
    log_info "Backup ID: $BACKUP_NAME"
    
    # Check if backup directory is available
    if [[ ! -d "$BACKUP_BASE_DIR" ]]; then
        mkdir -p "$BACKUP_BASE_DIR"
        log_info "Created backup directory: $BACKUP_BASE_DIR"
    fi
    
    # Create backup
    create_backup_structure
    backup_configuration
    backup_application
    backup_logs
    backup_database
    backup_system_info
    create_backup_metadata
    
    # Finalize backup
    compress_backup
    verify_backup
    upload_to_s3
    cleanup_old_backups
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Final log entry
    echo "Completed: $(date -Iseconds)" >> "${BACKUP_BASE_DIR}/${BACKUP_NAME}.tar.gz.log"
    echo "Duration: ${duration} seconds" >> "${BACKUP_BASE_DIR}/${BACKUP_NAME}.tar.gz.log"
    
    log_success "Backup completed successfully in ${duration} seconds"
    log_success "Backup location: ${BACKUP_BASE_DIR}/${BACKUP_NAME}.tar.gz"
    
    # Send success notification
    send_notification "SUCCESS" "Dashboard backup completed successfully. File: ${BACKUP_NAME}.tar.gz, Duration: ${duration}s"
    
    return 0
}

# Error handler
error_handler() {
    local exit_code=$?
    log_error "Backup failed with exit code $exit_code"
    
    # Send failure notification
    send_notification "FAILED" "Dashboard backup failed with exit code $exit_code. Check logs for details."
    
    exit $exit_code
}

# Set up error handling
trap error_handler ERR

# Parse command line arguments
case "${1:-full}" in
    full)
        main
        ;;
    config)
        create_backup_structure
        backup_configuration
        create_backup_metadata
        compress_backup
        log_success "Configuration backup completed"
        ;;
    app)
        create_backup_structure
        backup_application
        create_backup_metadata
        compress_backup
        log_success "Application backup completed"
        ;;
    logs)
        create_backup_structure
        backup_logs
        create_backup_metadata
        compress_backup
        log_success "Logs backup completed"
        ;;
    test)
        log_info "Testing backup configuration..."
        create_backup_structure
        create_backup_metadata
        log_success "Backup test completed"
        rm -rf "$BACKUP_DIR"
        ;;
    *)
        echo "Usage: $0 {full|config|app|logs|test}"
        echo "  full   - Complete backup (default)"
        echo "  config - Configuration files only"
        echo "  app    - Application files only"
        echo "  logs   - Log files only"
        echo "  test   - Test backup configuration"
        exit 1
        ;;
esac