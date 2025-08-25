# VPS Automation Infrastructure for Cold Email System

This directory contains comprehensive VPS automation tools for setting up and managing a cold email infrastructure on Ubuntu 22.04 LTS or Debian 12.

## 🏗️ Directory Structure

```
vps/
├── scripts/                    # Executable scripts
│   ├── setup-vps.sh           # Main VPS setup script
│   ├── health-check.sh        # System health monitoring
│   └── system-info.sh         # System information gathering
├── config/                     # Configuration templates
│   ├── network-config.yaml    # Network interface configuration
│   ├── firewall-rules.json    # Firewall rules definition
│   └── alert-thresholds.yaml  # Health monitoring thresholds
├── vps_manager.py             # Python VPS management module
├── monitoring/                 # Generated monitoring scripts
├── logs/                      # System and setup logs
└── README.md                  # This file
```

## 🚀 Quick Start

### 1. Initial VPS Setup

Run the main setup script as root:

```bash
sudo ./scripts/setup-vps.sh
```

This script will:
- ✅ Update the system packages
- ✅ Install required dependencies (Docker, UFW, Fail2Ban, etc.)
- ✅ Configure network interfaces with multiple IPs
- ✅ Set up firewall rules for mail server ports
- ✅ Configure security tools and monitoring
- ✅ Create health check and monitoring scripts

### 2. Configure Your IPs

Edit the network configuration file:

```bash
sudo nano config/network-config.yaml
```

Add your additional IP addresses:

```yaml
additional_ips:
  - ip: "YOUR_IP_1"
    netmask: "24"
    comment: "Email sending IP 1"
    enabled: true
  - ip: "YOUR_IP_2" 
    netmask: "24"
    comment: "Email sending IP 2"
    enabled: true
```

### 3. Apply Network Configuration

After editing the configuration, restart networking:

```bash
sudo systemctl restart networking
# or reboot the system
sudo reboot
```

### 4. Verify Setup

Run the health check script:

```bash
sudo ./scripts/health-check.sh
```

Check system information:

```bash
./scripts/system-info.sh
```

## 📊 VPS Manager Python Module

The `vps_manager.py` module provides programmatic access to VPS management functions.

### Installation

Install required Python packages:

```bash
pip3 install psutil PyYAML requests ping3
```

### Usage Examples

#### Check VPS Status

```bash
python3 vps_manager.py status
```

#### List Available IP Addresses

```bash
python3 vps_manager.py ips
```

#### Show Network Interfaces

```bash
python3 vps_manager.py interfaces
```

#### Add IP Alias

```bash
python3 vps_manager.py add-ip 192.168.1.100 --interface eth0
```

#### Remove IP Alias

```bash
python3 vps_manager.py remove-ip 192.168.1.100
```

#### IP Rotation for Email Sending

```bash
python3 vps_manager.py rotate-ip --exclude 192.168.1.99
```

#### Monitor IP Health

```bash
python3 vps_manager.py monitor 192.168.1.100
```

### Python API Usage

```python
from vps_manager import VPSManager

# Initialize manager
vps = VPSManager()

# Get available IPs
ips = vps.get_available_ips()
print(f"Available IPs: {ips}")

# Get VPS status
status = vps.get_vps_status()
print(f"System health: {status['overall_status']}")

# Rotate IP for sending
sending_ip = vps.rotate_ip_for_sending()
print(f"Use IP for sending: {sending_ip}")
```

## ⚙️ Configuration Files

### Network Configuration (`network-config.yaml`)

Controls network interface setup and IP management:

- **Primary interface**: Auto-detected main network interface
- **Additional IPs**: List of extra IP addresses for email sending
- **DNS servers**: DNS resolver configuration
- **IP rotation**: Settings for rotating IPs during email campaigns
- **Health monitoring**: IP health check configuration

### Firewall Rules (`firewall-rules.json`)

Defines comprehensive firewall rules:

- **Mail server ports**: 25, 587, 465, 143, 993, 110, 995
- **Web server ports**: 80, 443
- **SSH access**: Port 22 with rate limiting
- **Security policies**: Brute force protection, geo-blocking
- **Custom rules**: Environment-specific configurations

### Alert Thresholds (`alert-thresholds.yaml`)

Sets monitoring and alerting thresholds:

- **System resources**: CPU, memory, disk usage limits
- **Network**: Connectivity and performance thresholds
- **Services**: Required service monitoring
- **Security**: Failed login attempt limits
- **Email specific**: IP health and sending limits

## 🔧 Scripts

### Main Setup Script (`setup-vps.sh`)

Comprehensive VPS setup with the following features:

**System Configuration:**
- OS detection (Ubuntu 22.04 LTS / Debian 12)
- System package updates
- Required software installation
- Service configuration

**Network Setup:**
- Multiple IP address configuration
- Network interface management
- DNS configuration
- Connectivity testing

**Security Configuration:**
- UFW firewall setup
- Fail2Ban intrusion prevention
- SSH hardening
- Log monitoring

**Features:**
- ✅ Idempotent (safe to run multiple times)
- ✅ Comprehensive error handling
- ✅ Detailed logging
- ✅ Configuration backup
- ✅ Rollback capabilities

### Health Check Script (`health-check.sh`)

Monitors system health with:

- **System Resources**: CPU, memory, disk usage
- **Network Status**: Interface status, connectivity tests
- **Service Monitoring**: Docker, UFW, Fail2Ban status
- **Port Checking**: Mail server and web ports
- **Security Analysis**: Failed login attempts, active connections

**Usage Options:**
```bash
# Full health check
./scripts/health-check.sh

# Quiet mode (minimal output)
./scripts/health-check.sh --quiet

# JSON output
./scripts/health-check.sh --json
```

### System Info Script (`system-info.sh`)

Gathers comprehensive system information:

```bash
# Show all information
./scripts/system-info.sh

# Show specific sections
./scripts/system-info.sh --system
./scripts/system-info.sh --network
./scripts/system-info.sh --security
./scripts/system-info.sh --docker
./scripts/system-info.sh --mail
```

## 📈 Monitoring and Alerting

### Automated Health Checks

Set up automated health checks with cron:

```bash
# Add to crontab
crontab -e

# Check every 15 minutes
*/15 * * * * /path/to/vps/scripts/health-check.sh --quiet >> /var/log/health-check.log 2>&1
```

### Log Files

Important log files to monitor:

- **Setup logs**: `logs/vps-setup-YYYYMMDD_HHMMSS.log`
- **Health check logs**: `logs/health-check-YYYYMMDD_HHMMSS.log`
- **VPS manager logs**: `logs/vps-manager-YYYYMMDD.log`
- **System logs**: `/var/log/syslog`, `/var/log/auth.log`

### Status Files

JSON status files for external monitoring:

- **VPS Status**: `monitoring/vps-status.json`
- **Health Status**: Updated by health check script

## 🔐 Security Features

### Firewall Configuration

- **Default Deny**: All incoming traffic denied by default
- **Mail Ports**: Properly configured for email services
- **Rate Limiting**: SSH and mail server rate limits
- **Geo-blocking**: Optional country-based blocking
- **Port Scanning Detection**: Automatic threat detection

### Intrusion Prevention

- **Fail2Ban**: Automatic IP banning for repeated failures
- **SSH Protection**: Failed login attempt monitoring
- **Mail Security**: SMTP abuse prevention
- **Log Monitoring**: Real-time threat analysis

### Access Control

- **SSH Hardening**: Secure SSH configuration
- **Key-based Authentication**: Recommended setup
- **Multi-factor Authentication**: Optional integration
- **Network Segmentation**: Interface-based isolation

## 🚨 Troubleshooting

### Common Issues

**Network Configuration Problems:**
```bash
# Check interface status
ip addr show

# Test connectivity
ping -c3 8.8.8.8

# Restart networking
sudo systemctl restart networking
```

**Firewall Issues:**
```bash
# Check UFW status
sudo ufw status verbose

# Reset firewall (CAUTION)
sudo ufw --force reset

# Re-run setup script
sudo ./scripts/setup-vps.sh
```

**Service Problems:**
```bash
# Check service status
systemctl status docker ufw fail2ban

# Restart services
sudo systemctl restart docker
sudo systemctl restart ufw
sudo systemctl restart fail2ban
```

**IP Management Issues:**
```bash
# List all IPs
python3 vps_manager.py ips

# Check network interfaces
python3 vps_manager.py interfaces

# Test IP connectivity
python3 vps_manager.py monitor IP_ADDRESS
```

### Log Analysis

Check logs for issues:

```bash
# Setup logs
tail -f logs/vps-setup-*.log

# Health check logs  
tail -f logs/health-check-*.log

# System logs
sudo tail -f /var/log/syslog

# Security logs
sudo tail -f /var/log/auth.log

# Firewall logs
sudo tail -f /var/log/ufw.log
```

### Recovery Procedures

**Network Recovery:**
```bash
# Restore backup configuration
sudo cp /etc/network/backup-*/interfaces /etc/network/

# Restart networking
sudo systemctl restart networking
```

**Firewall Recovery:**
```bash
# Emergency firewall disable (if locked out)
sudo ufw --force disable

# Re-enable with setup script
sudo ./scripts/setup-vps.sh
```

## 📚 Advanced Usage

### Custom Integration

The VPS manager can be integrated into larger email infrastructure systems:

```python
# Example integration with email sender
from vps_manager import VPSManager

class EmailSender:
    def __init__(self):
        self.vps = VPSManager()
    
    def send_campaign(self, emails):
        # Get healthy IP for sending
        sending_ip = self.vps.rotate_ip_for_sending()
        
        # Configure mail server to use this IP
        self.configure_sending_ip(sending_ip)
        
        # Monitor IP health during sending
        health = self.vps.monitor_ip_health(sending_ip)
        
        if health['reachable']:
            return self.send_emails(emails)
        else:
            raise Exception(f"IP {sending_ip} is not healthy")
```

### Environment Management

Different configurations for different environments:

```bash
# Development environment
cp config/network-config.yaml config/network-config-dev.yaml
python3 vps_manager.py --config config/

# Production environment
cp config/network-config.yaml config/network-config-prod.yaml
python3 vps_manager.py --config /etc/email-infrastructure/
```

## 📞 Support and Maintenance

### Regular Maintenance Tasks

1. **Weekly System Updates**:
   ```bash
   sudo apt update && sudo apt upgrade -y
   ```

2. **Log Rotation**:
   ```bash
   sudo logrotate -f /etc/logrotate.d/cold-email-infrastructure
   ```

3. **Health Check Review**:
   ```bash
   ./scripts/health-check.sh --json | jq '.alerts'
   ```

4. **Security Audit**:
   ```bash
   ./scripts/system-info.sh --security
   ```

### Backup Procedures

Critical files to backup:

- Configuration files: `config/`
- Network configuration: `/etc/network/`
- Firewall rules: `/etc/ufw/`
- SSL certificates: `/etc/letsencrypt/`
- Email data: `/var/mail/`
- Logs: `logs/`

### Update Procedures

To update the VPS infrastructure:

1. Backup current configuration
2. Update script files
3. Review configuration changes
4. Test in staging environment
5. Apply to production
6. Monitor for issues

## 📋 Requirements

### System Requirements

- **OS**: Ubuntu 22.04 LTS or Debian 12
- **RAM**: Minimum 2GB, recommended 4GB+
- **Disk**: Minimum 20GB, recommended 50GB+
- **Network**: Multiple IP addresses for email sending
- **Root Access**: Required for system configuration

### Software Dependencies

Automatically installed by setup script:

- Docker and docker-compose
- UFW firewall
- Fail2Ban
- Python 3 with pip
- Network utilities (net-tools, ifupdown)
- Security tools (fail2ban, logrotate)

### Python Dependencies

```bash
pip3 install psutil PyYAML requests ping3
```

## 📄 License

This VPS automation infrastructure is part of the Cold Email Infrastructure project.

## 🤝 Contributing

Contributions are welcome! Please:

1. Test changes thoroughly
2. Update documentation
3. Follow security best practices
4. Add appropriate error handling
5. Include logging for debugging

---

**⚠️ Important Security Notes:**

- Always change default passwords
- Use SSH key authentication
- Regularly update the system
- Monitor logs for suspicious activity
- Test configurations in staging first
- Keep backups of critical configurations
- Review firewall rules regularly