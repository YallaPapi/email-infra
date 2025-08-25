"""
Centralized path management for the email infrastructure project.
"""
import os
from pathlib import Path

class ProjectPaths:
    """Centralized path management for the email infrastructure project."""
    
    def __init__(self):
        # Project root is 4 levels up from this file
        self.project_root = Path(__file__).parent.parent.parent.parent
        self.src_root = self.project_root / "src" / "email-infrastructure"
        
    @property
    def config_root(self):
        """Global configuration directory."""
        return self.project_root / "config"
        
    @property
    def dns_root(self):
        """DNS component root directory."""
        return self.src_root / "dns"
        
    @property
    def dns_config(self):
        """DNS configuration directory."""
        return self.src_root / "dns" / "config"
        
    @property
    def dns_scripts(self):
        """DNS scripts directory."""
        return self.src_root / "dns" / "scripts"
        
    @property
    def mailcow_root(self):
        """Mailcow component root directory."""
        return self.src_root / "mailcow"
        
    @property
    def mailcow_config(self):
        """Mailcow configuration directory."""
        return self.src_root / "mailcow" / "config"
        
    @property
    def mailcow_automation(self):
        """Mailcow automation scripts directory."""
        return self.src_root / "mailcow" / "automation"
        
    @property
    def monitoring_root(self):
        """Monitoring component root directory."""
        return self.src_root / "monitoring"
        
    @property
    def monitoring_config(self):
        """Monitoring configuration directory."""
        return self.src_root / "monitoring" / "config"
        
    @property
    def monitoring_scripts(self):
        """Monitoring scripts directory."""
        return self.src_root / "monitoring" / "scripts"
        
    @property
    def vps_root(self):
        """VPS component root directory."""
        return self.src_root / "vps"
        
    @property
    def vps_config(self):
        """VPS configuration directory."""
        return self.src_root / "vps" / "config"
        
    @property
    def vps_scripts(self):
        """VPS scripts directory."""
        return self.src_root / "vps" / "scripts"
        
    @property
    def logs_dir(self):
        """Centralized logs directory."""
        return self.project_root / "data" / "logs"
        
    @property
    def backups_dir(self):
        """Backup storage directory."""
        return self.project_root / "data" / "backups"
        
    @property
    def cache_dir(self):
        """Cache storage directory."""
        return self.project_root / "data" / "cache"
        
    @property
    def database_dir(self):
        """Database storage directory."""
        return self.project_root / "data" / "databases"
        
    def ensure_directories(self):
        """Create all necessary directories if they don't exist."""
        dirs_to_create = [
            self.logs_dir,
            self.backups_dir,
            self.cache_dir,
            self.database_dir,
        ]
        
        for directory in dirs_to_create:
            directory.mkdir(parents=True, exist_ok=True)

# Global path instance
paths = ProjectPaths()