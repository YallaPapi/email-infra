#!/usr/bin/env python3
"""
VPS Manager for Cold Email Infrastructure

This module provides comprehensive VPS management functionality including:
- Network interface and IP management
- VPS status monitoring 
- IP rotation for email sending
- Health monitoring and alerting

Author: Cold Email Infrastructure Setup Agent
Version: 1.0.0
"""

import os
import sys
import json
import yaml
import time
import socket
import logging
import subprocess
import ipaddress
import psutil
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Tuple, Any
from pathlib import Path


class VPSManager:
    """Main VPS management class for cold email infrastructure"""
    
    def __init__(self, config_path: Optional[str] = None):
        """Initialize VPS Manager
        
        Args:
            config_path: Optional path to configuration directory
        """
        # Set up paths
        self.script_dir = Path(__file__).parent
        self.base_dir = self.script_dir.parent if self.script_dir.name == 'scripts' else self.script_dir
        self.config_dir = self.base_dir / 'config'
        self.log_dir = self.base_dir / 'logs'
        self.monitoring_dir = self.base_dir / 'monitoring'
        
        # Override config directory if provided
        if config_path:
            self.config_dir = Path(config_path)
        
        # Create directories if they don't exist
        self.log_dir.mkdir(parents=True, exist_ok=True)
        self.monitoring_dir.mkdir(parents=True, exist_ok=True)
        
        # Set up logging
        self.setup_logging()
        
        # Load configurations
        self.network_config = self.load_network_config()
        self.firewall_config = self.load_firewall_config()
        
        self.logger.info("VPS Manager initialized")
    
    def setup_logging(self):
        """Set up logging configuration"""
        log_file = self.log_dir / f'vps-manager-{datetime.now().strftime("%Y%m%d")}.log'
        
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler(log_file),
                logging.StreamHandler(sys.stdout)
            ]
        )
        
        self.logger = logging.getLogger('VPSManager')
    
    def load_network_config(self) -> Dict[str, Any]:
        """Load network configuration from YAML file"""
        config_file = self.config_dir / 'network-config.yaml'
        
        if not config_file.exists():
            self.logger.warning(f"Network config file not found: {config_file}")
            return {}
        
        try:
            with open(config_file, 'r') as f:
                config = yaml.safe_load(f)
            self.logger.info("Network configuration loaded successfully")
            return config
        except Exception as e:
            self.logger.error(f"Failed to load network configuration: {e}")
            return {}
    
    def load_firewall_config(self) -> Dict[str, Any]:
        """Load firewall configuration from JSON file"""
        config_file = self.config_dir / 'firewall-rules.json'
        
        if not config_file.exists():
            self.logger.warning(f"Firewall config file not found: {config_file}")
            return {}
        
        try:
            with open(config_file, 'r') as f:
                config = json.load(f)
            self.logger.info("Firewall configuration loaded successfully")
            return config
        except Exception as e:
            self.logger.error(f"Failed to load firewall configuration: {e}")
            return {}
    
    def get_network_interfaces(self) -> Dict[str, Dict[str, Any]]:
        """Get all network interfaces and their details
        
        Returns:
            Dictionary mapping interface names to their details
        """
        interfaces = {}
        
        try:
            # Get interface statistics using psutil
            net_if_stats = psutil.net_if_stats()
            net_if_addrs = psutil.net_if_addrs()
            
            for interface_name, stats in net_if_stats.items():
                if interface_name == 'lo':  # Skip loopback
                    continue
                
                interface_info = {
                    'name': interface_name,
                    'is_up': stats.isup,
                    'mtu': stats.mtu,
                    'speed': getattr(stats, 'speed', 0),
                    'addresses': []
                }
                
                # Get IP addresses for this interface
                if interface_name in net_if_addrs:
                    for addr in net_if_addrs[interface_name]:
                        if addr.family == socket.AF_INET:  # IPv4
                            interface_info['addresses'].append({
                                'ip': addr.address,
                                'netmask': addr.netmask,
                                'broadcast': addr.broadcast,
                                'family': 'IPv4'
                            })
                        elif addr.family == socket.AF_INET6:  # IPv6
                            interface_info['addresses'].append({
                                'ip': addr.address,
                                'netmask': addr.netmask,
                                'broadcast': addr.broadcast,
                                'family': 'IPv6'
                            })
                
                interfaces[interface_name] = interface_info
            
            self.logger.info(f"Found {len(interfaces)} network interfaces")
            return interfaces
        
        except Exception as e:
            self.logger.error(f"Failed to get network interfaces: {e}")
            return {}
    
    def get_available_ips(self) -> List[str]:
        """Get list of all available IPv4 addresses on the server
        
        Returns:
            List of IPv4 addresses
        """
        ip_addresses = []
        
        try:
            interfaces = self.get_network_interfaces()
            
            for interface_name, interface_info in interfaces.items():
                for addr_info in interface_info['addresses']:
                    if addr_info['family'] == 'IPv4':
                        ip_addresses.append(addr_info['ip'])
            
            # Filter out private/local addresses if needed
            public_ips = []
            private_ips = []
            
            for ip in ip_addresses:
                try:
                    ip_obj = ipaddress.ip_address(ip)
                    if ip_obj.is_private:
                        private_ips.append(ip)
                    else:
                        public_ips.append(ip)
                except ValueError:
                    continue
            
            self.logger.info(f"Found {len(public_ips)} public IPs and {len(private_ips)} private IPs")
            
            return public_ips + private_ips
        
        except Exception as e:
            self.logger.error(f"Failed to get available IPs: {e}")
            return []
    
    def get_primary_interface(self) -> Optional[str]:
        """Get the primary network interface (with default route)
        
        Returns:
            Primary interface name or None if not found
        """
        try:
            # Try to get primary interface from network config first
            if self.network_config.get('primary_interface'):
                return self.network_config['primary_interface']
            
            # Get primary interface from system
            result = subprocess.run(
                ['ip', 'route', 'show', 'default'],
                capture_output=True,
                text=True,
                check=True
            )
            
            for line in result.stdout.strip().split('\n'):
                if 'default via' in line:
                    parts = line.split()
                    if 'dev' in parts:
                        dev_index = parts.index('dev')
                        if dev_index + 1 < len(parts):
                            interface_name = parts[dev_index + 1]
                            self.logger.info(f"Primary interface detected: {interface_name}")
                            return interface_name
            
            self.logger.warning("Could not detect primary interface")
            return None
        
        except Exception as e:
            self.logger.error(f"Failed to get primary interface: {e}")
            return None
    
    def add_ip_alias(self, ip: str, interface: Optional[str] = None, netmask: str = '24') -> bool:
        """Add an IP alias to a network interface
        
        Args:
            ip: IP address to add
            interface: Interface name (uses primary if None)
            netmask: Network mask (default: 24)
        
        Returns:
            True if successful, False otherwise
        """
        if not interface:
            interface = self.get_primary_interface()
            if not interface:
                self.logger.error("Cannot determine primary interface")
                return False
        
        try:
            # Validate IP address
            ipaddress.ip_address(ip)
            
            # Find next available alias number
            alias_num = 1
            interfaces = self.get_network_interfaces()
            
            while f"{interface}:{alias_num}" in interfaces:
                alias_num += 1
            
            alias_interface = f"{interface}:{alias_num}"
            
            # Add IP alias using ip command
            cmd = [
                'ip', 'addr', 'add',
                f'{ip}/{netmask}',
                'dev', interface,
                'label', alias_interface
            ]
            
            result = subprocess.run(cmd, capture_output=True, text=True)
            
            if result.returncode == 0:
                self.logger.info(f"Successfully added IP alias {ip} to {alias_interface}")
                return True
            else:
                self.logger.error(f"Failed to add IP alias: {result.stderr}")
                return False
        
        except Exception as e:
            self.logger.error(f"Failed to add IP alias {ip}: {e}")
            return False
    
    def remove_ip_alias(self, ip: str, interface: Optional[str] = None) -> bool:
        """Remove an IP alias from a network interface
        
        Args:
            ip: IP address to remove
            interface: Interface name (searches all if None)
        
        Returns:
            True if successful, False otherwise
        """
        try:
            if interface:
                # Remove from specific interface
                cmd = ['ip', 'addr', 'del', ip, 'dev', interface]
            else:
                # Find interface with this IP
                interfaces = self.get_network_interfaces()
                target_interface = None
                
                for iface_name, iface_info in interfaces.items():
                    for addr_info in iface_info['addresses']:
                        if addr_info['ip'] == ip:
                            target_interface = iface_name
                            break
                    if target_interface:
                        break
                
                if not target_interface:
                    self.logger.error(f"IP {ip} not found on any interface")
                    return False
                
                cmd = ['ip', 'addr', 'del', ip, 'dev', target_interface]
            
            result = subprocess.run(cmd, capture_output=True, text=True)
            
            if result.returncode == 0:
                self.logger.info(f"Successfully removed IP {ip}")
                return True
            else:
                self.logger.error(f"Failed to remove IP: {result.stderr}")
                return False
        
        except Exception as e:
            self.logger.error(f"Failed to remove IP alias {ip}: {e}")
            return False
    
    def get_vps_status(self) -> Dict[str, Any]:
        """Get comprehensive VPS status information
        
        Returns:
            Dictionary containing VPS status details
        """
        try:
            status = {
                'timestamp': datetime.now().isoformat(),
                'hostname': socket.gethostname(),
                'system': self.get_system_status(),
                'network': self.get_network_status(),
                'disk': self.get_disk_status(),
                'services': self.get_service_status(),
                'load': self.get_load_status()
            }
            
            return status
        
        except Exception as e:
            self.logger.error(f"Failed to get VPS status: {e}")
            return {'error': str(e)}
    
    def get_system_status(self) -> Dict[str, Any]:
        """Get system resource status"""
        try:
            cpu_percent = psutil.cpu_percent(interval=1)
            memory = psutil.virtual_memory()
            boot_time = datetime.fromtimestamp(psutil.boot_time())
            
            return {
                'cpu_usage_percent': cpu_percent,
                'cpu_count': psutil.cpu_count(),
                'memory_total_gb': round(memory.total / (1024**3), 2),
                'memory_used_gb': round(memory.used / (1024**3), 2),
                'memory_percent': memory.percent,
                'uptime': str(datetime.now() - boot_time),
                'boot_time': boot_time.isoformat()
            }
        except Exception as e:
            self.logger.error(f"Failed to get system status: {e}")
            return {}
    
    def get_network_status(self) -> Dict[str, Any]:
        """Get network status information"""
        try:
            interfaces = self.get_network_interfaces()
            available_ips = self.get_available_ips()
            
            # Test internet connectivity
            connectivity = self.test_connectivity()
            
            return {
                'interfaces_count': len(interfaces),
                'available_ips': available_ips,
                'ip_count': len(available_ips),
                'connectivity': connectivity,
                'primary_interface': self.get_primary_interface()
            }
        except Exception as e:
            self.logger.error(f"Failed to get network status: {e}")
            return {}
    
    def get_disk_status(self) -> Dict[str, Any]:
        """Get disk usage status"""
        try:
            disk_usage = psutil.disk_usage('/')
            
            return {
                'total_gb': round(disk_usage.total / (1024**3), 2),
                'used_gb': round(disk_usage.used / (1024**3), 2),
                'free_gb': round(disk_usage.free / (1024**3), 2),
                'percent': round((disk_usage.used / disk_usage.total) * 100, 2)
            }
        except Exception as e:
            self.logger.error(f"Failed to get disk status: {e}")
            return {}
    
    def get_service_status(self) -> Dict[str, Any]:
        """Get status of important services"""
        services = ['docker', 'ufw', 'fail2ban', 'ssh']
        service_status = {}
        
        for service in services:
            try:
                result = subprocess.run(
                    ['systemctl', 'is-active', service],
                    capture_output=True,
                    text=True
                )
                service_status[service] = result.stdout.strip() == 'active'
            except Exception:
                service_status[service] = False
        
        return service_status
    
    def get_load_status(self) -> Dict[str, Any]:
        """Get system load averages"""
        try:
            load_avg = psutil.getloadavg()
            
            return {
                'load_1min': load_avg[0],
                'load_5min': load_avg[1],
                'load_15min': load_avg[2],
                'cpu_count': psutil.cpu_count()
            }
        except Exception as e:
            self.logger.error(f"Failed to get load status: {e}")
            return {}
    
    def test_connectivity(self) -> Dict[str, bool]:
        """Test network connectivity to various endpoints"""
        connectivity = {
            'internet': False,
            'dns': False,
            'smtp_port': False
        }
        
        try:
            # Test internet connectivity
            import urllib.request
            urllib.request.urlopen('http://www.google.com', timeout=5)
            connectivity['internet'] = True
        except Exception:
            pass
        
        try:
            # Test DNS resolution
            socket.gethostbyname('google.com')
            connectivity['dns'] = True
        except Exception:
            pass
        
        try:
            # Test SMTP port (25) connectivity
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(5)
            result = sock.connect_ex(('smtp.gmail.com', 25))
            connectivity['smtp_port'] = result == 0
            sock.close()
        except Exception:
            pass
        
        return connectivity
    
    def rotate_ip_for_sending(self, exclude_ips: Optional[List[str]] = None) -> Optional[str]:
        """Select an IP address for email sending with rotation
        
        Args:
            exclude_ips: List of IPs to exclude from selection
        
        Returns:
            Selected IP address or None if no IPs available
        """
        available_ips = self.get_available_ips()
        
        if exclude_ips:
            available_ips = [ip for ip in available_ips if ip not in exclude_ips]
        
        if not available_ips:
            self.logger.warning("No available IPs for sending")
            return None
        
        # Simple round-robin selection
        # In a production environment, you might want more sophisticated logic
        import random
        selected_ip = random.choice(available_ips)
        
        self.logger.info(f"Selected IP for sending: {selected_ip}")
        return selected_ip
    
    def monitor_ip_health(self, ip: str) -> Dict[str, Any]:
        """Monitor the health of a specific IP address
        
        Args:
            ip: IP address to monitor
        
        Returns:
            Dictionary containing health status
        """
        health_status = {
            'ip': ip,
            'timestamp': datetime.now().isoformat(),
            'reachable': False,
            'response_time_ms': None,
            'blacklisted': None,
            'reverse_dns': None
        }
        
        try:
            # Test if IP is reachable
            import ping3
            response_time = ping3.ping(ip, timeout=5)
            if response_time:
                health_status['reachable'] = True
                health_status['response_time_ms'] = round(response_time * 1000, 2)
        except Exception:
            pass
        
        try:
            # Check reverse DNS
            reverse_dns = socket.gethostbyaddr(ip)
            health_status['reverse_dns'] = reverse_dns[0]
        except Exception:
            health_status['reverse_dns'] = None
        
        # Note: Blacklist checking would require external APIs
        # This is left as a placeholder for implementation
        
        return health_status
    
    def save_status_to_file(self, status: Dict[str, Any], filename: str = None) -> bool:
        """Save VPS status to JSON file
        
        Args:
            status: Status dictionary to save
            filename: Optional filename (default: vps-status.json)
        
        Returns:
            True if successful, False otherwise
        """
        try:
            if not filename:
                filename = 'vps-status.json'
            
            status_file = self.monitoring_dir / filename
            
            with open(status_file, 'w') as f:
                json.dump(status, f, indent=2)
            
            self.logger.info(f"Status saved to {status_file}")
            return True
        
        except Exception as e:
            self.logger.error(f"Failed to save status: {e}")
            return False
    
    def load_status_from_file(self, filename: str = None) -> Optional[Dict[str, Any]]:
        """Load VPS status from JSON file
        
        Args:
            filename: Optional filename (default: vps-status.json)
        
        Returns:
            Status dictionary or None if failed
        """
        try:
            if not filename:
                filename = 'vps-status.json'
            
            status_file = self.monitoring_dir / filename
            
            if not status_file.exists():
                return None
            
            with open(status_file, 'r') as f:
                status = json.load(f)
            
            return status
        
        except Exception as e:
            self.logger.error(f"Failed to load status: {e}")
            return None


def main():
    """Main function for command-line interface"""
    import argparse
    
    parser = argparse.ArgumentParser(description='VPS Manager for Cold Email Infrastructure')
    parser.add_argument('--config', '-c', help='Configuration directory path')
    
    subparsers = parser.add_subparsers(dest='command', help='Available commands')
    
    # Status command
    status_parser = subparsers.add_parser('status', help='Get VPS status')
    status_parser.add_argument('--json', action='store_true', help='Output in JSON format')
    status_parser.add_argument('--save', action='store_true', help='Save status to file')
    
    # List IPs command
    ips_parser = subparsers.add_parser('ips', help='List available IP addresses')
    ips_parser.add_argument('--public-only', action='store_true', help='Show only public IPs')
    
    # Interface command
    interfaces_parser = subparsers.add_parser('interfaces', help='Show network interfaces')
    
    # Add IP command
    add_ip_parser = subparsers.add_parser('add-ip', help='Add IP alias')
    add_ip_parser.add_argument('ip', help='IP address to add')
    add_ip_parser.add_argument('--interface', help='Interface name')
    add_ip_parser.add_argument('--netmask', default='24', help='Network mask (default: 24)')
    
    # Remove IP command
    remove_ip_parser = subparsers.add_parser('remove-ip', help='Remove IP alias')
    remove_ip_parser.add_argument('ip', help='IP address to remove')
    remove_ip_parser.add_argument('--interface', help='Interface name')
    
    # Rotate IP command
    rotate_parser = subparsers.add_parser('rotate-ip', help='Get IP for sending rotation')
    rotate_parser.add_argument('--exclude', nargs='*', help='IPs to exclude')
    
    # Monitor command
    monitor_parser = subparsers.add_parser('monitor', help='Monitor IP health')
    monitor_parser.add_argument('ip', help='IP address to monitor')
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        return
    
    # Initialize VPS Manager
    vps_manager = VPSManager(config_path=args.config)
    
    # Execute commands
    if args.command == 'status':
        status = vps_manager.get_vps_status()
        
        if args.save:
            vps_manager.save_status_to_file(status)
        
        if args.json:
            # Output JSON format
            import sys
            sys.stdout.write(json.dumps(status, indent=2))
        else:
            # Log status instead of printing
            logger.info("VPS status retrieved successfully")
            logger.info(f"Hostname: {status.get('hostname', 'Unknown')}")
            logger.info(f"Timestamp: {status.get('timestamp', 'Unknown')}")
    
    elif args.command == 'ips':
        ips = vps_manager.get_available_ips()
        
        if args.public_only:
            public_ips = []
            for ip in ips:
                try:
                    ip_obj = ipaddress.ip_address(ip)
                    if not ip_obj.is_private:
                        public_ips.append(ip)
                except ValueError:
                    continue
            ips = public_ips
        
        logger.info(f"Found {len(ips)} available IP addresses")
        for ip in ips:
            logger.info(f"IP: {ip}")
    
    elif args.command == 'interfaces':
        interfaces = vps_manager.get_network_interfaces()
        
        logger.info(f"Found {len(interfaces)} network interfaces")
        for name, info in interfaces.items():
            status = 'UP' if info['is_up'] else 'DOWN'
            logger.info(f"Interface {name}: {status}, MTU: {info['mtu']}")
            for addr in info['addresses']:
                logger.info(f"  Address: {addr['ip']}/{addr['netmask']} ({addr['family']})")
    
    elif args.command == 'add-ip':
        success = vps_manager.add_ip_alias(args.ip, args.interface, args.netmask)
        if success:
            logger.info(f"Successfully added IP {args.ip}")
        else:
            logger.error(f"Failed to add IP {args.ip}")
            sys.exit(1)
    
    elif args.command == 'remove-ip':
        success = vps_manager.remove_ip_alias(args.ip, args.interface)
        if success:
            logger.info(f"Successfully removed IP {args.ip}")
        else:
            logger.error(f"Failed to remove IP {args.ip}")
            sys.exit(1)
    
    elif args.command == 'rotate-ip':
        selected_ip = vps_manager.rotate_ip_for_sending(exclude_ips=args.exclude)
        if selected_ip:
            print(f"Selected IP for sending: {selected_ip}")
        else:
            print("No available IPs for sending")
            sys.exit(1)
    
    elif args.command == 'monitor':
        health = vps_manager.monitor_ip_health(args.ip)
        print(f"Health status for {args.ip}:")
        print(f"  Reachable: {'✓' if health['reachable'] else '✗'}")
        if health['response_time_ms']:
            print(f"  Response Time: {health['response_time_ms']:.2f}ms")
        if health['reverse_dns']:
            print(f"  Reverse DNS: {health['reverse_dns']}")


if __name__ == '__main__':
    main()