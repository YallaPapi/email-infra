#!/bin/bash

# Mailcow Database Initialization Script
# Handles database setup, initialization, and management
# Usage: ./db-init.sh [action] [options]

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/../config"
MAILCOW_DIR="/opt/mailcow-dockerized"
SQL_DIR="$SCRIPT_DIR/../sql"
LOG_FILE="/var/log/mailcow-db-init.log"

# Database settings
DB_CONTAINER="mysql-mailcow"
DB_NAME="mailcow"
DB_USER="mailcow"
DB_CHARSET="utf8mb4"
DB_COLLATION="utf8mb4_unicode_ci"

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
    if [[ -f "$CONFIG_DIR/admin_credentials" ]]; then
        source "$CONFIG_DIR/admin_credentials"
    else
        error "Admin credentials not found. Run install script first."
    fi
    
    # Extract database credentials from mailcow.conf
    if [[ -f "$MAILCOW_DIR/mailcow.conf" ]]; then
        DB_ROOT_PASS=$(grep "DBROOT=" "$MAILCOW_DIR/mailcow.conf" | cut -d'=' -f2)
        DB_PASS=$(grep "DBPASS=" "$MAILCOW_DIR/mailcow.conf" | cut -d'=' -f2)
        DB_NAME=$(grep "DBNAME=" "$MAILCOW_DIR/mailcow.conf" | cut -d'=' -f2 || echo "mailcow")
        DB_USER=$(grep "DBUSER=" "$MAILCOW_DIR/mailcow.conf" | cut -d'=' -f2 || echo "mailcow")
    else
        error "mailcow.conf not found"
    fi
}

# Check database connection
check_db_connection() {
    log "Checking database connection..."
    
    cd "$MAILCOW_DIR"
    
    # Check if MySQL container is running
    if ! docker-compose ps | grep -q "$DB_CONTAINER.*Up"; then
        error "MySQL container is not running"
    fi
    
    # Test database connection
    if docker-compose exec -T "$DB_CONTAINER" mysql -u root -p"$DB_ROOT_PASS" -e "SELECT 1;" >/dev/null 2>&1; then
        info "Database connection successful"
        return 0
    else
        error "Failed to connect to database"
    fi
}

# Initialize SQL directory structure
init_sql_directory() {
    log "Initializing SQL directory structure..."
    
    mkdir -p "$SQL_DIR"/{schemas,migrations,functions,triggers,views,seeds,maintenance}
    
    # Create README files for each directory
    cat > "$SQL_DIR/README.md" << 'EOF'
# Mailcow Database SQL Scripts

This directory contains SQL scripts for Mailcow database management.

## Directory Structure

- `schemas/` - Database schema definitions
- `migrations/` - Database migration scripts
- `functions/` - Custom database functions
- `triggers/` - Database triggers
- `views/` - Database views
- `seeds/` - Initial data and test data
- `maintenance/` - Maintenance and optimization scripts

## Usage

Use the db-init.sh script to execute these scripts:

```bash
./db-init.sh run-script schemas/custom_tables.sql
./db-init.sh migrate
./db-init.sh seed test_data
```
EOF

    info "SQL directory structure created"
}

# Create custom database schema
create_custom_schema() {
    log "Creating custom database schema..."
    
    mkdir -p "$SQL_DIR/schemas"
    
    # Create custom tables for extended functionality
    cat > "$SQL_DIR/schemas/custom_tables.sql" << 'EOF'
-- Custom tables for extended Mailcow functionality
-- Created by db-init.sh

-- API Keys table for enhanced API management
CREATE TABLE IF NOT EXISTS `api_keys` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `key_name` varchar(100) NOT NULL,
  `api_key` varchar(255) NOT NULL,
  `description` text,
  `permissions` json,
  `allowed_ips` json,
  `created` datetime DEFAULT CURRENT_TIMESTAMP,
  `updated` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `expires` datetime DEFAULT NULL,
  `last_used` datetime DEFAULT NULL,
  `usage_count` int(11) DEFAULT 0,
  `active` tinyint(1) DEFAULT 1,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_key_name` (`key_name`),
  UNIQUE KEY `uk_api_key` (`api_key`),
  KEY `idx_api_keys_active` (`active`),
  KEY `idx_api_keys_expires` (`expires`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Audit log table for tracking changes
CREATE TABLE IF NOT EXISTS `audit_log` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `table_name` varchar(100) NOT NULL,
  `record_id` varchar(100) NOT NULL,
  `action` enum('CREATE','UPDATE','DELETE') NOT NULL,
  `old_values` json,
  `new_values` json,
  `user_id` varchar(100) DEFAULT NULL,
  `user_ip` varchar(45) DEFAULT NULL,
  `user_agent` text,
  `created` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_audit_table_record` (`table_name`, `record_id`),
  KEY `idx_audit_action` (`action`),
  KEY `idx_audit_created` (`created`),
  KEY `idx_audit_user` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Extended mailbox statistics
CREATE TABLE IF NOT EXISTS `mailbox_stats` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `username` varchar(255) NOT NULL,
  `date` date NOT NULL,
  `messages_received` int(11) DEFAULT 0,
  `messages_sent` int(11) DEFAULT 0,
  `bytes_received` bigint(20) DEFAULT 0,
  `bytes_sent` bigint(20) DEFAULT 0,
  `spam_count` int(11) DEFAULT 0,
  `virus_count` int(11) DEFAULT 0,
  `login_count` int(11) DEFAULT 0,
  `last_login` datetime DEFAULT NULL,
  `created` datetime DEFAULT CURRENT_TIMESTAMP,
  `updated` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_username_date` (`username`, `date`),
  KEY `idx_stats_username` (`username`),
  KEY `idx_stats_date` (`date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Domain statistics
CREATE TABLE IF NOT EXISTS `domain_stats` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `domain` varchar(255) NOT NULL,
  `date` date NOT NULL,
  `mailboxes_count` int(11) DEFAULT 0,
  `aliases_count` int(11) DEFAULT 0,
  `messages_total` int(11) DEFAULT 0,
  `bytes_total` bigint(20) DEFAULT 0,
  `quota_used` bigint(20) DEFAULT 0,
  `quota_total` bigint(20) DEFAULT 0,
  `created` datetime DEFAULT CURRENT_TIMESTAMP,
  `updated` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_domain_date` (`domain`, `date`),
  KEY `idx_domain_stats_domain` (`domain`),
  KEY `idx_domain_stats_date` (`date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Custom settings table for extended configuration
CREATE TABLE IF NOT EXISTS `custom_settings` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `setting_key` varchar(100) NOT NULL,
  `setting_value` text,
  `setting_type` enum('string','integer','boolean','json','encrypted') DEFAULT 'string',
  `description` text,
  `category` varchar(50) DEFAULT 'general',
  `created` datetime DEFAULT CURRENT_TIMESTAMP,
  `updated` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_setting_key` (`setting_key`),
  KEY `idx_settings_category` (`category`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Notification queue for email/webhook notifications
CREATE TABLE IF NOT EXISTS `notification_queue` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `type` enum('email','webhook','sms') NOT NULL,
  `recipient` varchar(255) NOT NULL,
  `subject` varchar(255) DEFAULT NULL,
  `message` text,
  `data` json,
  `status` enum('pending','processing','sent','failed') DEFAULT 'pending',
  `attempts` int(11) DEFAULT 0,
  `max_attempts` int(11) DEFAULT 3,
  `next_attempt` datetime DEFAULT NULL,
  `last_error` text,
  `created` datetime DEFAULT CURRENT_TIMESTAMP,
  `updated` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `sent` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_notification_status` (`status`),
  KEY `idx_notification_next_attempt` (`next_attempt`),
  KEY `idx_notification_type` (`type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Backup metadata tracking
CREATE TABLE IF NOT EXISTS `backup_metadata` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `backup_name` varchar(255) NOT NULL,
  `backup_type` enum('full','incremental','config','mail','database') NOT NULL,
  `file_path` varchar(500) NOT NULL,
  `file_size` bigint(20) DEFAULT NULL,
  `checksum` varchar(128) DEFAULT NULL,
  `compressed` tinyint(1) DEFAULT 0,
  `encrypted` tinyint(1) DEFAULT 0,
  `description` text,
  `created` datetime DEFAULT CURRENT_TIMESTAMP,
  `expires` datetime DEFAULT NULL,
  `restored` datetime DEFAULT NULL,
  `status` enum('creating','completed','failed','expired') DEFAULT 'creating',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_backup_name` (`backup_name`),
  KEY `idx_backup_type` (`backup_type`),
  KEY `idx_backup_created` (`created`),
  KEY `idx_backup_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
EOF

    info "Custom database schema created"
}

# Create database functions
create_functions() {
    log "Creating database functions..."
    
    mkdir -p "$SQL_DIR/functions"
    
    cat > "$SQL_DIR/functions/mailbox_functions.sql" << 'EOF'
-- Custom functions for mailbox management
DELIMITER $$

-- Function to calculate mailbox quota usage percentage
DROP FUNCTION IF EXISTS get_quota_usage_percentage$$
CREATE FUNCTION get_quota_usage_percentage(p_username VARCHAR(255))
RETURNS DECIMAL(5,2)
READS SQL DATA
DETERMINISTIC
BEGIN
    DECLARE v_quota_used BIGINT DEFAULT 0;
    DECLARE v_quota_total BIGINT DEFAULT 0;
    DECLARE v_percentage DECIMAL(5,2) DEFAULT 0.00;
    
    -- Get quota information from mailbox table
    SELECT 
        COALESCE(bytes, 0),
        COALESCE(quota, 0) * 1048576  -- Convert MB to bytes
    INTO v_quota_used, v_quota_total
    FROM mailbox 
    WHERE username = p_username;
    
    -- Calculate percentage
    IF v_quota_total > 0 THEN
        SET v_percentage = (v_quota_used / v_quota_total) * 100;
    END IF;
    
    RETURN ROUND(v_percentage, 2);
END$$

-- Function to get domain quota usage
DROP FUNCTION IF EXISTS get_domain_quota_usage$$
CREATE FUNCTION get_domain_quota_usage(p_domain VARCHAR(255))
RETURNS JSON
READS SQL DATA
DETERMINISTIC
BEGIN
    DECLARE v_total_used BIGINT DEFAULT 0;
    DECLARE v_total_quota BIGINT DEFAULT 0;
    DECLARE v_mailbox_count INT DEFAULT 0;
    DECLARE v_result JSON;
    
    -- Calculate total usage for domain
    SELECT 
        COUNT(*),
        COALESCE(SUM(bytes), 0),
        COALESCE(SUM(quota * 1048576), 0)
    INTO v_mailbox_count, v_total_used, v_total_quota
    FROM mailbox
    WHERE domain = p_domain AND active = '1';
    
    -- Build result JSON
    SET v_result = JSON_OBJECT(
        'domain', p_domain,
        'mailbox_count', v_mailbox_count,
        'total_used_bytes', v_total_used,
        'total_quota_bytes', v_total_quota,
        'usage_percentage', 
        CASE 
            WHEN v_total_quota > 0 THEN ROUND((v_total_used / v_total_quota) * 100, 2)
            ELSE 0.00
        END
    );
    
    RETURN v_result;
END$$

-- Function to generate secure API key
DROP FUNCTION IF EXISTS generate_api_key$$
CREATE FUNCTION generate_api_key()
RETURNS VARCHAR(64)
READS SQL DATA
DETERMINISTIC
BEGIN
    RETURN UPPER(CONCAT(
        HEX(RANDOM_BYTES(16)),
        HEX(RANDOM_BYTES(16))
    ));
END$$

DELIMITER ;
EOF

    info "Database functions created"
}

# Create database triggers
create_triggers() {
    log "Creating database triggers..."
    
    mkdir -p "$SQL_DIR/triggers"
    
    cat > "$SQL_DIR/triggers/audit_triggers.sql" << 'EOF'
-- Audit triggers for tracking changes

DELIMITER $$

-- Mailbox audit trigger
DROP TRIGGER IF EXISTS mailbox_audit_insert$$
CREATE TRIGGER mailbox_audit_insert
    AFTER INSERT ON mailbox
    FOR EACH ROW
BEGIN
    INSERT INTO audit_log (
        table_name, record_id, action, new_values, user_id, user_ip
    ) VALUES (
        'mailbox', 
        NEW.username, 
        'CREATE',
        JSON_OBJECT(
            'username', NEW.username,
            'password', '[HIDDEN]',
            'name', NEW.name,
            'quota', NEW.quota,
            'local_part', NEW.local_part,
            'domain', NEW.domain,
            'active', NEW.active,
            'created', NEW.created
        ),
        COALESCE(@current_user_id, 'system'),
        COALESCE(@current_user_ip, 'localhost')
    );
END$$

DROP TRIGGER IF EXISTS mailbox_audit_update$$
CREATE TRIGGER mailbox_audit_update
    AFTER UPDATE ON mailbox
    FOR EACH ROW
BEGIN
    INSERT INTO audit_log (
        table_name, record_id, action, old_values, new_values, user_id, user_ip
    ) VALUES (
        'mailbox',
        NEW.username,
        'UPDATE',
        JSON_OBJECT(
            'username', OLD.username,
            'name', OLD.name,
            'quota', OLD.quota,
            'active', OLD.active,
            'modified', OLD.modified
        ),
        JSON_OBJECT(
            'username', NEW.username,
            'name', NEW.name,
            'quota', NEW.quota,
            'active', NEW.active,
            'modified', NEW.modified
        ),
        COALESCE(@current_user_id, 'system'),
        COALESCE(@current_user_ip, 'localhost')
    );
END$$

DROP TRIGGER IF EXISTS mailbox_audit_delete$$
CREATE TRIGGER mailbox_audit_delete
    AFTER DELETE ON mailbox
    FOR EACH ROW
BEGIN
    INSERT INTO audit_log (
        table_name, record_id, action, old_values, user_id, user_ip
    ) VALUES (
        'mailbox',
        OLD.username,
        'DELETE',
        JSON_OBJECT(
            'username', OLD.username,
            'name', OLD.name,
            'quota', OLD.quota,
            'domain', OLD.domain,
            'active', OLD.active
        ),
        COALESCE(@current_user_id, 'system'),
        COALESCE(@current_user_ip, 'localhost')
    );
END$$

-- Domain audit triggers
DROP TRIGGER IF EXISTS domain_audit_insert$$
CREATE TRIGGER domain_audit_insert
    AFTER INSERT ON domain
    FOR EACH ROW
BEGIN
    INSERT INTO audit_log (
        table_name, record_id, action, new_values, user_id, user_ip
    ) VALUES (
        'domain',
        NEW.domain,
        'CREATE',
        JSON_OBJECT(
            'domain', NEW.domain,
            'description', NEW.description,
            'aliases', NEW.aliases,
            'mailboxes', NEW.mailboxes,
            'quota', NEW.quota,
            'active', NEW.active,
            'created', NEW.created
        ),
        COALESCE(@current_user_id, 'system'),
        COALESCE(@current_user_ip, 'localhost')
    );
END$$

DROP TRIGGER IF EXISTS domain_audit_update$$
CREATE TRIGGER domain_audit_update
    AFTER UPDATE ON domain
    FOR EACH ROW
BEGIN
    INSERT INTO audit_log (
        table_name, record_id, action, old_values, new_values, user_id, user_ip
    ) VALUES (
        'domain',
        NEW.domain,
        'UPDATE',
        JSON_OBJECT(
            'description', OLD.description,
            'aliases', OLD.aliases,
            'mailboxes', OLD.mailboxes,
            'quota', OLD.quota,
            'active', OLD.active
        ),
        JSON_OBJECT(
            'description', NEW.description,
            'aliases', NEW.aliases,
            'mailboxes', NEW.mailboxes,
            'quota', NEW.quota,
            'active', NEW.active
        ),
        COALESCE(@current_user_id, 'system'),
        COALESCE(@current_user_ip, 'localhost')
    );
END$$

DROP TRIGGER IF EXISTS domain_audit_delete$$
CREATE TRIGGER domain_audit_delete
    AFTER DELETE ON domain
    FOR EACH ROW
BEGIN
    INSERT INTO audit_log (
        table_name, record_id, action, old_values, user_id, user_ip
    ) VALUES (
        'domain',
        OLD.domain,
        'DELETE',
        JSON_OBJECT(
            'domain', OLD.domain,
            'description', OLD.description,
            'aliases', OLD.aliases,
            'mailboxes', OLD.mailboxes,
            'quota', OLD.quota,
            'active', OLD.active
        ),
        COALESCE(@current_user_id, 'system'),
        COALESCE(@current_user_ip, 'localhost')
    );
END$$

DELIMITER ;
EOF

    info "Database triggers created"
}

# Create database views
create_views() {
    log "Creating database views..."
    
    mkdir -p "$SQL_DIR/views"
    
    cat > "$SQL_DIR/views/reporting_views.sql" << 'EOF'
-- Reporting views for better data access

-- Mailbox usage summary view
CREATE OR REPLACE VIEW v_mailbox_usage AS
SELECT 
    m.username,
    m.name,
    m.domain,
    m.quota as quota_mb,
    ROUND(m.bytes / 1048576, 2) as used_mb,
    ROUND((m.quota - (m.bytes / 1048576)), 2) as available_mb,
    get_quota_usage_percentage(m.username) as usage_percentage,
    m.active,
    m.created,
    m.modified
FROM mailbox m
WHERE m.active = '1';

-- Domain summary view
CREATE OR REPLACE VIEW v_domain_summary AS
SELECT 
    d.domain,
    d.description,
    d.quota as domain_quota_mb,
    d.active,
    COUNT(m.username) as mailbox_count,
    COUNT(CASE WHEN m.active = '1' THEN 1 END) as active_mailboxes,
    COALESCE(SUM(m.quota), 0) as total_mailbox_quota_mb,
    COALESCE(ROUND(SUM(m.bytes) / 1048576, 2), 0) as total_used_mb,
    ROUND(
        CASE 
            WHEN d.quota > 0 THEN (COALESCE(SUM(m.bytes), 0) / 1048576) / d.quota * 100
            ELSE 0 
        END, 2
    ) as domain_usage_percentage,
    d.created,
    d.modified
FROM domain d
LEFT JOIN mailbox m ON d.domain = m.domain
GROUP BY d.domain, d.description, d.quota, d.active, d.created, d.modified;

-- Active aliases view
CREATE OR REPLACE VIEW v_active_aliases AS
SELECT 
    a.id,
    a.address,
    a.goto,
    a.domain,
    a.created,
    a.modified,
    CASE 
        WHEN a.goto LIKE '%@%' THEN 'external'
        ELSE 'internal'
    END as alias_type,
    LENGTH(a.goto) - LENGTH(REPLACE(a.goto, ',', '')) + 1 as destination_count
FROM alias a
WHERE a.active = '1'
AND a.address != a.goto;  -- Exclude mailbox entries

-- Recent audit activity view
CREATE OR REPLACE VIEW v_recent_audit AS
SELECT 
    al.id,
    al.table_name,
    al.record_id,
    al.action,
    al.user_id,
    al.user_ip,
    al.created,
    CASE 
        WHEN al.table_name = 'mailbox' THEN CONCAT('Mailbox: ', al.record_id)
        WHEN al.table_name = 'domain' THEN CONCAT('Domain: ', al.record_id)
        WHEN al.table_name = 'alias' THEN CONCAT('Alias: ', al.record_id)
        ELSE CONCAT(al.table_name, ': ', al.record_id)
    END as description
FROM audit_log al
ORDER BY al.created DESC
LIMIT 100;

-- Quota alerts view (mailboxes over 80% usage)
CREATE OR REPLACE VIEW v_quota_alerts AS
SELECT 
    username,
    name,
    domain,
    quota_mb,
    used_mb,
    usage_percentage,
    CASE 
        WHEN usage_percentage >= 95 THEN 'critical'
        WHEN usage_percentage >= 85 THEN 'warning'
        WHEN usage_percentage >= 80 THEN 'info'
        ELSE 'ok'
    END as alert_level,
    created
FROM v_mailbox_usage
WHERE usage_percentage >= 80
ORDER BY usage_percentage DESC;

-- System statistics view
CREATE OR REPLACE VIEW v_system_stats AS
SELECT 
    'domains' as metric,
    COUNT(*) as total_count,
    COUNT(CASE WHEN active = '1' THEN 1 END) as active_count,
    NULL as percentage
FROM domain
UNION ALL
SELECT 
    'mailboxes' as metric,
    COUNT(*) as total_count,
    COUNT(CASE WHEN active = '1' THEN 1 END) as active_count,
    NULL as percentage
FROM mailbox
UNION ALL
SELECT 
    'aliases' as metric,
    COUNT(*) as total_count,
    COUNT(CASE WHEN active = '1' THEN 1 END) as active_count,
    NULL as percentage
FROM alias
WHERE address != goto
UNION ALL
SELECT 
    'quota_usage' as metric,
    ROUND(SUM(bytes) / 1048576, 2) as total_count,
    ROUND(SUM(quota), 2) as active_count,
    ROUND(
        CASE 
            WHEN SUM(quota) > 0 THEN (SUM(bytes) / 1048576) / SUM(quota) * 100
            ELSE 0 
        END, 2
    ) as percentage
FROM mailbox
WHERE active = '1';
EOF

    info "Database views created"
}

# Create seed data
create_seed_data() {
    log "Creating seed data..."
    
    mkdir -p "$SQL_DIR/seeds"
    
    cat > "$SQL_DIR/seeds/default_settings.sql" << 'EOF'
-- Default custom settings
INSERT IGNORE INTO custom_settings (setting_key, setting_value, setting_type, description, category) VALUES
('api_rate_limit', '100', 'integer', 'API requests per minute per IP', 'api'),
('api_burst_limit', '10', 'integer', 'API burst requests per second', 'api'),
('backup_retention_days', '30', 'integer', 'Number of days to keep backups', 'backup'),
('notification_email_enabled', 'true', 'boolean', 'Enable email notifications', 'notifications'),
('notification_webhook_enabled', 'false', 'boolean', 'Enable webhook notifications', 'notifications'),
('quota_warning_threshold', '80', 'integer', 'Quota warning threshold percentage', 'quota'),
('quota_critical_threshold', '95', 'integer', 'Quota critical threshold percentage', 'quota'),
('audit_log_retention_days', '90', 'integer', 'Number of days to keep audit logs', 'audit'),
('stats_collection_enabled', 'true', 'boolean', 'Enable statistics collection', 'stats'),
('auto_cleanup_enabled', 'true', 'boolean', 'Enable automatic cleanup of old data', 'maintenance');
EOF

    cat > "$SQL_DIR/seeds/admin_api_key.sql" << 'EOF'
-- Create default admin API key (will be updated during installation)
INSERT IGNORE INTO api_keys (
    key_name, 
    api_key, 
    description, 
    permissions, 
    allowed_ips,
    expires
) VALUES (
    'admin',
    'PLACEHOLDER_API_KEY',
    'Main administrative API key',
    JSON_OBJECT(
        'domains', JSON_ARRAY('read', 'write', 'delete'),
        'mailboxes', JSON_ARRAY('read', 'write', 'delete'),
        'aliases', JSON_ARRAY('read', 'write', 'delete'),
        'system', JSON_ARRAY('read', 'write'),
        'backup', JSON_ARRAY('create', 'restore'),
        'audit', JSON_ARRAY('read')
    ),
    JSON_ARRAY('127.0.0.1', '::1'),
    NULL
);
EOF

    info "Seed data created"
}

# Create maintenance scripts
create_maintenance_scripts() {
    log "Creating maintenance scripts..."
    
    mkdir -p "$SQL_DIR/maintenance"
    
    cat > "$SQL_DIR/maintenance/cleanup_old_data.sql" << 'EOF'
-- Cleanup old audit logs (older than retention period)
DELETE FROM audit_log 
WHERE created < DATE_SUB(NOW(), INTERVAL (
    SELECT CAST(setting_value AS UNSIGNED) 
    FROM custom_settings 
    WHERE setting_key = 'audit_log_retention_days'
) DAY);

-- Cleanup old notification queue entries (older than 30 days)
DELETE FROM notification_queue 
WHERE created < DATE_SUB(NOW(), INTERVAL 30 DAY)
AND status IN ('sent', 'failed');

-- Cleanup expired API keys
UPDATE api_keys 
SET active = 0 
WHERE expires IS NOT NULL 
AND expires < NOW() 
AND active = 1;

-- Update statistics
INSERT INTO mailbox_stats (username, date, messages_received, messages_sent, bytes_received, bytes_sent, last_login)
SELECT 
    m.username,
    CURDATE(),
    0, 0, 0, 0,  -- These would be populated by actual mail statistics
    NULL
FROM mailbox m
WHERE m.active = '1'
ON DUPLICATE KEY UPDATE
    updated = NOW();

-- Update domain statistics  
INSERT INTO domain_stats (domain, date, mailboxes_count, quota_used, quota_total)
SELECT 
    d.domain,
    CURDATE(),
    COUNT(m.username),
    COALESCE(SUM(m.bytes), 0),
    COALESCE(SUM(m.quota * 1048576), 0)
FROM domain d
LEFT JOIN mailbox m ON d.domain = m.domain AND m.active = '1'
WHERE d.active = '1'
GROUP BY d.domain
ON DUPLICATE KEY UPDATE
    mailboxes_count = VALUES(mailboxes_count),
    quota_used = VALUES(quota_used),
    quota_total = VALUES(quota_total),
    updated = NOW();
EOF

    cat > "$SQL_DIR/maintenance/optimize_tables.sql" << 'EOF'
-- Optimize database tables for better performance
OPTIMIZE TABLE mailbox;
OPTIMIZE TABLE domain;
OPTIMIZE TABLE alias;
OPTIMIZE TABLE audit_log;
OPTIMIZE TABLE mailbox_stats;
OPTIMIZE TABLE domain_stats;
OPTIMIZE TABLE api_keys;
OPTIMIZE TABLE custom_settings;
OPTIMIZE TABLE notification_queue;
OPTIMIZE TABLE backup_metadata;
EOF

    info "Maintenance scripts created"
}

# Execute SQL script
execute_sql_script() {
    local script_file="$1"
    local description="${2:-SQL script}"
    
    if [[ ! -f "$script_file" ]]; then
        error "SQL script not found: $script_file"
    fi
    
    log "Executing $description: $(basename "$script_file")"
    
    cd "$MAILCOW_DIR"
    
    if docker-compose exec -T "$DB_CONTAINER" mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" < "$script_file"; then
        info "$description executed successfully"
    else
        error "Failed to execute $description"
    fi
}

# Initialize database
initialize_database() {
    log "Initializing Mailcow database extensions..."
    
    check_db_connection
    
    # Create SQL directory structure
    init_sql_directory
    
    # Create database components
    create_custom_schema
    create_functions
    create_triggers  
    create_views
    create_seed_data
    create_maintenance_scripts
    
    # Execute initialization scripts
    execute_sql_script "$SQL_DIR/schemas/custom_tables.sql" "Custom schema"
    execute_sql_script "$SQL_DIR/functions/mailbox_functions.sql" "Database functions"
    execute_sql_script "$SQL_DIR/triggers/audit_triggers.sql" "Audit triggers"
    execute_sql_script "$SQL_DIR/views/reporting_views.sql" "Reporting views"
    execute_sql_script "$SQL_DIR/seeds/default_settings.sql" "Default settings"
    
    # Update admin API key if provided
    if [[ -n "$MAILCOW_API_KEY" ]]; then
        log "Updating admin API key in database..."
        cd "$MAILCOW_DIR"
        docker-compose exec -T "$DB_CONTAINER" mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" << EOF
UPDATE api_keys 
SET api_key = '$MAILCOW_API_KEY', updated = NOW() 
WHERE key_name = 'admin' AND api_key = 'PLACEHOLDER_API_KEY';
EOF
    fi
    
    log "Database initialization completed"
}

# Run database maintenance
run_maintenance() {
    log "Running database maintenance..."
    
    check_db_connection
    
    execute_sql_script "$SQL_DIR/maintenance/cleanup_old_data.sql" "Data cleanup"
    execute_sql_script "$SQL_DIR/maintenance/optimize_tables.sql" "Table optimization"
    
    # Update statistics
    cd "$MAILCOW_DIR"
    docker-compose exec -T "$DB_CONTAINER" mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" << 'EOF'
-- Refresh statistics
ANALYZE TABLE mailbox, domain, alias, audit_log;
EOF
    
    log "Database maintenance completed"
}

# Create database backup
create_db_backup() {
    local backup_name="${1:-db-backup-$(date +%Y%m%d_%H%M%S)}"
    
    log "Creating database backup: $backup_name"
    
    check_db_connection
    
    mkdir -p "$CONFIG_DIR/db-backups"
    
    cd "$MAILCOW_DIR"
    
    # Create database dump
    docker-compose exec -T "$DB_CONTAINER" mysqldump \
        -u root -p"$DB_ROOT_PASS" \
        --single-transaction \
        --routines \
        --triggers \
        --events \
        --hex-blob \
        "$DB_NAME" > "$CONFIG_DIR/db-backups/${backup_name}.sql"
    
    # Compress backup
    gzip "$CONFIG_DIR/db-backups/${backup_name}.sql"
    
    # Create metadata
    cat > "$CONFIG_DIR/db-backups/${backup_name}.meta" << EOF
# Database Backup Metadata
BACKUP_NAME=$backup_name
CREATED=$(date -Iseconds)
DATABASE=$DB_NAME
FILE_SIZE=$(stat -c%s "$CONFIG_DIR/db-backups/${backup_name}.sql.gz")
CHECKSUM=$(md5sum "$CONFIG_DIR/db-backups/${backup_name}.sql.gz" | cut -d' ' -f1)
EOF
    
    info "Database backup created: $CONFIG_DIR/db-backups/${backup_name}.sql.gz"
}

# Restore database backup  
restore_db_backup() {
    local backup_file="$1"
    local confirm="${2:-false}"
    
    if [[ -z "$backup_file" ]]; then
        error "Backup file is required"
    fi
    
    if [[ ! -f "$backup_file" ]]; then
        error "Backup file not found: $backup_file"
    fi
    
    # Confirmation
    if [[ "$confirm" != "true" ]]; then
        echo -e "${RED}WARNING: This will overwrite the current database!${NC}"
        echo -n "Are you sure you want to restore from backup? (yes/no): "
        read -r confirmation
        if [[ "$confirmation" != "yes" ]]; then
            info "Database restore cancelled"
            return 0
        fi
    fi
    
    log "Restoring database from backup: $backup_file"
    
    check_db_connection
    
    cd "$MAILCOW_DIR"
    
    # Decompress if needed
    if [[ "$backup_file" =~ \.gz$ ]]; then
        gunzip -c "$backup_file" | docker-compose exec -T "$DB_CONTAINER" mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME"
    else
        docker-compose exec -T "$DB_CONTAINER" mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" < "$backup_file"
    fi
    
    info "Database restored from backup"
}

# Show database status
show_db_status() {
    log "Checking database status..."
    
    check_db_connection
    
    cd "$MAILCOW_DIR"
    
    echo ""
    echo "${BLUE}Database Status:${NC}"
    echo "================="
    
    # Basic database info
    docker-compose exec -T "$DB_CONTAINER" mysql -u root -p"$DB_ROOT_PASS" -e "
    SELECT 
        'Database' as Component,
        DATABASE() as Name,
        VERSION() as Version,
        NOW() as Current_Time;
    "
    
    echo ""
    echo "${BLUE}Table Statistics:${NC}"
    echo "=================="
    
    # Table statistics
    docker-compose exec -T "$DB_CONTAINER" mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" -e "
    SELECT 
        table_name as Table_Name,
        table_rows as Rows,
        ROUND(((data_length + index_length) / 1024 / 1024), 2) as Size_MB,
        engine as Engine
    FROM information_schema.tables 
    WHERE table_schema = '$DB_NAME'
    ORDER BY (data_length + index_length) DESC;
    "
    
    echo ""
    echo "${BLUE}Custom Tables Status:${NC}"
    echo "====================="
    
    # Check if custom tables exist
    docker-compose exec -T "$DB_CONTAINER" mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" -e "
    SELECT 
        CASE 
            WHEN table_name IS NOT NULL THEN 'EXISTS'
            ELSE 'MISSING'
        END as Status,
        'api_keys' as Table_Name
    FROM information_schema.tables 
    WHERE table_schema = '$DB_NAME' AND table_name = 'api_keys'
    UNION ALL
    SELECT 
        CASE 
            WHEN table_name IS NOT NULL THEN 'EXISTS'
            ELSE 'MISSING'
        END as Status,
        'audit_log' as Table_Name
    FROM information_schema.tables 
    WHERE table_schema = '$DB_NAME' AND table_name = 'audit_log';
    "
}

# Show usage
show_usage() {
    cat << EOF
Mailcow Database Initialization and Management

Usage: $0 [action] [options]

Actions:
  init
    Initialize database with custom schema, functions, and triggers
    
  maintenance  
    Run database maintenance (cleanup, optimize)
    
  backup [name]
    Create database backup
    
  restore <backup_file> [--confirm]
    Restore database from backup
    
  status
    Show database status and statistics
    
  run-script <sql_file>
    Execute custom SQL script
    
  check-connection
    Test database connectivity

Options:
  --confirm       Skip confirmation prompts
  --help         Show this help message

Examples:
  $0 init
  $0 maintenance  
  $0 backup daily-backup
  $0 restore /path/to/backup.sql.gz --confirm
  $0 status
  $0 run-script /path/to/script.sql
  $0 check-connection

Files and directories:
  SQL scripts: $SQL_DIR
  Backups: $CONFIG_DIR/db-backups
  Log file: $LOG_FILE

EOF
}

# Main function
main() {
    local action="$1"
    shift
    
    # Load configuration
    load_config
    
    case "$action" in
        "init")
            initialize_database
            ;;
        "maintenance")
            run_maintenance
            ;;
        "backup")
            create_db_backup "$1"
            ;;
        "restore")
            local confirm=""
            for arg in "$@"; do
                if [[ "$arg" == "--confirm" ]]; then
                    confirm="true"
                    break
                fi
            done
            restore_db_backup "$1" "$confirm"
            ;;
        "status")
            show_db_status
            ;;
        "run-script")
            execute_sql_script "$1" "Custom SQL script"
            ;;
        "check-connection")
            check_db_connection
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