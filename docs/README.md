# Cold Email Infrastructure - Documentation Hub

## Overview

Welcome to the comprehensive documentation for the Cold Email Infrastructure system. This documentation provides everything you need to understand, deploy, configure, and extend this complete cold email automation platform.

## 📚 Documentation Structure

### 🚀 Getting Started

| Document | Description | Target Audience |
|----------|-------------|-----------------|
| [Installation Guide](setup/installation-guide.md) | Complete step-by-step installation instructions | System Administrators, DevOps |
| [Configuration Guide](setup/configuration-guide.md) | Unified configuration system documentation | Administrators, Developers |
| [Troubleshooting Guide](setup/troubleshooting.md) | Common issues and solutions | All Users |

### 🏗️ Architecture & Components

| Document | Description | Target Audience |
|----------|-------------|-----------------|
| [Component Architecture](architecture/components.md) | Detailed system architecture and components | Developers, Architects |
| [API Reference](api/endpoints.md) | Complete API documentation with examples | Developers, Integrators |

### 🛡️ Operations & Security

| Document | Description | Target Audience |
|----------|-------------|-----------------|
| [Security Guide](operations/security.md) | Security best practices and configurations | Security Engineers, Administrators |
| [Backup & Recovery](operations/backup-restore.md) | Backup strategies and recovery procedures | System Administrators |
| [Monitoring & Alerting](operations/monitoring.md) | System monitoring and alert configuration | Operations Teams |
| [Maintenance Guide](operations/maintenance.md) | Ongoing maintenance procedures | System Administrators |

### 👩‍💻 Development

| Document | Description | Target Audience |
|----------|-------------|-----------------|
| [Developer Guide](development/developer-guide.md) | Complete development documentation | Developers |
| [Contributing Guidelines](../CONTRIBUTING.md) | How to contribute to the project | Contributors |
| [API Development](development/api-development.md) | Building new API endpoints | Developers |

## 🎯 Quick Navigation

### By Role

#### System Administrators
1. **Start Here**: [Installation Guide](setup/installation-guide.md)
2. **Configuration**: [Configuration Guide](setup/configuration-guide.md)
3. **Security**: [Security Guide](operations/security.md)
4. **Maintenance**: [Monitoring Guide](operations/monitoring.md)
5. **Troubleshooting**: [Troubleshooting Guide](setup/troubleshooting.md)

#### Developers
1. **Architecture**: [Component Architecture](architecture/components.md)
2. **API Reference**: [API Documentation](api/endpoints.md)
3. **Development**: [Developer Guide](development/developer-guide.md)
4. **Contributing**: [Contributing Guidelines](../CONTRIBUTING.md)

#### DevOps Engineers
1. **Deployment**: [Installation Guide](setup/installation-guide.md)
2. **Configuration**: [Configuration Guide](setup/configuration-guide.md)
3. **Security**: [Security Guide](operations/security.md)
4. **Monitoring**: [Monitoring Guide](operations/monitoring.md)

### By Component

#### DNS Management
- **Architecture**: [DNS Component](architecture/components.md#dns-management-component)
- **Configuration**: [DNS Configuration](setup/configuration-guide.md#dns-configuration)
- **API**: [DNS API Endpoints](api/endpoints.md#dns-management-api)
- **Source**: [DNS Component README](../src/email-infrastructure/dns/README.md)

#### Mailcow Management
- **Architecture**: [Mailcow Component](architecture/components.md#mailcow-management-component)
- **Configuration**: [Mailcow Configuration](setup/configuration-guide.md#mailcow-configuration)
- **API**: [Mailcow API Endpoints](api/endpoints.md#mailcow-management-api)
- **Source**: [Mailcow Component README](../src/email-infrastructure/mailcow/README.md)

#### Monitoring System
- **Architecture**: [Monitoring Component](architecture/components.md#monitoring-component)
- **Configuration**: [Monitoring Configuration](setup/configuration-guide.md#monitoring-configuration)
- **API**: [Monitoring API Endpoints](api/endpoints.md#monitoring-api)
- **Security**: [Monitoring Security](operations/security.md#monitoring-and-logging)

#### VPS Management
- **Architecture**: [VPS Component](architecture/components.md#vps-management-component)
- **Configuration**: [VPS Configuration](setup/configuration-guide.md#vps-configuration)
- **API**: [VPS API Endpoints](api/endpoints.md#vps-management-api)
- **Security**: [VPS Security](operations/security.md#server-hardening)

## 🔧 Common Tasks

### Initial Setup
```bash
# 1. Quick installation
curl -fsSL https://raw.githubusercontent.com/your-repo/cold-email-infrastructure/main/scripts/install/quick-install.sh | bash -s -- \
  --domain mail.yourdomain.com \
  --ip your.server.ip \
  --email admin@yourdomain.com \
  --token your_cloudflare_api_token

# 2. Validate installation
./scripts/utilities/validate-setup.sh yourdomain.com your.server.ip
```

### Daily Operations
```bash
# Check system status
./scripts/utilities/validate-setup.sh yourdomain.com your.server.ip --health-check

# View logs
tail -f /var/log/email-infrastructure.log

# Create backup
./src/email-infrastructure/mailcow/backup/backup-manager.sh create daily

# Check blacklist status
python3 -c "
from email_infrastructure.monitoring.monitors.blacklist_monitor import BlacklistMonitor
monitor = BlacklistMonitor()
status = monitor.check_ip_blacklist('your.server.ip')
print('Blacklist Status:', status['status'])
"
```

### Configuration Updates
```bash
# Update configuration
nano config/environments/production.yaml

# Validate configuration
python3 config/config.py --validate --environment production

# Reload configuration
python3 -c "
from email_infrastructure.core.config_manager import get_config_manager
config_manager = get_config_manager()
config_manager.reload_config()
print('Configuration reloaded')
"
```

### Development Tasks
```bash
# Set up development environment
python3 -m venv venv
source venv/bin/activate
pip install -r requirements-dev.txt
pip install -e .

# Run tests
pytest --cov=src/email-infrastructure

# Start development API server
uvicorn email_infrastructure.api.main:app --reload --host 0.0.0.0 --port 8000
```

## 📋 Checklists

### Pre-Deployment Checklist
- [ ] Review [System Requirements](setup/installation-guide.md#prerequisites)
- [ ] Configure [DNS Settings](setup/installation-guide.md#dns-configuration)
- [ ] Set up [Cloudflare Account](setup/installation-guide.md#required-accounts--access)
- [ ] Generate [API Tokens](setup/configuration-guide.md#environment-variables)
- [ ] Plan [Security Configuration](operations/security.md#initial-security-setup)
- [ ] Design [Backup Strategy](operations/backup-restore.md)

### Post-Deployment Checklist
- [ ] Verify [System Health](setup/troubleshooting.md#system-health-check)
- [ ] Test [Email Delivery](setup/installation-guide.md#email-delivery-test)
- [ ] Configure [Monitoring](operations/monitoring.md)
- [ ] Set up [Alerts](operations/monitoring.md#alert-configuration)
- [ ] Schedule [Backups](operations/backup-restore.md)
- [ ] Document [Custom Configuration](setup/configuration-guide.md)

### Security Review Checklist
- [ ] Complete [Server Hardening](operations/security.md#server-hardening)
- [ ] Configure [Firewall Rules](operations/security.md#firewall-configuration)
- [ ] Set up [TLS/SSL](operations/security.md#tlsssl-security)
- [ ] Review [API Security](operations/security.md#api-security)
- [ ] Enable [Audit Logging](operations/security.md#audit-logging)
- [ ] Test [Backup Encryption](operations/security.md#backup-security)

## 🆘 Support & Help

### Getting Help

1. **Documentation**: Search this documentation first
2. **Troubleshooting**: Check the [Troubleshooting Guide](setup/troubleshooting.md)
3. **Logs**: Review system logs for detailed error information
4. **Community**: Join our community discussions
5. **Issues**: Report bugs or request features on GitHub

### Common Questions

**Q: How do I add a new domain?**
```bash
./src/email-infrastructure/mailcow/automation/domain-manager.sh add newdomain.com "New Domain" 5120 25 500
```

**Q: How do I check if my server is blacklisted?**
```bash
python3 -c "
from email_infrastructure.monitoring.monitors.blacklist_monitor import BlacklistMonitor
monitor = BlacklistMonitor()
status = monitor.check_ip_blacklist('your.server.ip')
print(status)
"
```

**Q: How do I backup my configuration?**
```bash
./src/email-infrastructure/mailcow/backup/backup-manager.sh create config
```

**Q: How do I update DNS records?**
```bash
./src/email-infrastructure/dns/scripts/record-generator.sh -d yourdomain.com -i your.server.ip --deploy
```

### Log File Locations

| Component | Log File | Purpose |
|-----------|----------|---------|
| System | `/var/log/email-infrastructure.log` | Main system log |
| DNS | `/var/log/email-infrastructure-dns.log` | DNS operations |
| Mailcow | `/opt/mailcow-dockerized/data/logs/` | Mail server logs |
| Monitoring | `/var/log/email-infrastructure-monitoring.log` | Monitoring activities |
| Installation | `/var/log/email-infrastructure-install.log` | Installation process |

### Debug Commands

```bash
# Enable debug logging
export EMAIL_INFRA_LOG_LEVEL=DEBUG

# Test component connectivity
python3 -c "
from email_infrastructure.dns.managers.dns_manager import DNSManager
from email_infrastructure.mailcow.core.api_client import MailcowAPI
from email_infrastructure.monitoring.monitors.blacklist_monitor import BlacklistMonitor

dns = DNSManager()
mail = MailcowAPI()
monitor = BlacklistMonitor()

print('DNS:', 'OK' if dns.test_connection() else 'FAILED')
print('Mailcow:', 'OK' if mail.test_connection() else 'FAILED')
print('Monitoring:', 'OK')
"

# Validate complete system
./scripts/utilities/validate-setup.sh yourdomain.com your.server.ip --verbose --debug
```

## 📊 System Overview

### Architecture Summary

The Cold Email Infrastructure is built with a modular architecture consisting of:

- **DNS Component**: Cloudflare integration for automated DNS management
- **Mailcow Component**: Complete mail server deployment and management
- **Monitoring Component**: Blacklist monitoring and email warmup campaigns
- **VPS Component**: Server provisioning and management
- **Unified API**: RESTful API for all system operations
- **Configuration System**: Hierarchical configuration management

### Key Features

- ✅ **One-Command Installation**: Complete system deployment in minutes
- ✅ **Automated DNS Management**: Cloudflare integration with record generation
- ✅ **Mail Server Automation**: Mailcow deployment with API management
- ✅ **Comprehensive Monitoring**: Blacklist checking and warmup campaigns
- ✅ **Security Hardening**: Multi-layer security with best practices
- ✅ **Unified Configuration**: Environment-based configuration management
- ✅ **Complete API Coverage**: RESTful API for all operations
- ✅ **Backup & Recovery**: Automated backup with encryption
- ✅ **Production Ready**: Scalable architecture with monitoring

## 🚀 What's Next?

### Recommended Learning Path

1. **Understand the Architecture**: Read [Component Architecture](architecture/components.md)
2. **Deploy the System**: Follow [Installation Guide](setup/installation-guide.md)
3. **Configure for Production**: Use [Configuration Guide](setup/configuration-guide.md)
4. **Secure Your Deployment**: Implement [Security Guide](operations/security.md)
5. **Set Up Monitoring**: Configure [Monitoring & Alerting](operations/monitoring.md)
6. **Learn API Usage**: Explore [API Documentation](api/endpoints.md)

### Advanced Topics

- **Custom Component Development**: [Developer Guide](development/developer-guide.md)
- **Performance Optimization**: [Architecture Guide](architecture/components.md#performance-optimization)
- **Multi-Server Deployment**: [Deployment Patterns](architecture/deployment-patterns.md)
- **Integration Patterns**: [API Integration](api/integration-patterns.md)

---

**Welcome to the Cold Email Infrastructure!** This documentation is designed to help you successfully deploy, configure, and manage a complete cold email automation platform. Start with the [Installation Guide](setup/installation-guide.md) if you're new to the system, or use the navigation above to find specific information.

For questions, issues, or contributions, please see our [Contributing Guidelines](../CONTRIBUTING.md) or reach out to the community.