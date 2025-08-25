# Cold Email Dashboard - Deployment Guide

This guide provides comprehensive instructions for deploying the Cold Email Infrastructure Dashboard in various environments.

## Table of Contents

1. [Quick Start](#quick-start)
2. [Deployment Options](#deployment-options)
3. [System Requirements](#system-requirements)
4. [Configuration](#configuration)
5. [Security](#security)
6. [Monitoring](#monitoring)
7. [Backup & Restore](#backup--restore)
8. [Troubleshooting](#troubleshooting)

## Quick Start

### One-Command Deployment

For most users, the quickest way to get started is with the automated quick-start script:

```bash
# Basic deployment (development/testing)
sudo ./quick-start.sh

# Full production deployment with SSL and nginx
sudo ./quick-start.sh --full --domain dashboard.yourdomain.com --email admin@yourdomain.com

# Docker deployment
sudo ./quick-start.sh --mode docker --domain dashboard.yourdomain.com

# Check system requirements only
sudo ./quick-start.sh --check-only
```

### Manual Steps (if you prefer more control)

1. **System Validation**
   ```bash
   sudo ./quick-start.sh --check-only
   ```

2. **Native Deployment**
   ```bash
   sudo ./deploy.sh
   ```

3. **Docker Deployment**
   ```bash
   ./docker-start.sh start
   ```

## Deployment Options

### 1. Native Deployment (Recommended for Production)

**Features:**
- Systemd service management
- Full system integration
- Production-ready security
- Automated backups and monitoring

**Steps:**
```bash
# Full deployment
sudo ./deploy.sh

# Or use quick-start for guided deployment
sudo ./quick-start.sh --mode native --full
```

**What gets installed:**
- Python virtual environment at `/opt/cold-email-dashboard/venv`
- Application files at `/opt/cold-email-dashboard/dashboard`
- Systemd service `cold-email-dashboard`
- Configuration at `/etc/cold-email-dashboard/dashboard.env`
- Logs at `/var/log/cold-email-dashboard/`
- Backups at `/opt/cold-email-dashboard/backups/`

### 2. Docker Deployment (Recommended for Development)

**Features:**
- Isolated container environment
- Easy scaling and management
- Includes nginx proxy and Redis
- Quick setup and teardown

**Steps:**
```bash
# Start all services
./docker-start.sh start

# View logs
./docker-start.sh logs

# Stop services
./docker-start.sh stop
```

**Services included:**
- Dashboard (Flask application)
- Nginx (reverse proxy)
- Redis (caching/sessions)

### 3. Minimal Deployment (Development Only)

**Features:**
- Local development environment
- No system services
- Manual start/stop

**Steps:**
```bash
sudo ./quick-start.sh --mode minimal
cd dashboard
source venv/bin/activate
python app.py
```

## System Requirements

### Minimum Requirements
- **OS**: Ubuntu 18.04+ or Debian 10+
- **RAM**: 512MB (1GB recommended)
- **Disk**: 2GB free space
- **CPU**: 1 core
- **Network**: Internet connection for package installation

### Recommended for Production
- **OS**: Ubuntu 20.04 LTS or Ubuntu 22.04 LTS
- **RAM**: 2GB or more
- **Disk**: 10GB+ free space (for logs and backups)
- **CPU**: 2+ cores
- **Network**: Static IP address, proper DNS configuration

### Required Ports
- **80**: HTTP (will redirect to HTTPS)
- **443**: HTTPS
- **5000**: Dashboard (if not using nginx proxy)

## Configuration

### Environment Variables

The dashboard can be configured through environment variables:

#### Core Settings
```bash
FLASK_ENV=production                    # Flask environment
FLASK_PORT=5000                        # Port to run on
FLASK_SECRET_KEY=your-secret-key       # Change in production!
API_KEY=your-api-key                   # Change in production!
```

#### Email Configuration
```bash
DOMAIN=yourdomain.com                  # Your email domain
SERVER_IP=your.server.ip               # Your server's IP address
ADMIN_EMAIL=admin@yourdomain.com       # Administrator email
DMARC_EMAIL=dmarc@yourdomain.com       # DMARC reports email
```

#### SMTP Settings
```bash
SMTP_HOST=mail.yourdomain.com          # SMTP server
SMTP_PORT=587                          # SMTP port
SMTP_SECURITY=tls                      # tls, ssl, or none
SMTP_USER=your-smtp-user               # SMTP username
SMTP_PASSWORD=your-smtp-password       # SMTP password
```

#### External Services
```bash
CLOUDFLARE_API_TOKEN=your-token        # Cloudflare API token
MAILCOW_API_KEY=your-api-key          # Mailcow API key
MAILCOW_HOSTNAME=mail.yourdomain.com   # Mailcow hostname
```

### Configuration Files

#### Native Deployment
- Main config: `/etc/cold-email-dashboard/dashboard.env`
- Systemd service: `/etc/systemd/system/cold-email-dashboard.service`
- Nginx config: `/etc/nginx/sites-available/dashboard`

#### Docker Deployment
- Main config: `.env` (copy from `.env.example`)
- Docker compose: `docker-compose.yml`
- Nginx config: `nginx/dashboard.conf`

### SSL Certificate Configuration

#### Let's Encrypt (Recommended)
```bash
# Automatic setup
sudo ./ssl/setup-ssl.sh dashboard.yourdomain.com admin@yourdomain.com letsencrypt

# Or through quick-start
sudo ./quick-start.sh --ssl --domain dashboard.yourdomain.com
```

#### Self-Signed (Development)
```bash
sudo ./ssl/setup-ssl.sh dashboard.yourdomain.com admin@yourdomain.com selfsigned
```

#### Import Existing Certificate
```bash
sudo ./ssl/setup-ssl.sh dashboard.yourdomain.com admin@yourdomain.com import /path/to/cert.pem /path/to/key.pem
```

## Security

### Production Security Checklist

- [ ] Change default secret keys and API keys
- [ ] Use HTTPS with valid SSL certificates
- [ ] Configure firewall (UFW recommended)
- [ ] Set up fail2ban for intrusion prevention
- [ ] Use strong passwords for all accounts
- [ ] Regularly update system packages
- [ ] Monitor logs for suspicious activity
- [ ] Implement proper backup strategy
- [ ] Restrict admin interface access by IP (optional)

### Firewall Configuration

The deployment scripts automatically configure UFW firewall:

```bash
# Allow required ports
sudo ufw allow ssh
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 5000/tcp
sudo ufw enable
```

### Security Headers

The nginx configuration includes security headers:
- Strict-Transport-Security (HSTS)
- X-Frame-Options
- X-Content-Type-Options
- X-XSS-Protection
- Content-Security-Policy
- Referrer-Policy

## Monitoring

### Health Checks

The dashboard includes comprehensive health checking:

```bash
# Check application health
curl http://localhost:5000/api/health

# Detailed health check
python3 monitoring/health_checks.py --check all

# System resource monitoring
curl http://localhost:5000/api/metrics/system
```

### Log Files

#### Native Deployment
- Application logs: `/var/log/cold-email-dashboard/`
- Systemd logs: `journalctl -u cold-email-dashboard -f`
- Nginx logs: `/var/log/nginx/dashboard_*`

#### Docker Deployment
```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f dashboard
```

### Monitoring Scripts

Automated monitoring scripts are installed:
- Nginx monitoring: `/usr/local/bin/nginx-monitor.sh`
- SSL certificate monitoring: `/usr/local/bin/monitor-dashboard-ssl.sh`
- Health checks: `monitoring/health_checks.py`

## Backup & Restore

### Automated Backups

```bash
# Run full backup
sudo ./scripts/backup.sh full

# Configuration only
sudo ./scripts/backup.sh config

# Set up automatic daily backups (done during deployment)
# Backups run at 2 AM daily via cron
```

### Manual Backup

```bash
# Create a manual backup
sudo ./scripts/backup.sh full

# List available backups
sudo ./scripts/restore.sh list
```

### Restore from Backup

```bash
# Interactive restore
sudo ./scripts/restore.sh

# Restore specific backup
sudo ./scripts/restore.sh /path/to/backup.tar.gz

# Restore only configuration
sudo ./scripts/restore.sh /path/to/backup.tar.gz config
```

### Backup Storage

#### Local Storage
- Default location: `/opt/cold-email-dashboard/backups/`
- Retention: 30 days (configurable)
- Automatic cleanup of old backups

#### S3 Storage (Optional)
Configure S3 backup in environment:
```bash
BACKUP_S3_BUCKET=your-backup-bucket
BACKUP_S3_REGION=us-east-1
AWS_ACCESS_KEY_ID=your-access-key
AWS_SECRET_ACCESS_KEY=your-secret-key
```

## Troubleshooting

### Common Issues

#### Dashboard Not Starting
```bash
# Check service status
sudo systemctl status cold-email-dashboard

# View logs
sudo journalctl -u cold-email-dashboard -f

# Check configuration
sudo python3 monitoring/health_checks.py --check flask
```

#### Port Already in Use
```bash
# Check what's using the port
sudo netstat -tulnp | grep :5000

# Kill process if needed
sudo fuser -k 5000/tcp
```

#### Permission Issues
```bash
# Fix ownership
sudo chown -R dashboard:dashboard /opt/cold-email-dashboard/
sudo chown -R dashboard:dashboard /var/log/cold-email-dashboard/

# Fix permissions
sudo chmod 640 /etc/cold-email-dashboard/dashboard.env
sudo chmod +x /opt/cold-email-dashboard/dashboard/*.sh
```

#### SSL Certificate Issues
```bash
# Check certificate validity
sudo openssl x509 -in /etc/ssl/dashboard/dashboard.crt -noout -dates

# Test SSL connection
sudo ./ssl/setup-ssl.sh dashboard.yourdomain.com admin@yourdomain.com letsencrypt

# Monitor SSL status
sudo /usr/local/bin/monitor-dashboard-ssl.sh
```

#### Docker Issues
```bash
# Check container status
docker-compose ps

# View container logs
docker-compose logs dashboard

# Restart containers
docker-compose restart

# Rebuild containers
docker-compose up --build -d
```

### Log Analysis

#### Find Errors
```bash
# Application errors
sudo grep -i error /var/log/cold-email-dashboard/dashboard.log

# Nginx errors
sudo grep -i error /var/log/nginx/dashboard_error.log

# System errors
sudo journalctl -u cold-email-dashboard --no-pager | grep -i error
```

#### Monitor Performance
```bash
# System resources
curl http://localhost:5000/api/metrics/system

# Process monitoring
ps aux | grep python

# Memory usage
free -h

# Disk usage
df -h
```

### Getting Help

If you encounter issues:

1. **Check the logs** - Most issues are revealed in the application or system logs
2. **Verify configuration** - Ensure all required environment variables are set
3. **Test connectivity** - Check that required ports are open and services are running
4. **Review system requirements** - Ensure your system meets the minimum requirements
5. **Run health checks** - Use the built-in health checking tools

### Support Commands

```bash
# Generate system report
sudo python3 monitoring/health_checks.py --check all --format json > system-report.json

# Test all components
sudo ./quick-start.sh --check-only

# Validate configuration
sudo nginx -t  # Test nginx config
sudo systemctl is-active cold-email-dashboard  # Check service status
```

## Advanced Configuration

### Custom Nginx Configuration

To customize the nginx configuration:

1. Edit `/etc/nginx/sites-available/dashboard`
2. Test configuration: `sudo nginx -t`
3. Reload nginx: `sudo systemctl reload nginx`

### Custom Systemd Service

To modify the systemd service:

1. Edit `/etc/systemd/system/cold-email-dashboard.service`
2. Reload systemd: `sudo systemctl daemon-reload`
3. Restart service: `sudo systemctl restart cold-email-dashboard`

### Database Integration

For persistent data storage, you can integrate with PostgreSQL or MySQL:

1. Install database server
2. Create database and user
3. Update configuration with database connection details
4. Restart the dashboard service

### Load Balancing

For high-availability deployments:

1. Deploy multiple dashboard instances
2. Configure nginx upstream blocks
3. Use shared storage for session data
4. Implement database clustering

## Maintenance

### Regular Maintenance Tasks

#### Weekly
- Check log files for errors
- Verify SSL certificate validity
- Review system resource usage
- Test backup/restore procedures

#### Monthly
- Update system packages
- Review and rotate log files
- Check disk space usage
- Update SSL certificates if needed

#### Quarterly
- Review security configuration
- Update application dependencies
- Test disaster recovery procedures
- Review monitoring and alerting

### Update Procedures

#### Application Updates
```bash
# Backup current version
sudo ./scripts/backup.sh full

# Update application code
git pull origin main

# Restart services
sudo systemctl restart cold-email-dashboard
```

#### System Updates
```bash
# Update packages
sudo apt update && sudo apt upgrade

# Reboot if kernel updated
sudo reboot
```

This deployment guide should cover most scenarios and provide a solid foundation for running the Cold Email Dashboard in production environments.