#!/usr/bin/env python3
"""
Health Check and Monitoring Module for Cold Email Dashboard
Provides comprehensive health checks and system monitoring capabilities
"""

import os
import sys
import time
import json
import psutil
import requests
import subprocess
from datetime import datetime, timedelta
from typing import Dict, List, Any, Optional
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class HealthChecker:
    """Comprehensive health check system"""
    
    def __init__(self):
        self.start_time = time.time()
        self.checks = {}
        
    def check_system_resources(self) -> Dict[str, Any]:
        """Check system resource usage"""
        try:
            # CPU usage
            cpu_percent = psutil.cpu_percent(interval=1)
            
            # Memory usage
            memory = psutil.virtual_memory()
            
            # Disk usage
            disk = psutil.disk_usage('/')
            
            # Network stats
            network = psutil.net_io_counters()
            
            # System load
            load_avg = psutil.getloadavg() if hasattr(psutil, 'getloadavg') else (0, 0, 0)
            
            # Process count
            process_count = len(psutil.pids())
            
            # Determine health status
            status = 'healthy'
            issues = []
            
            if cpu_percent > 90:
                status = 'critical'
                issues.append(f'High CPU usage: {cpu_percent:.1f}%')
            elif cpu_percent > 75:
                status = 'warning'
                issues.append(f'Elevated CPU usage: {cpu_percent:.1f}%')
            
            if memory.percent > 95:
                status = 'critical'
                issues.append(f'Critical memory usage: {memory.percent:.1f}%')
            elif memory.percent > 85:
                if status != 'critical':
                    status = 'warning'
                issues.append(f'High memory usage: {memory.percent:.1f}%')
            
            disk_percent = (disk.used / disk.total) * 100
            if disk_percent > 95:
                status = 'critical'
                issues.append(f'Critical disk usage: {disk_percent:.1f}%')
            elif disk_percent > 85:
                if status != 'critical':
                    status = 'warning'
                issues.append(f'High disk usage: {disk_percent:.1f}%')
            
            return {
                'status': status,
                'timestamp': datetime.now().isoformat(),
                'metrics': {
                    'cpu_percent': round(cpu_percent, 1),
                    'memory_percent': round(memory.percent, 1),
                    'memory_available_gb': round(memory.available / (1024**3), 2),
                    'memory_total_gb': round(memory.total / (1024**3), 2),
                    'disk_percent': round(disk_percent, 1),
                    'disk_free_gb': round(disk.free / (1024**3), 2),
                    'disk_total_gb': round(disk.total / (1024**3), 2),
                    'network_bytes_sent': network.bytes_sent,
                    'network_bytes_recv': network.bytes_recv,
                    'load_average': load_avg,
                    'process_count': process_count
                },
                'issues': issues
            }
            
        except Exception as e:
            logger.error(f"System resource check failed: {e}")
            return {
                'status': 'error',
                'timestamp': datetime.now().isoformat(),
                'error': str(e)
            }
    
    def check_flask_app(self, port: int = 5000) -> Dict[str, Any]:
        """Check Flask application health"""
        try:
            # Check if Flask is listening on the port
            for conn in psutil.net_connections(kind='inet'):
                if conn.laddr.port == port and conn.status == 'LISTEN':
                    # Try to make HTTP request
                    try:
                        response = requests.get(f'http://localhost:{port}/api/health', timeout=5)
                        if response.status_code == 200:
                            return {
                                'status': 'healthy',
                                'timestamp': datetime.now().isoformat(),
                                'response_time_ms': round(response.elapsed.total_seconds() * 1000, 2),
                                'port': port
                            }
                        else:
                            return {
                                'status': 'degraded',
                                'timestamp': datetime.now().isoformat(),
                                'error': f'HTTP {response.status_code}',
                                'port': port
                            }
                    except requests.RequestException as e:
                        return {
                            'status': 'degraded',
                            'timestamp': datetime.now().isoformat(),
                            'error': f'Request failed: {e}',
                            'port': port
                        }
            
            return {
                'status': 'critical',
                'timestamp': datetime.now().isoformat(),
                'error': f'Flask not listening on port {port}',
                'port': port
            }
            
        except Exception as e:
            logger.error(f"Flask app check failed: {e}")
            return {
                'status': 'error',
                'timestamp': datetime.now().isoformat(),
                'error': str(e)
            }
    
    def check_external_dependencies(self) -> Dict[str, Any]:
        """Check external service dependencies"""
        results = {}
        
        # Check Cloudflare API
        try:
            api_token = os.environ.get('CLOUDFLARE_API_TOKEN')
            if api_token:
                headers = {'Authorization': f'Bearer {api_token}'}
                response = requests.get('https://api.cloudflare.com/client/v4/user', headers=headers, timeout=10)
                if response.status_code == 200:
                    results['cloudflare'] = {'status': 'healthy', 'response_time_ms': round(response.elapsed.total_seconds() * 1000, 2)}
                else:
                    results['cloudflare'] = {'status': 'degraded', 'error': f'HTTP {response.status_code}'}
            else:
                results['cloudflare'] = {'status': 'not_configured', 'message': 'API token not set'}
        except Exception as e:
            results['cloudflare'] = {'status': 'error', 'error': str(e)}
        
        # Check Mailcow API
        try:
            mailcow_host = os.environ.get('MAILCOW_HOSTNAME')
            api_key = os.environ.get('MAILCOW_API_KEY')
            if mailcow_host and api_key:
                url = f'https://{mailcow_host}/api/v1/get/status/containers'
                headers = {'X-API-Key': api_key}
                response = requests.get(url, headers=headers, verify=False, timeout=10)
                if response.status_code == 200:
                    results['mailcow'] = {'status': 'healthy', 'response_time_ms': round(response.elapsed.total_seconds() * 1000, 2)}
                else:
                    results['mailcow'] = {'status': 'degraded', 'error': f'HTTP {response.status_code}'}
            else:
                results['mailcow'] = {'status': 'not_configured', 'message': 'Host or API key not set'}
        except Exception as e:
            results['mailcow'] = {'status': 'error', 'error': str(e)}
        
        # Check internet connectivity
        try:
            response = requests.get('https://8.8.8.8', timeout=5)
            results['internet'] = {'status': 'healthy', 'response_time_ms': round(response.elapsed.total_seconds() * 1000, 2)}
        except Exception as e:
            results['internet'] = {'status': 'error', 'error': str(e)}
        
        # Overall status
        statuses = [dep.get('status') for dep in results.values()]
        if 'error' in statuses or 'critical' in statuses:
            overall_status = 'critical'
        elif 'degraded' in statuses:
            overall_status = 'degraded'
        else:
            overall_status = 'healthy'
        
        return {
            'status': overall_status,
            'timestamp': datetime.now().isoformat(),
            'dependencies': results
        }
    
    def check_file_permissions(self) -> Dict[str, Any]:
        """Check critical file and directory permissions"""
        try:
            checks = []
            
            # Check log directory
            log_dir = '/var/log/cold-email-dashboard'
            if os.path.exists(log_dir):
                stat = os.stat(log_dir)
                checks.append({
                    'path': log_dir,
                    'exists': True,
                    'writable': os.access(log_dir, os.W_OK),
                    'permissions': oct(stat.st_mode)[-3:]
                })
            else:
                checks.append({
                    'path': log_dir,
                    'exists': False,
                    'issue': 'Log directory does not exist'
                })
            
            # Check config directory
            config_dir = '/etc/cold-email-dashboard'
            if os.path.exists(config_dir):
                stat = os.stat(config_dir)
                checks.append({
                    'path': config_dir,
                    'exists': True,
                    'readable': os.access(config_dir, os.R_OK),
                    'permissions': oct(stat.st_mode)[-3:]
                })
            else:
                checks.append({
                    'path': config_dir,
                    'exists': False,
                    'issue': 'Config directory does not exist'
                })
            
            # Check for any issues
            issues = [check for check in checks if 'issue' in check or not check.get('writable', True) or not check.get('readable', True)]
            
            return {
                'status': 'critical' if issues else 'healthy',
                'timestamp': datetime.now().isoformat(),
                'checks': checks,
                'issues': issues
            }
            
        except Exception as e:
            logger.error(f"File permissions check failed: {e}")
            return {
                'status': 'error',
                'timestamp': datetime.now().isoformat(),
                'error': str(e)
            }
    
    def check_process_status(self) -> Dict[str, Any]:
        """Check for required processes"""
        try:
            processes = {}
            
            # Check for Python processes
            python_processes = []
            for proc in psutil.process_iter(['pid', 'name', 'cmdline', 'status']):
                try:
                    if 'python' in proc.info['name'].lower() and proc.info['cmdline']:
                        if any('app.py' in cmd for cmd in proc.info['cmdline']):
                            python_processes.append({
                                'pid': proc.info['pid'],
                                'status': proc.info['status'],
                                'cmdline': ' '.join(proc.info['cmdline'])
                            })
                except (psutil.NoSuchProcess, psutil.AccessDenied):
                    continue
            
            processes['dashboard_app'] = {
                'count': len(python_processes),
                'processes': python_processes,
                'status': 'healthy' if python_processes else 'critical'
            }
            
            # Check for nginx if it should be running
            nginx_processes = []
            for proc in psutil.process_iter(['pid', 'name', 'status']):
                try:
                    if 'nginx' in proc.info['name'].lower():
                        nginx_processes.append({
                            'pid': proc.info['pid'],
                            'status': proc.info['status']
                        })
                except (psutil.NoSuchProcess, psutil.AccessDenied):
                    continue
            
            processes['nginx'] = {
                'count': len(nginx_processes),
                'processes': nginx_processes,
                'status': 'healthy' if nginx_processes else 'not_running'
            }
            
            # Overall status
            overall_status = 'healthy'
            for proc_name, proc_info in processes.items():
                if proc_info['status'] == 'critical':
                    overall_status = 'critical'
                    break
                elif proc_info['status'] == 'degraded' and overall_status != 'critical':
                    overall_status = 'degraded'
            
            return {
                'status': overall_status,
                'timestamp': datetime.now().isoformat(),
                'processes': processes
            }
            
        except Exception as e:
            logger.error(f"Process status check failed: {e}")
            return {
                'status': 'error',
                'timestamp': datetime.now().isoformat(),
                'error': str(e)
            }
    
    def get_comprehensive_health(self) -> Dict[str, Any]:
        """Get comprehensive system health report"""
        start_time = time.time()
        
        # Run all health checks
        checks = {
            'system_resources': self.check_system_resources(),
            'flask_app': self.check_flask_app(),
            'external_dependencies': self.check_external_dependencies(),
            'file_permissions': self.check_file_permissions(),
            'process_status': self.check_process_status()
        }
        
        # Calculate overall health
        statuses = [check.get('status') for check in checks.values()]
        if 'critical' in statuses or 'error' in statuses:
            overall_status = 'critical'
        elif 'degraded' in statuses:
            overall_status = 'degraded'
        elif 'warning' in statuses:
            overall_status = 'warning'
        else:
            overall_status = 'healthy'
        
        # Get uptime
        uptime_seconds = time.time() - self.start_time
        uptime_str = str(timedelta(seconds=int(uptime_seconds)))
        
        check_duration = time.time() - start_time
        
        return {
            'status': overall_status,
            'timestamp': datetime.now().isoformat(),
            'uptime': uptime_str,
            'uptime_seconds': int(uptime_seconds),
            'check_duration_ms': round(check_duration * 1000, 2),
            'version': '1.0.0',
            'checks': checks,
            'summary': {
                'total_checks': len(checks),
                'healthy_checks': len([s for s in statuses if s == 'healthy']),
                'warning_checks': len([s for s in statuses if s == 'warning']),
                'degraded_checks': len([s for s in statuses if s == 'degraded']),
                'critical_checks': len([s for s in statuses if s in ['critical', 'error']])
            }
        }

class MonitoringMetrics:
    """Collect and provide monitoring metrics"""
    
    @staticmethod
    def get_process_metrics() -> Dict[str, Any]:
        """Get current process metrics"""
        try:
            process = psutil.Process()
            
            return {
                'timestamp': datetime.now().isoformat(),
                'pid': process.pid,
                'cpu_percent': process.cpu_percent(),
                'memory_percent': process.memory_percent(),
                'memory_info': process.memory_info()._asdict(),
                'num_threads': process.num_threads(),
                'num_fds': process.num_fds() if hasattr(process, 'num_fds') else None,
                'create_time': datetime.fromtimestamp(process.create_time()).isoformat(),
                'status': process.status()
            }
            
        except Exception as e:
            logger.error(f"Failed to get process metrics: {e}")
            return {'error': str(e)}
    
    @staticmethod
    def get_network_metrics() -> Dict[str, Any]:
        """Get network interface metrics"""
        try:
            network_io = psutil.net_io_counters()
            network_connections = len(psutil.net_connections())
            
            return {
                'timestamp': datetime.now().isoformat(),
                'bytes_sent': network_io.bytes_sent,
                'bytes_recv': network_io.bytes_recv,
                'packets_sent': network_io.packets_sent,
                'packets_recv': network_io.packets_recv,
                'errin': network_io.errin,
                'errout': network_io.errout,
                'dropin': network_io.dropin,
                'dropout': network_io.dropout,
                'connections_count': network_connections
            }
            
        except Exception as e:
            logger.error(f"Failed to get network metrics: {e}")
            return {'error': str(e)}

# Command-line interface for standalone health checks
if __name__ == '__main__':
    import argparse
    
    parser = argparse.ArgumentParser(description='Cold Email Dashboard Health Checker')
    parser.add_argument('--check', choices=['all', 'system', 'flask', 'dependencies', 'permissions', 'processes'], 
                       default='all', help='Type of health check to perform')
    parser.add_argument('--format', choices=['json', 'text'], default='text', help='Output format')
    parser.add_argument('--port', type=int, default=5000, help='Flask app port to check')
    
    args = parser.parse_args()
    
    checker = HealthChecker()
    
    if args.check == 'all':
        result = checker.get_comprehensive_health()
    elif args.check == 'system':
        result = checker.check_system_resources()
    elif args.check == 'flask':
        result = checker.check_flask_app(args.port)
    elif args.check == 'dependencies':
        result = checker.check_external_dependencies()
    elif args.check == 'permissions':
        result = checker.check_file_permissions()
    elif args.check == 'processes':
        result = checker.check_process_status()
    
    if args.format == 'json':
        print(json.dumps(result, indent=2))
    else:
        status = result.get('status', 'unknown')
        print(f"Health Status: {status.upper()}")
        
        if 'checks' in result:
            print("\nDetailed Checks:")
            for check_name, check_result in result['checks'].items():
                check_status = check_result.get('status', 'unknown')
                print(f"  {check_name}: {check_status.upper()}")
        
        if 'issues' in result and result['issues']:
            print(f"\nIssues Found:")
            for issue in result['issues']:
                print(f"  - {issue}")
        
        if 'summary' in result:
            summary = result['summary']
            print(f"\nSummary: {summary['healthy_checks']}/{summary['total_checks']} checks healthy")
    
    # Exit with appropriate code
    status = result.get('status', 'unknown')
    if status in ['critical', 'error']:
        sys.exit(2)
    elif status in ['degraded', 'warning']:
        sys.exit(1)
    else:
        sys.exit(0)