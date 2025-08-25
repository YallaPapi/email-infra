# Unified Configuration System Design

## Overview
This design document outlines the consolidated configuration system that will replace the scattered configuration files across claude-flow, claude-task-master, and email-infrastructure components.

## Current Configuration Problems
- **17+ separate YAML/JSON configuration files**
- **Inconsistent configuration patterns** across Python, TypeScript, and JavaScript
- **Duplicated settings** for logging, API endpoints, and database connections
- **Environment-specific configurations** scattered across different locations
- **No configuration validation** or schema enforcement

## Unified Configuration Architecture

### Directory Structure
```
/config/
├── schemas/                          # JSON Schema validation files
│   ├── base.schema.json             # Base configuration schema
│   ├── api.schema.json              # API client configurations
│   ├── database.schema.json         # Database connection settings
│   ├── dns.schema.json              # DNS and domain configurations
│   ├── email.schema.json            # Email service configurations
│   ├── logging.schema.json          # Logging framework settings
│   ├── monitoring.schema.json       # Monitoring and alerting
│   └── security.schema.json         # Security and authentication
├── environments/                     # Environment-specific configurations
│   ├── base.yaml                    # Base settings inherited by all environments
│   ├── development.yaml             # Development overrides
│   ├── staging.yaml                 # Staging environment settings
│   ├── production.yaml              # Production environment settings
│   └── testing.yaml                 # Testing environment settings
├── templates/                        # Configuration templates
│   ├── dns-records.yaml             # DNS record templates
│   ├── email-templates.yaml         # Email campaign templates
│   └── monitoring-alerts.yaml       # Alert notification templates
├── secrets/                          # Secret management (environment variables)
│   ├── .env.example                 # Example environment variables
│   └── secrets.schema.json          # Secret validation schema
└── config.py                        # Unified configuration loader
```

## Configuration Schema Design

### Base Configuration Schema (`schemas/base.schema.json`)
```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "application": {
      "type": "object",
      "properties": {
        "name": {"type": "string"},
        "version": {"type": "string"},
        "environment": {"type": "string", "enum": ["development", "staging", "production", "testing"]},
        "debug": {"type": "boolean", "default": false}
      },
      "required": ["name", "environment"]
    },
    "logging": {"$ref": "logging.schema.json"},
    "database": {"$ref": "database.schema.json"},
    "apis": {"$ref": "api.schema.json"},
    "email": {"$ref": "email.schema.json"},
    "dns": {"$ref": "dns.schema.json"},
    "monitoring": {"$ref": "monitoring.schema.json"},
    "security": {"$ref": "security.schema.json"}
  },
  "required": ["application", "logging"]
}
```

### API Configuration Schema (`schemas/api.schema.json`)
```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "cloudflare": {
      "type": "object",
      "properties": {
        "api_token": {"type": "string", "pattern": "^[A-Za-z0-9_-]{40}$"},
        "base_url": {"type": "string", "format": "uri", "default": "https://api.cloudflare.com/client/v4"},
        "timeout": {"type": "integer", "minimum": 1, "maximum": 300, "default": 30},
        "rate_limit": {
          "type": "object",
          "properties": {
            "requests_per_second": {"type": "integer", "minimum": 1, "default": 4},
            "burst_limit": {"type": "integer", "minimum": 1, "default": 10}
          }
        },
        "retry": {
          "type": "object",
          "properties": {
            "max_attempts": {"type": "integer", "minimum": 1, "default": 3},
            "backoff_factor": {"type": "number", "minimum": 1, "default": 2}
          }
        }
      },
      "required": ["api_token"]
    },
    "mailcow": {
      "type": "object",
      "properties": {
        "hostname": {"type": "string", "format": "hostname"},
        "api_key": {"type": "string"},
        "verify_ssl": {"type": "boolean", "default": true},
        "timeout": {"type": "integer", "minimum": 1, "default": 30}
      },
      "required": ["hostname", "api_key"]
    }
  }
}
```

### Logging Configuration Schema (`schemas/logging.schema.json`)
```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "level": {
      "type": "string",
      "enum": ["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"],
      "default": "INFO"
    },
    "format": {
      "type": "string",
      "default": "%(asctime)s - %(name)s - %(levelname)s - %(message)s"
    },
    "handlers": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "type": {"type": "string", "enum": ["file", "console", "syslog", "json"]},
          "filename": {"type": "string"},
          "max_size": {"type": "string", "pattern": "^\\d+[KMGT]?B?$", "default": "10MB"},
          "backup_count": {"type": "integer", "minimum": 1, "default": 5},
          "when": {"type": "string", "enum": ["midnight", "hourly", "daily"], "default": "midnight"}
        },
        "required": ["type"]
      },
      "minItems": 1
    },
    "loggers": {
      "type": "object",
      "patternProperties": {
        "^[a-zA-Z_][a-zA-Z0-9_.]*$": {
          "type": "object",
          "properties": {
            "level": {"type": "string", "enum": ["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"]},
            "handlers": {"type": "array", "items": {"type": "string"}},
            "propagate": {"type": "boolean", "default": true}
          }
        }
      }
    }
  },
  "required": ["level", "handlers"]
}
```

## Environment Configuration Examples

### Base Configuration (`environments/base.yaml`)
```yaml
application:
  name: "cold-email-infrastructure"
  version: "1.0.0"
  debug: false

logging:
  level: "INFO"
  format: "%(asctime)s - %(name)s - %(levelname)s - %(message)s"
  handlers:
    - type: "console"
    - type: "file"
      filename: "/var/log/email-infrastructure.log"
      max_size: "10MB"
      backup_count: 5
      when: "midnight"

database:
  default:
    type: "sqlite"
    path: "/var/lib/email-infrastructure/main.db"
    timeout: 30
    backup_enabled: true
    backup_interval: "daily"

apis:
  cloudflare:
    base_url: "https://api.cloudflare.com/client/v4"
    timeout: 30
    rate_limit:
      requests_per_second: 4
      burst_limit: 10
    retry:
      max_attempts: 3
      backoff_factor: 2

email:
  default_domain: "example.com"
  warmup:
    enabled: true
    initial_daily_limit: 50
    increase_rate: 10
    target_daily_limit: 1000
    duration_days: 30

dns:
  default_ttl: 300
  min_ttl: 120
  max_ttl: 86400
  propagation_timeout: 1800
  nameservers:
    - "8.8.8.8"
    - "8.8.4.4"
    - "1.1.1.1"
    - "1.0.0.1"

monitoring:
  enabled: true
  check_interval: 300
  alert_thresholds:
    delivery_rate_min: 95.0
    bounce_rate_max: 3.0
    spam_rate_max: 0.5
    reputation_score_min: 7.0
  notifications:
    email_alerts: false
    webhook_url: ""

security:
  api_key_rotation_days: 90
  audit_logging: true
  sensitive_data_masking: true
  allowed_ips: []
```

### Development Environment (`environments/development.yaml`)
```yaml
# Inherits from base.yaml with overrides
application:
  debug: true

logging:
  level: "DEBUG"
  handlers:
    - type: "console"

database:
  default:
    path: "/tmp/email-infrastructure-dev.db"

email:
  warmup:
    initial_daily_limit: 10
    target_daily_limit: 100
    duration_days: 7

monitoring:
  check_interval: 60
  alert_thresholds:
    delivery_rate_min: 80.0

security:
  audit_logging: false
```

### Production Environment (`environments/production.yaml`)
```yaml
# Inherits from base.yaml with overrides
logging:
  level: "WARNING"
  handlers:
    - type: "file"
      filename: "/var/log/email-infrastructure.log"
      max_size: "100MB"
      backup_count: 10
    - type: "json"
      filename: "/var/log/email-infrastructure.json"
    - type: "syslog"

database:
  default:
    path: "/var/lib/email-infrastructure/production.db"
    backup_enabled: true
    backup_interval: "hourly"

monitoring:
  check_interval: 60
  notifications:
    email_alerts: true
    webhook_url: "${SLACK_WEBHOOK_URL}"

security:
  api_key_rotation_days: 30
  allowed_ips:
    - "192.168.1.0/24"
    - "10.0.0.0/8"
```

## Unified Configuration Loader

### Configuration Manager (`config/config.py`)
```python
#!/usr/bin/env python3
"""
Unified Configuration Manager
Handles loading, validation, and management of all configuration
"""

import os
import yaml
import json
import logging
from typing import Dict, Any, Optional, List
from pathlib import Path
from dataclasses import dataclass, field
from jsonschema import validate, ValidationError
import re

@dataclass
class ConfigurationError(Exception):
    """Configuration loading or validation error"""
    message: str
    path: Optional[str] = None
    errors: List[str] = field(default_factory=list)

class UnifiedConfigManager:
    """Unified configuration manager for the entire infrastructure"""
    
    def __init__(self, config_dir: str = None, environment: str = None):
        self.config_dir = Path(config_dir or Path(__file__).parent)
        self.environment = environment or os.getenv('ENVIRONMENT', 'development')
        self.config_cache = {}
        self.schemas = {}
        self.logger = logging.getLogger(__name__)
        
        # Load schemas
        self._load_schemas()
        
    def _load_schemas(self):
        """Load all JSON schemas for validation"""
        schema_dir = self.config_dir / 'schemas'
        if not schema_dir.exists():
            raise ConfigurationError(f"Schema directory not found: {schema_dir}")
            
        for schema_file in schema_dir.glob('*.schema.json'):
            schema_name = schema_file.stem.replace('.schema', '')
            try:
                with open(schema_file, 'r') as f:
                    self.schemas[schema_name] = json.load(f)
            except Exception as e:
                raise ConfigurationError(f"Failed to load schema {schema_name}: {e}")
    
    def load_config(self, force_reload: bool = False) -> Dict[str, Any]:
        """Load complete configuration with environment inheritance"""
        if not force_reload and 'main' in self.config_cache:
            return self.config_cache['main']
            
        try:
            # Load base configuration
            base_config = self._load_yaml_file(self.config_dir / 'environments' / 'base.yaml')
            
            # Load environment-specific overrides
            env_file = self.config_dir / 'environments' / f'{self.environment}.yaml'
            if env_file.exists():
                env_config = self._load_yaml_file(env_file)
                config = self._deep_merge(base_config, env_config)
            else:
                config = base_config
                
            # Apply environment variable substitutions
            config = self._substitute_env_vars(config)
            
            # Validate against schema
            self._validate_config(config)
            
            # Cache the configuration
            self.config_cache['main'] = config
            
            self.logger.info(f"Configuration loaded successfully for environment: {self.environment}")
            return config
            
        except Exception as e:
            raise ConfigurationError(f"Failed to load configuration: {e}")
    
    def get_section(self, section: str) -> Dict[str, Any]:
        """Get a specific configuration section"""
        config = self.load_config()
        if section not in config:
            raise ConfigurationError(f"Configuration section '{section}' not found")
        return config[section]
    
    def get_value(self, path: str, default: Any = None) -> Any:
        """Get configuration value by dot notation path (e.g., 'database.default.timeout')"""
        config = self.load_config()
        keys = path.split('.')
        
        current = config
        for key in keys:
            if isinstance(current, dict) and key in current:
                current = current[key]
            else:
                return default
        
        return current
    
    def _load_yaml_file(self, file_path: Path) -> Dict[str, Any]:
        """Load and parse YAML file"""
        if not file_path.exists():
            raise ConfigurationError(f"Configuration file not found: {file_path}")
            
        try:
            with open(file_path, 'r') as f:
                content = yaml.safe_load(f) or {}
            return content
        except yaml.YAMLError as e:
            raise ConfigurationError(f"Invalid YAML in {file_path}: {e}")
    
    def _deep_merge(self, base: Dict, override: Dict) -> Dict:
        """Deep merge two dictionaries, with override taking precedence"""
        result = base.copy()
        
        for key, value in override.items():
            if (key in result and 
                isinstance(result[key], dict) and 
                isinstance(value, dict)):
                result[key] = self._deep_merge(result[key], value)
            else:
                result[key] = value
                
        return result
    
    def _substitute_env_vars(self, config: Any) -> Any:
        """Recursively substitute environment variables in configuration"""
        if isinstance(config, dict):
            return {k: self._substitute_env_vars(v) for k, v in config.items()}
        elif isinstance(config, list):
            return [self._substitute_env_vars(item) for item in config]
        elif isinstance(config, str):
            return self._expand_env_vars(config)
        else:
            return config
    
    def _expand_env_vars(self, value: str) -> str:
        """Expand environment variables in string values"""
        # Pattern: ${VAR_NAME} or ${VAR_NAME:default_value}
        pattern = re.compile(r'\$\{([^}:]+)(?::([^}]*))?\}')
        
        def replacer(match):
            var_name = match.group(1)
            default_value = match.group(2) if match.group(2) is not None else ''
            return os.getenv(var_name, default_value)
        
        return pattern.sub(replacer, value)
    
    def _validate_config(self, config: Dict[str, Any]):
        """Validate configuration against JSON schema"""
        if 'base' in self.schemas:
            try:
                validate(config, self.schemas['base'])
            except ValidationError as e:
                raise ConfigurationError(
                    f"Configuration validation failed: {e.message}",
                    path='.'.join(str(p) for p in e.absolute_path),
                    errors=[str(e)]
                )
    
    def reload_config(self) -> Dict[str, Any]:
        """Force reload configuration from files"""
        self.config_cache.clear()
        return self.load_config()
    
    def export_config(self, output_path: str = None, format: str = 'yaml'):
        """Export current configuration to file"""
        config = self.load_config()
        
        if not output_path:
            output_path = f'config_export_{self.environment}.{format}'
        
        try:
            with open(output_path, 'w') as f:
                if format.lower() == 'json':
                    json.dump(config, f, indent=2)
                else:
                    yaml.dump(config, f, default_flow_style=False, indent=2)
                    
            self.logger.info(f"Configuration exported to: {output_path}")
        except Exception as e:
            raise ConfigurationError(f"Failed to export configuration: {e}")

# Global configuration instance
_config_manager = None

def get_config_manager() -> UnifiedConfigManager:
    """Get the global configuration manager instance"""
    global _config_manager
    if _config_manager is None:
        _config_manager = UnifiedConfigManager()
    return _config_manager

def get_config() -> Dict[str, Any]:
    """Get the complete configuration dictionary"""
    return get_config_manager().load_config()

def get_section(section: str) -> Dict[str, Any]:
    """Get a specific configuration section"""
    return get_config_manager().get_section(section)

def get_value(path: str, default: Any = None) -> Any:
    """Get configuration value by dot notation path"""
    return get_config_manager().get_value(path, default)

# Usage examples and CLI interface
if __name__ == '__main__':
    import argparse
    
    parser = argparse.ArgumentParser(description='Unified Configuration Manager')
    parser.add_argument('--environment', '-e', default='development', 
                       help='Environment to load (development, staging, production)')
    parser.add_argument('--validate', action='store_true', 
                       help='Validate configuration and exit')
    parser.add_argument('--export', help='Export configuration to file')
    parser.add_argument('--format', choices=['yaml', 'json'], default='yaml', 
                       help='Export format')
    parser.add_argument('--get', help='Get specific configuration value by path')
    parser.add_argument('--section', help='Get specific configuration section')
    
    args = parser.parse_args()
    
    try:
        config_manager = UnifiedConfigManager(environment=args.environment)
        
        if args.validate:
            config = config_manager.load_config()
            print(f"✓ Configuration valid for environment: {args.environment}")
            
        elif args.export:
            config_manager.export_config(args.export, args.format)
            
        elif args.get:
            value = config_manager.get_value(args.get)
            if args.format == 'json':
                print(json.dumps(value, indent=2))
            else:
                print(yaml.dump(value, default_flow_style=False))
                
        elif args.section:
            section = config_manager.get_section(args.section)
            if args.format == 'json':
                print(json.dumps(section, indent=2))
            else:
                print(yaml.dump(section, default_flow_style=False))
                
        else:
            config = config_manager.load_config()
            print(f"Configuration loaded for environment: {args.environment}")
            print(f"Available sections: {list(config.keys())}")
            
    except ConfigurationError as e:
        print(f"❌ Configuration Error: {e.message}")
        if e.path:
            print(f"   Path: {e.path}")
        for error in e.errors:
            print(f"   - {error}")
        exit(1)
    except Exception as e:
        print(f"❌ Unexpected error: {e}")
        exit(1)
```

## Migration Strategy

### Phase 1: Setup Infrastructure
1. Create the `/config/` directory structure
2. Implement the `UnifiedConfigManager` class
3. Create base JSON schemas for validation
4. Set up the base configuration file

### Phase 2: Component Migration
1. **DNS Manager**: Migrate from `cloudflare-config.yaml` to unified config
2. **Mailcow API**: Integrate with unified configuration system
3. **Monitoring Components**: Consolidate all monitoring configurations
4. **VPS Manager**: Migrate network and firewall configurations

### Phase 3: Environment Setup
1. Create environment-specific configuration files
2. Set up secret management with environment variables
3. Validate all configurations against schemas
4. Test configuration inheritance and overrides

### Phase 4: Integration Testing
1. Update all Python modules to use the unified config manager
2. Test configuration loading and validation
3. Verify environment-specific behavior
4. Performance testing with configuration caching

## Benefits of Unified Configuration

### For Developers:
- **Single source of truth** for all configuration
- **Type-safe validation** with JSON schemas
- **Environment inheritance** reduces duplication
- **Hot-reload capabilities** for development

### For Operations:
- **Consistent configuration** across all components
- **Environment-specific deployments** made simple
- **Secret management** with environment variables
- **Configuration validation** prevents deployment errors

### For Maintenance:
- **Centralized configuration** easier to maintain
- **Schema validation** catches errors early
- **Version control** for configuration changes
- **Documentation generation** from schemas

This unified configuration system will eliminate the duplication found across the 228+ configuration files while providing a robust, scalable, and maintainable solution for the entire cold email infrastructure.