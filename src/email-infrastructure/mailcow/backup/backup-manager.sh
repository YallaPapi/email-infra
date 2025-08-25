#!/bin/bash

# Mailcow Backup and Restore Manager
# Handles comprehensive backup and restore operations
# Usage: ./backup-manager.sh [action] [options]

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/../config"
MAILCOW_DIR="/opt/mailcow-dockerized"
BACKUP_BASE_DIR="/var/backups/mailcow"
LOG_FILE="/var/log/mailcow-backup.log"

# Backup settings
DEFAULT_RETENTION_DAYS=30
COMPRESS_BACKUPS=true
VERIFY_BACKUPS=true
BACKUP_ENCRYPTION=false

# Backup types
BACKUP_TYPES=("full" "config" "mail" "db" "redis")

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
    if [[ -f "$CONFIG_DIR/backup.conf" ]]; then
        source "$CONFIG_DIR/backup.conf"
    else
        create_backup_config
    fi
    
    # Ensure backup directory exists
    mkdir -p "$BACKUP_BASE_DIR"
    chmod 700 "$BACKUP_BASE_DIR"
}

# Create default backup configuration
create_backup_config() {
    log "Creating default backup configuration..."
    
    mkdir -p "$CONFIG_DIR"
    
    cat > "$CONFIG_DIR/backup.conf" << EOF
# Mailcow Backup Configuration
# Generated: $(date)

# Backup settings
BACKUP_BASE_DIR="$BACKUP_BASE_DIR"
RETENTION_DAYS=$DEFAULT_RETENTION_DAYS
COMPRESS_BACKUPS=$COMPRESS_BACKUPS
VERIFY_BACKUPS=$VERIFY_BACKUPS
BACKUP_ENCRYPTION=$BACKUP_ENCRYPTION

# Backup schedule (for cron)
DAILY_BACKUP_TIME="02:00"
WEEKLY_BACKUP_DAY="sunday"
MONTHLY_BACKUP_DAY="1"

# Notification settings
BACKUP_NOTIFICATIONS=true
NOTIFICATION_EMAIL=""

# Remote backup settings
REMOTE_BACKUP_ENABLED=false
REMOTE_BACKUP_TYPE=""  # rsync, s3, ftp
REMOTE_BACKUP_HOST=""
REMOTE_BACKUP_PATH=""
REMOTE_BACKUP_USER=""

# Encryption settings (if enabled)
GPG_RECIPIENT=""
ENCRYPTION_PASSPHRASE=""

# Include/exclude patterns
BACKUP_INCLUDE_PATTERNS=("data/vmail" "data/mysql" "data/redis")
BACKUP_EXCLUDE_PATTERNS=("*.tmp" "*.lock" "lost+found")
EOF
    
    chmod 600 "$CONFIG_DIR/backup.conf"
    info "Backup configuration created: $CONFIG_DIR/backup.conf"
}

# Check prerequisites
check_prerequisites() {
    log "Checking backup prerequisites..."
    
    # Check if Mailcow directory exists
    if [[ ! -d "$MAILCOW_DIR" ]]; then
        error "Mailcow directory not found: $MAILCOW_DIR"
    fi
    
    # Check if we can access docker-compose
    if ! command -v docker-compose &> /dev/null; then
        error "docker-compose command not found"
    fi
    
    # Check disk space
    local available_space=$(df "$BACKUP_BASE_DIR" | awk 'NR==2 {print $4}')
    local required_space=5242880  # 5GB in KB
    
    if [[ $available_space -lt $required_space ]]; then
        warning "Low disk space for backups: $(($available_space / 1024 / 1024))GB available"
    fi
    
    # Check backup directory permissions
    if [[ ! -w "$BACKUP_BASE_DIR" ]]; then
        error "Cannot write to backup directory: $BACKUP_BASE_DIR"
    fi
    
    info "Prerequisites check passed"
}

# Create backup
create_backup() {
    local backup_type="${1:-full}"
    local backup_name="${2:-mailcow-$(date +%Y%m%d_%H%M%S)}"
    local description="${3:-Automated backup}"
    
    log "Starting backup: $backup_name ($backup_type)"
    
    check_prerequisites
    
    # Validate backup type
    if [[ ! " ${BACKUP_TYPES[@]} " =~ " ${backup_type} " ]]; then
        error "Invalid backup type: $backup_type. Valid types: ${BACKUP_TYPES[*]}"
    fi
    
    # Create backup directory
    local backup_dir="$BACKUP_BASE_DIR/$backup_name"
    mkdir -p "$backup_dir"
    
    # Create backup metadata
    create_backup_metadata "$backup_dir" "$backup_type" "$description"
    
    # Perform backup based on type
    case "$backup_type" in
        "full")
            backup_full "$backup_dir"
            ;;
        "config")
            backup_config "$backup_dir"
            ;;
        "mail")
            backup_mail "$backup_dir"
            ;;
        "db")
            backup_database "$backup_dir"
            ;;
        "redis")
            backup_redis "$backup_dir"
            ;;
    esac
    
    # Post-backup operations
    if [[ "$COMPRESS_BACKUPS" == "true" ]]; then
        compress_backup "$backup_dir"
    fi
    
    if [[ "$BACKUP_ENCRYPTION" == "true" ]]; then
        encrypt_backup "$backup_dir"
    fi
    
    if [[ "$VERIFY_BACKUPS" == "true" ]]; then
        verify_backup "$backup_dir"
    fi
    
    # Update backup index
    update_backup_index "$backup_name" "$backup_type" "$description"
    
    log "Backup completed successfully: $backup_name"
    
    # Cleanup old backups
    cleanup_old_backups
}

# Create backup metadata
create_backup_metadata() {
    local backup_dir="$1"
    local backup_type="$2"
    local description="$3"
    
    cat > "$backup_dir/backup.meta" << EOF
# Mailcow Backup Metadata
BACKUP_NAME=$(basename "$backup_dir")
BACKUP_TYPE=$backup_type
DESCRIPTION=$description
CREATED=$(date -Iseconds)
CREATED_BY=$(whoami)
HOSTNAME=$(hostname)
MAILCOW_VERSION=$(cd "$MAILCOW_DIR" && git describe --tags --abbrev=0 2>/dev/null || echo "unknown")
COMPRESSED=$COMPRESS_BACKUPS
ENCRYPTED=$BACKUP_ENCRYPTION
VERIFIED=false

# System information
OS=$(lsb_release -ds 2>/dev/null || echo "Unknown")
KERNEL=$(uname -r)
DOCKER_VERSION=$(docker --version 2>/dev/null || echo "Unknown")
DOCKER_COMPOSE_VERSION=$(docker-compose --version 2>/dev/null || echo "Unknown")
EOF
    
    info "Backup metadata created"
}

# Full backup
backup_full() {
    local backup_dir="$1"
    
    log "Performing full backup..."
    
    cd "$MAILCOW_DIR"
    
    # Stop services for consistent backup
    log "Stopping Mailcow services..."
    docker-compose stop
    
    # Backup all data
    backup_config "$backup_dir"
    backup_mail "$backup_dir"
    backup_database "$backup_dir"
    backup_redis "$backup_dir"
    
    # Backup additional files
    log "Backing up additional files..."
    
    # Docker compose files
    cp docker-compose.yml "$backup_dir/"
    cp mailcow.conf "$backup_dir/"
    
    # Custom configurations
    if [[ -d "data/conf" ]]; then
        cp -r data/conf "$backup_dir/"
    fi
    
    # SSL certificates
    if [[ -d "data/assets/ssl" ]]; then
        cp -r data/assets/ssl "$backup_dir/"
    fi
    
    # Start services again
    log "Starting Mailcow services..."
    docker-compose up -d
    
    info "Full backup completed"
}

# Configuration backup
backup_config() {
    local backup_dir="$1"
    
    log "Backing up configuration..."
    
    cd "$MAILCOW_DIR"
    
    # Create config backup directory
    mkdir -p "$backup_dir/config"
    
    # Backup main configuration files
    cp mailcow.conf "$backup_dir/config/"
    cp docker-compose.yml "$backup_dir/config/"
    
    # Backup data/conf directory
    if [[ -d "data/conf" ]]; then
        cp -r data/conf "$backup_dir/config/"
    fi
    
    # Backup custom scripts and hooks
    if [[ -d "data/hooks" ]]; then
        cp -r data/hooks "$backup_dir/config/"
    fi
    
    info "Configuration backup completed"
}

# Mail data backup
backup_mail() {
    local backup_dir="$1"
    
    log "Backing up mail data..."
    
    cd "$MAILCOW_DIR"
    
    # Create mail backup directory
    mkdir -p "$backup_dir/mail"
    
    # Backup vmail directory (user mailboxes)
    if [[ -d "data/vmail" ]]; then
        log "Backing up vmail directory..."
        tar -czf "$backup_dir/mail/vmail.tar.gz" -C data vmail
    fi
    
    # Backup Dovecot index files
    if [[ -d "data/dovecot" ]]; then
        log "Backing up Dovecot data..."
        tar -czf "$backup_dir/mail/dovecot.tar.gz" -C data dovecot
    fi
    
    # Backup Postfix queue
    if [[ -d "data/postfix" ]]; then
        log "Backing up Postfix data..."
        tar -czf "$backup_dir/mail/postfix.tar.gz" -C data postfix
    fi
    
    info "Mail data backup completed"
}

# Database backup
backup_database() {
    local backup_dir="$1"
    
    log "Backing up database..."
    
    cd "$MAILCOW_DIR"
    
    # Create database backup directory
    mkdir -p "$backup_dir/database"
    
    # Get database credentials
    local db_root_pass=$(grep "DBROOT=" mailcow.conf | cut -d'=' -f2)
    local db_name=$(grep "DBNAME=" mailcow.conf | cut -d'=' -f2 || echo "mailcow")
    
    # Backup MySQL database
    log "Creating MySQL dump..."
    docker-compose exec -T mysql-mailcow mysqldump \
        -u root -p"$db_root_pass" \
        --single-transaction \
        --routines \
        --triggers \
        --all-databases \
        > "$backup_dir/database/mailcow-$(date +%Y%m%d_%H%M%S).sql"
    
    # Compress database dump
    gzip "$backup_dir/database/"*.sql
    
    info "Database backup completed"
}

# Redis backup
backup_redis() {
    local backup_dir="$1"
    
    log "Backing up Redis data..."
    
    cd "$MAILCOW_DIR"
    
    # Create Redis backup directory
    mkdir -p "$backup_dir/redis"
    
    # Backup Redis data
    if [[ -d "data/redis" ]]; then
        cp -r data/redis "$backup_dir/"
    fi
    
    # Create Redis dump
    docker-compose exec -T redis-mailcow redis-cli BGSAVE
    sleep 5  # Wait for background save to complete
    
    # Copy dump file
    docker-compose exec -T redis-mailcow cat /data/dump.rdb > "$backup_dir/redis/dump.rdb" 2>/dev/null || warning "Could not backup Redis dump"
    
    info "Redis backup completed"
}

# Compress backup
compress_backup() {
    local backup_dir="$1"
    
    log "Compressing backup..."
    
    local backup_name=$(basename "$backup_dir")
    local compressed_file="$backup_dir.tar.gz"
    
    # Create compressed archive
    tar -czf "$compressed_file" -C "$(dirname "$backup_dir")" "$backup_name"
    
    # Remove uncompressed directory
    rm -rf "$backup_dir"
    
    info "Backup compressed: $compressed_file"
}

# Encrypt backup
encrypt_backup() {
    local backup_path="$1"
    
    if [[ -z "$GPG_RECIPIENT" ]]; then
        warning "GPG recipient not configured, skipping encryption"
        return 0
    fi
    
    log "Encrypting backup..."
    
    # Determine if it's a directory or file
    if [[ -d "$backup_path" ]]; then
        # Compress first if not already compressed
        local backup_name=$(basename "$backup_path")
        local compressed_file="$backup_path.tar.gz"
        tar -czf "$compressed_file" -C "$(dirname "$backup_path")" "$backup_name"
        rm -rf "$backup_path"
        backup_path="$compressed_file"
    fi
    
    # Encrypt with GPG
    gpg --trust-model always --encrypt -r "$GPG_RECIPIENT" "$backup_path"
    
    # Remove unencrypted file
    rm -f "$backup_path"
    
    info "Backup encrypted: ${backup_path}.gpg"
}

# Verify backup
verify_backup() {
    local backup_path="$1"
    
    log "Verifying backup..."
    
    local verification_passed=true
    
    # Determine backup path (could be compressed or encrypted)
    local actual_path="$backup_path"
    if [[ -f "${backup_path}.tar.gz" ]]; then
        actual_path="${backup_path}.tar.gz"
    elif [[ -f "${backup_path}.tar.gz.gpg" ]]; then
        actual_path="${backup_path}.tar.gz.gpg"
    fi
    
    # Check if backup file/directory exists
    if [[ ! -e "$actual_path" ]]; then
        warning "Backup verification failed: file not found"
        return 1
    fi
    
    # Check file size
    local file_size
    if [[ -f "$actual_path" ]]; then
        file_size=$(stat -c%s "$actual_path")
        if [[ $file_size -lt 1048576 ]]; then  # Less than 1MB
            warning "Backup file seems too small: $(($file_size / 1024))KB"
            verification_passed=false
        fi
    fi
    
    # Test archive integrity if compressed
    if [[ "$actual_path" =~ \.tar\.gz$ ]]; then
        if ! tar -tzf "$actual_path" >/dev/null 2>&1; then
            warning "Backup archive integrity check failed"
            verification_passed=false
        fi
    fi
    
    # Update metadata
    if [[ -f "$backup_path/backup.meta" ]]; then
        sed -i "s/VERIFIED=false/VERIFIED=$verification_passed/" "$backup_path/backup.meta"
    fi
    
    if [[ "$verification_passed" == "true" ]]; then
        info "Backup verification passed"
    else
        warning "Backup verification failed"
    fi
    
    return $([ "$verification_passed" == "true" ] && echo 0 || echo 1)
}

# Update backup index
update_backup_index() {
    local backup_name="$1"
    local backup_type="$2"
    local description="$3"
    
    local index_file="$BACKUP_BASE_DIR/backup_index.txt"
    
    # Create index header if file doesn't exist
    if [[ ! -f "$index_file" ]]; then
        cat > "$index_file" << EOF
# Mailcow Backup Index
# Format: DATE|NAME|TYPE|SIZE|STATUS|DESCRIPTION
EOF
    fi
    
    # Calculate backup size
    local backup_size="0"
    if [[ -f "$BACKUP_BASE_DIR/$backup_name.tar.gz" ]]; then
        backup_size=$(stat -c%s "$BACKUP_BASE_DIR/$backup_name.tar.gz")
    elif [[ -d "$BACKUP_BASE_DIR/$backup_name" ]]; then
        backup_size=$(du -sb "$BACKUP_BASE_DIR/$backup_name" | cut -f1)
    fi
    
    # Add entry to index
    echo "$(date -Iseconds)|$backup_name|$backup_type|$backup_size|SUCCESS|$description" >> "$index_file"
}

# List backups
list_backups() {
    local format="${1:-table}"
    local filter_type="${2:-all}"
    
    log "Listing backups..."
    
    local index_file="$BACKUP_BASE_DIR/backup_index.txt"
    
    if [[ ! -f "$index_file" ]]; then
        warning "No backup index found"
        return 1
    fi
    
    case "$format" in
        "table")
            echo ""
            printf "%-20s %-30s %-8s %-10s %-10s %s\n" "Date" "Name" "Type" "Size" "Status" "Description"
            printf "%-20s %-30s %-8s %-10s %-10s %s\n" "====================" "==============================" "========" "==========" "==========" "========================="
            
            while IFS='|' read -r date name type size status description; do
                # Skip comments
                [[ "$date" =~ ^#.*$ ]] && continue
                
                # Apply filter
                if [[ "$filter_type" != "all" && "$type" != "$filter_type" ]]; then
                    continue
                fi
                
                # Format size
                local size_human
                if [[ $size -gt 1073741824 ]]; then
                    size_human="$(($size / 1073741824))GB"
                elif [[ $size -gt 1048576 ]]; then
                    size_human="$(($size / 1048576))MB"
                else
                    size_human="$(($size / 1024))KB"
                fi
                
                printf "%-20s %-30s %-8s %-10s %-10s %s\n" \
                    "${date%T*}" "$name" "$type" "$size_human" "$status" "$description"
                    
            done < "$index_file"
            echo ""
            ;;
        "json")
            echo "["
            local first=true
            while IFS='|' read -r date name type size status description; do
                [[ "$date" =~ ^#.*$ ]] && continue
                
                if [[ "$filter_type" != "all" && "$type" != "$filter_type" ]]; then
                    continue
                fi
                
                if [[ "$first" != "true" ]]; then
                    echo ","
                fi
                first=false
                
                echo "  {"
                echo "    \"date\": \"$date\","
                echo "    \"name\": \"$name\","
                echo "    \"type\": \"$type\","
                echo "    \"size\": $size,"
                echo "    \"status\": \"$status\","
                echo "    \"description\": \"$description\""
                echo -n "  }"
            done < "$index_file"
            echo ""
            echo "]"
            ;;
    esac
}

# Restore backup
restore_backup() {
    local backup_name="$1"
    local restore_type="${2:-full}"
    local confirm="${3:-false}"
    
    if [[ -z "$backup_name" ]]; then
        error "Backup name is required"
    fi
    
    log "Restoring backup: $backup_name ($restore_type)"
    
    # Confirmation
    if [[ "$confirm" != "true" ]]; then
        echo -e "${RED}WARNING: This will overwrite current Mailcow data!${NC}"
        echo -n "Are you sure you want to restore from backup '$backup_name'? (yes/no): "
        read -r confirmation
        if [[ "$confirmation" != "yes" ]]; then
            info "Restore cancelled"
            return 0
        fi
    fi
    
    # Find backup
    local backup_path=""
    if [[ -d "$BACKUP_BASE_DIR/$backup_name" ]]; then
        backup_path="$BACKUP_BASE_DIR/$backup_name"
    elif [[ -f "$BACKUP_BASE_DIR/$backup_name.tar.gz" ]]; then
        backup_path="$BACKUP_BASE_DIR/$backup_name.tar.gz"
        # Extract compressed backup
        log "Extracting compressed backup..."
        tar -xzf "$backup_path" -C "$BACKUP_BASE_DIR"
        backup_path="$BACKUP_BASE_DIR/$backup_name"
    else
        error "Backup not found: $backup_name"
    fi
    
    # Perform restore
    case "$restore_type" in
        "full")
            restore_full "$backup_path"
            ;;
        "config")
            restore_config "$backup_path"
            ;;
        "mail")
            restore_mail "$backup_path"
            ;;
        "db")
            restore_database "$backup_path"
            ;;
        *)
            error "Invalid restore type: $restore_type"
            ;;
    esac
    
    log "Restore completed: $backup_name"
}

# Full restore
restore_full() {
    local backup_path="$1"
    
    log "Performing full restore..."
    
    cd "$MAILCOW_DIR"
    
    # Stop services
    log "Stopping Mailcow services..."
    docker-compose down
    
    # Restore configuration
    restore_config "$backup_path"
    
    # Restore mail data
    restore_mail "$backup_path"
    
    # Restore database
    restore_database "$backup_path"
    
    # Start services
    log "Starting Mailcow services..."
    docker-compose up -d
    
    info "Full restore completed"
}

# Restore configuration
restore_config() {
    local backup_path="$1"
    
    log "Restoring configuration..."
    
    if [[ -d "$backup_path/config" ]]; then
        cp -r "$backup_path/config/"* "$MAILCOW_DIR/"
        info "Configuration restored"
    else
        warning "No configuration found in backup"
    fi
}

# Restore mail data
restore_mail() {
    local backup_path="$1"
    
    log "Restoring mail data..."
    
    cd "$MAILCOW_DIR"
    
    # Restore vmail
    if [[ -f "$backup_path/mail/vmail.tar.gz" ]]; then
        log "Restoring vmail directory..."
        tar -xzf "$backup_path/mail/vmail.tar.gz" -C data/
    fi
    
    # Restore Dovecot data
    if [[ -f "$backup_path/mail/dovecot.tar.gz" ]]; then
        log "Restoring Dovecot data..."
        tar -xzf "$backup_path/mail/dovecot.tar.gz" -C data/
    fi
    
    # Restore Postfix data
    if [[ -f "$backup_path/mail/postfix.tar.gz" ]]; then
        log "Restoring Postfix data..."
        tar -xzf "$backup_path/mail/postfix.tar.gz" -C data/
    fi
    
    info "Mail data restored"
}

# Restore database
restore_database() {
    local backup_path="$1"
    
    log "Restoring database..."
    
    cd "$MAILCOW_DIR"
    
    # Find database dump
    local db_dump=$(ls "$backup_path/database/"*.sql.gz 2>/dev/null | head -1)
    
    if [[ -z "$db_dump" ]]; then
        warning "No database dump found in backup"
        return 1
    fi
    
    # Get database credentials
    local db_root_pass=$(grep "DBROOT=" mailcow.conf | cut -d'=' -f2)
    
    # Restore database
    log "Restoring MySQL database..."
    gunzip -c "$db_dump" | docker-compose exec -T mysql-mailcow mysql -u root -p"$db_root_pass"
    
    info "Database restored"
}

# Cleanup old backups
cleanup_old_backups() {
    log "Cleaning up old backups (retention: $RETENTION_DAYS days)..."
    
    local deleted_count=0
    
    # Find and delete old backups
    while IFS= read -r -d '' backup_file; do
        local file_age=$(stat -c %Y "$backup_file")
        local current_time=$(date +%s)
        local age_days=$(( (current_time - file_age) / 86400 ))
        
        if [[ $age_days -gt $RETENTION_DAYS ]]; then
            log "Deleting old backup: $(basename "$backup_file") (${age_days} days old)"
            rm -rf "$backup_file"
            ((deleted_count++))
        fi
    done < <(find "$BACKUP_BASE_DIR" -maxdepth 1 \( -type f -name "*.tar.gz" -o -type d -name "mailcow-*" \) -print0)
    
    info "Deleted $deleted_count old backups"
}

# Setup backup schedule
setup_schedule() {
    local schedule_type="${1:-daily}"
    
    log "Setting up backup schedule: $schedule_type"
    
    local script_path="$(realpath "$0")"
    local cron_entry=""
    
    case "$schedule_type" in
        "daily")
            cron_entry="0 2 * * * $script_path create full daily-$(date +\%Y\%m\%d) 'Daily automated backup'"
            ;;
        "weekly")
            cron_entry="0 2 * * 0 $script_path create full weekly-$(date +\%Y\%m\%d) 'Weekly automated backup'"
            ;;
        "monthly")
            cron_entry="0 2 1 * * $script_path create full monthly-$(date +\%Y\%m\%d) 'Monthly automated backup'"
            ;;
        *)
            error "Invalid schedule type: $schedule_type. Use: daily, weekly, monthly"
            ;;
    esac
    
    # Add to crontab
    (crontab -l 2>/dev/null; echo "$cron_entry") | crontab -
    
    info "Backup schedule configured: $schedule_type"
}

# Show usage
show_usage() {
    cat << EOF
Mailcow Backup and Restore Manager

Usage: $0 [action] [options]

Actions:
  create [type] [name] [description]
    Create backup (type: full, config, mail, db, redis)
    
  list [format] [filter]
    List available backups (format: table, json)
    
  restore <name> [type] [--confirm]
    Restore from backup (type: full, config, mail, db)
    
  verify <name>
    Verify backup integrity
    
  cleanup [days]
    Clean up old backups (default: $DEFAULT_RETENTION_DAYS days)
    
  schedule [type]
    Setup automatic backup schedule (type: daily, weekly, monthly)
    
  config
    Show/edit backup configuration

Backup Types:
  full     - Complete backup (config + mail + database + redis)
  config   - Configuration files only
  mail     - Mail data and mailboxes
  db       - Database only
  redis    - Redis data only

Options:
  --confirm        Skip confirmation prompts
  --encrypt        Encrypt backup (requires GPG configuration)
  --no-compress    Don't compress backup
  --no-verify      Skip backup verification
  --help          Show this help message

Examples:
  $0 create full
  $0 create config backup-before-update "Before major update"
  $0 list table
  $0 restore mailcow-20231201_020000 full --confirm
  $0 cleanup 7
  $0 schedule daily

Configuration file: $CONFIG_DIR/backup.conf

EOF
}

# Main function
main() {
    local action="$1"
    shift
    
    # Load configuration
    load_config
    
    case "$action" in
        "create")
            create_backup "$1" "$2" "$3"
            ;;
        "list")
            list_backups "$1" "$2"
            ;;
        "restore")
            local confirm=""
            for arg in "$@"; do
                if [[ "$arg" == "--confirm" ]]; then
                    confirm="true"
                    break
                fi
            done
            restore_backup "$1" "$2" "$confirm"
            ;;
        "verify")
            verify_backup "$1"
            ;;
        "cleanup")
            local days="${1:-$RETENTION_DAYS}"
            RETENTION_DAYS="$days"
            cleanup_old_backups
            ;;
        "schedule")
            setup_schedule "$1"
            ;;
        "config")
            if [[ -f "$CONFIG_DIR/backup.conf" ]]; then
                echo "Current backup configuration:"
                cat "$CONFIG_DIR/backup.conf"
            else
                echo "No backup configuration found. Creating default..."
                create_backup_config
            fi
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