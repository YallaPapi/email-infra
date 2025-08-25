"""
Centralized configuration management for the email infrastructure project.
"""
import os
import yaml
from pathlib import Path
from typing import Dict, Any, Optional
from .paths import paths

class ConfigManager:
    """Centralized configuration management system."""
    
    def __init__(self, environment: str = None):
        """Initialize configuration manager.
        
        Args:
            environment: Target environment (development, staging, production)
        """
        self.environment = environment or os.getenv('EMAIL_INFRA_ENV', 'development')
        self.config_cache = {}
        self._load_configurations()
    
    def _load_configurations(self):
        """Load all configuration files."""
        # Load global configuration
        global_config_path = paths.config_root / "global-config.yaml"
        if global_config_path.exists():
            self.config_cache['global'] = self._load_yaml_file(global_config_path)
        
        # Load environment-specific configuration
        env_config_path = paths.config_root / "environments" / f"{self.environment}.yaml"
        if env_config_path.exists():
            self.config_cache['environment'] = self._load_yaml_file(env_config_path)
        
        # Load component-specific configurations
        self._load_component_configs()
    
    def _load_component_configs(self):
        """Load configuration files for each component."""
        components = ['dns', 'mailcow', 'monitoring', 'vps']
        
        for component in components:
            component_config_dir = getattr(paths, f"{component}_config")
            if component_config_dir.exists():
                config_files = list(component_config_dir.glob("*.yaml")) + list(component_config_dir.glob("*.yml"))
                self.config_cache[component] = {}
                
                for config_file in config_files:
                    config_name = config_file.stem
                    self.config_cache[component][config_name] = self._load_yaml_file(config_file)
    
    def _load_yaml_file(self, file_path: Path) -> Dict[str, Any]:
        """Load and parse a YAML configuration file."""
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()
                # Replace environment variables
                content = os.path.expandvars(content)
                return yaml.safe_load(content)
        except Exception as e:
            print(f"Error loading config file {file_path}: {e}")
            return {}
    
    def get_global_config(self) -> Dict[str, Any]:
        """Get global configuration."""
        return self.config_cache.get('global', {})
    
    def get_environment_config(self) -> Dict[str, Any]:
        """Get environment-specific configuration."""
        return self.config_cache.get('environment', {})
    
    def get_dns_config(self) -> Dict[str, Any]:
        """Get DNS component configuration."""
        return self.config_cache.get('dns', {})
    
    def get_mailcow_config(self) -> Dict[str, Any]:
        """Get Mailcow component configuration."""
        return self.config_cache.get('mailcow', {})
    
    def get_monitoring_config(self) -> Dict[str, Any]:
        """Get monitoring component configuration."""
        return self.config_cache.get('monitoring', {})
    
    def get_vps_config(self) -> Dict[str, Any]:
        """Get VPS component configuration."""
        return self.config_cache.get('vps', {})
    
    def get_config(self, component: str, config_name: Optional[str] = None) -> Dict[str, Any]:
        """Get configuration for a specific component.
        
        Args:
            component: Component name (dns, mailcow, monitoring, vps)
            config_name: Specific configuration file name (optional)
            
        Returns:
            Configuration dictionary
        """
        if component not in self.config_cache:
            return {}
        
        if config_name:
            return self.config_cache[component].get(config_name, {})
        else:
            return self.config_cache[component]
    
    def get_merged_config(self, component: str) -> Dict[str, Any]:
        """Get merged configuration with global and environment overrides.
        
        Args:
            component: Component name
            
        Returns:
            Merged configuration dictionary
        """
        merged_config = {}
        
        # Start with global config
        global_config = self.get_global_config()
        if 'components' in global_config and component in global_config['components']:
            merged_config.update(global_config['components'][component])
        
        # Apply environment config
        env_config = self.get_environment_config()
        if 'components' in env_config and component in env_config['components']:
            merged_config.update(env_config['components'][component])
        
        # Apply component-specific config
        component_config = self.get_config(component)
        merged_config.update(component_config)
        
        return merged_config
    
    def reload_config(self):
        """Reload all configuration files."""
        self.config_cache.clear()
        self._load_configurations()
    
    def validate_config(self) -> bool:
        """Validate all loaded configurations."""
        required_components = ['dns', 'mailcow', 'monitoring', 'vps']
        
        for component in required_components:
            if component not in self.config_cache:
                print(f"Warning: {component} configuration not found")
                return False
        
        return True

# Global config manager instance
config_manager = ConfigManager()