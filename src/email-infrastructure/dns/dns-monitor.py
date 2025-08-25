#!/usr/bin/env python3
"""
DNS Monitor - DNS Health Monitoring and Blacklist Checking System
Monitors DNS records, checks propagation, validates deliverability, and monitors blacklists
"""

import json
import yaml
import time
import logging
import asyncio
import aiohttp
import schedule
from typing import Dict, List, Optional, Any, Tuple
from datetime import datetime, timedelta
from dataclasses import dataclass, asdict
from pathlib import Path
import os
import sys
import smtplib
import ssl
from email.mime.text import MIMEText
import concurrent.futures
from dns_verifier import DNSVerifier, DNSCheckResult, PropagationResult

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/dns-monitor.log'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

@dataclass
class MonitoringRule:
    """DNS monitoring rule configuration"""
    name: str
    domain: str
    record_type: str
    record_name: str
    expected_value: str
    check_interval: int = 300  # seconds
    alert_threshold: int = 3   # consecutive failures before alert
    enabled: bool = True
    
@dataclass
class AlertConfig:
    """Alert configuration"""
    webhook_url: Optional[str] = None
    email_recipients: List[str] = None
    slack_webhook: Optional[str] = None
    discord_webhook: Optional[str] = None
    alert_cooldown: int = 3600  # seconds between same alerts
    
@dataclass
class MonitoringResult:
    """Monitoring check result"""
    rule_name: str
    timestamp: datetime
    success: bool
    message: str
    details: Dict = None
    response_time: float = None
    
    def to_dict(self) -> Dict:
        return {
            **asdict(self),
            'timestamp': self.timestamp.isoformat(),
            'details': self.details or {}
        }

class DNSMonitor:
    """DNS monitoring and alerting system"""
    
    def __init__(self, config_path: str = None):
        """Initialize DNS monitor"""
        self.config = self._load_config(config_path)
        self.verifier = DNSVerifier()
        self.session = None
        self.monitoring_rules = []
        self.alert_history = {}
        self.results_history = []
        self.running = False
        
        # Load monitoring rules
        self._load_monitoring_rules()
        
        # Initialize alert config
        self.alert_config = AlertConfig(**self.config.get('alerts', {}))
        
    def _load_config(self, config_path: str = None) -> Dict:
        """Load configuration from file"""
        if not config_path:
            config_path = os.path.join(os.path.dirname(__file__), 'dns-monitor-config.yaml')
        
        try:
            with open(config_path, 'r') as f:
                return yaml.safe_load(f)
        except FileNotFoundError:
            logger.warning(f"Config file not found: {config_path}, using defaults")
            return self._get_default_config()
    
    def _get_default_config(self) -> Dict:
        """Get default configuration"""
        return {
            'monitoring': {
                'default_interval': 300,
                'alert_threshold': 3,
                'max_concurrent_checks': 10,
                'timeout': 30
            },
            'blacklist': {
                'check_interval': 3600,
                'servers': [
                    'zen.spamhaus.org',
                    'bl.spamcop.net',
                    'dnsbl.sorbs.net',
                    'cbl.abuseat.org',
                    'pbl.spamhaus.org',
                    'sbl.spamhaus.org',
                    'xbl.spamhaus.org'
                ]
            },
            'deliverability': {
                'check_interval': 1800,
                'test_domains': [
                    'gmail.com',
                    'outlook.com',
                    'yahoo.com',
                    'aol.com'
                ]
            },
            'alerts': {
                'webhook_url': None,
                'email_recipients': [],
                'alert_cooldown': 3600
            },
            'storage': {
                'results_retention_days': 30,
                'export_format': 'json',
                'export_path': '/var/log/dns-monitor-results.json'
            }
        }
    
    def _load_monitoring_rules(self):
        """Load monitoring rules from configuration"""
        rules_config = self.config.get('rules', [])
        self.monitoring_rules = []
        
        for rule_config in rules_config:
            rule = MonitoringRule(**rule_config)
            self.monitoring_rules.append(rule)
            logger.info(f"Loaded monitoring rule: {rule.name}")
    
    async def _create_session(self):
        """Create aiohttp session"""
        if not self.session:
            timeout = aiohttp.ClientTimeout(total=30)
            self.session = aiohttp.ClientSession(timeout=timeout)
    
    async def _close_session(self):
        """Close aiohttp session"""
        if self.session:
            await self.session.close()
            self.session = None
    
    async def check_dns_record(self, rule: MonitoringRule) -> MonitoringResult:
        """Check a single DNS record according to monitoring rule"""
        start_time = time.time()
        
        try:
            result = await self.verifier.check_single_record(
                rule.record_name,
                rule.record_type,
                rule.expected_value
            )
            
            response_time = time.time() - start_time
            
            if result.passed:
                return MonitoringResult(
                    rule_name=rule.name,
                    timestamp=datetime.now(),
                    success=True,
                    message=f"DNS check passed: {rule.record_type} {rule.record_name}",
                    details=result.to_dict(),
                    response_time=response_time
                )
            else:
                return MonitoringResult(
                    rule_name=rule.name,
                    timestamp=datetime.now(),
                    success=False,
                    message=f"DNS check failed: Expected {rule.expected_value}, got {result.actual}",
                    details=result.to_dict(),
                    response_time=response_time
                )
                
        except Exception as e:
            response_time = time.time() - start_time
            return MonitoringResult(
                rule_name=rule.name,
                timestamp=datetime.now(),
                success=False,
                message=f"DNS check error: {str(e)}",
                details={'error': str(e)},
                response_time=response_time
            )
    
    async def check_propagation_status(self, domain: str, record_type: str, 
                                     expected: str) -> MonitoringResult:
        """Check DNS propagation status"""
        start_time = time.time()
        
        try:
            result = await self.verifier.check_propagation(domain, record_type, expected)
            response_time = time.time() - start_time
            
            success = result.propagated
            message = f"Propagation: {result.propagation_percentage:.1f}% ({result.nameservers_passed}/{result.nameservers_checked})"
            
            return MonitoringResult(
                rule_name=f"propagation_{domain}_{record_type}",
                timestamp=datetime.now(),
                success=success,
                message=message,
                details=result.to_dict(),
                response_time=response_time
            )
            
        except Exception as e:
            response_time = time.time() - start_time
            return MonitoringResult(
                rule_name=f"propagation_{domain}_{record_type}",
                timestamp=datetime.now(),
                success=False,
                message=f"Propagation check error: {str(e)}",
                details={'error': str(e)},
                response_time=response_time
            )
    
    async def check_blacklist_status(self, ip_address: str) -> MonitoringResult:
        """Check IP blacklist status"""
        start_time = time.time()
        
        try:
            result = await self.verifier.check_blacklist_status(ip_address)
            response_time = time.time() - start_time
            
            success = result['clean']
            
            if success:
                message = f"IP {ip_address} is clean (checked {result['total_checked']} blacklists)"
            else:
                message = f"IP {ip_address} is listed on {result['listed_count']}/{result['total_checked']} blacklists"
            
            return MonitoringResult(
                rule_name=f"blacklist_{ip_address}",
                timestamp=datetime.now(),
                success=success,
                message=message,
                details=result,
                response_time=response_time
            )
            
        except Exception as e:
            response_time = time.time() - start_time
            return MonitoringResult(
                rule_name=f"blacklist_{ip_address}",
                timestamp=datetime.now(),
                success=False,
                message=f"Blacklist check error: {str(e)}",
                details={'error': str(e)},
                response_time=response_time
            )
    
    async def test_email_deliverability(self, domain: str, from_email: str) -> MonitoringResult:
        """Test email deliverability to major providers"""
        start_time = time.time()
        
        try:
            deliverability_results = {}
            test_domains = self.config['deliverability']['test_domains']
            
            for test_domain in test_domains:
                try:
                    # Test SMTP connection to the domain
                    mx_records = await self.verifier.check_single_record(test_domain, 'MX', '')
                    
                    if mx_records.actual:
                        # Get the primary MX record
                        mx_record = mx_records.actual[0]
                        mx_server = mx_record.split(' ')[1].rstrip('.')
                        
                        # Test SMTP connectivity
                        smtp_result = await self.verifier.test_smtp_connectivity(mx_server, 25)
                        deliverability_results[test_domain] = {
                            'mx_server': mx_server,
                            'smtp_accessible': smtp_result['connected'],
                            'error': smtp_result.get('error')
                        }
                    else:
                        deliverability_results[test_domain] = {
                            'mx_server': None,
                            'smtp_accessible': False,
                            'error': 'No MX records found'
                        }
                        
                except Exception as e:
                    deliverability_results[test_domain] = {
                        'mx_server': None,
                        'smtp_accessible': False,
                        'error': str(e)
                    }
            
            # Calculate success rate
            accessible_count = sum(1 for r in deliverability_results.values() if r['smtp_accessible'])
            total_count = len(deliverability_results)
            success_rate = (accessible_count / total_count) * 100 if total_count > 0 else 0
            
            response_time = time.time() - start_time
            success = success_rate >= 80  # 80% threshold
            
            message = f"Deliverability test: {success_rate:.1f}% ({accessible_count}/{total_count}) providers accessible"
            
            return MonitoringResult(
                rule_name=f"deliverability_{domain}",
                timestamp=datetime.now(),
                success=success,
                message=message,
                details={
                    'success_rate': success_rate,
                    'results': deliverability_results
                },
                response_time=response_time
            )
            
        except Exception as e:
            response_time = time.time() - start_time
            return MonitoringResult(
                rule_name=f"deliverability_{domain}",
                timestamp=datetime.now(),
                success=False,
                message=f"Deliverability test error: {str(e)}",
                details={'error': str(e)},
                response_time=response_time
            )
    
    async def comprehensive_domain_health_check(self, domain: str, server_ip: str) -> List[MonitoringResult]:
        """Perform comprehensive domain health check"""
        results = []
        
        # DNS record checks
        dns_checks = [
            ('MX', domain, ''),
            ('A', domain, server_ip),
            ('TXT', domain, ''),  # SPF
            ('TXT', f'_dmarc.{domain}', ''),  # DMARC
        ]
        
        for record_type, name, expected in dns_checks:
            try:
                if expected:
                    result = await self.verifier.check_single_record(name, record_type, expected)
                else:
                    result = await self.verifier.check_single_record(name, record_type, '')
                
                results.append(MonitoringResult(
                    rule_name=f"{record_type.lower()}_{name}",
                    timestamp=datetime.now(),
                    success=len(result.actual) > 0,
                    message=f"{record_type} check for {name}: {len(result.actual)} records found",
                    details=result.to_dict()
                ))
            except Exception as e:
                results.append(MonitoringResult(
                    rule_name=f"{record_type.lower()}_{name}",
                    timestamp=datetime.now(),
                    success=False,
                    message=f"{record_type} check error: {str(e)}",
                    details={'error': str(e)}
                ))
        
        # Blacklist check
        blacklist_result = await self.check_blacklist_status(server_ip)
        results.append(blacklist_result)
        
        # Deliverability test
        deliverability_result = await self.test_email_deliverability(domain, f"test@{domain}")
        results.append(deliverability_result)
        
        return results
    
    def should_send_alert(self, rule_name: str) -> bool:
        """Check if alert should be sent based on cooldown"""
        now = datetime.now()
        last_alert = self.alert_history.get(rule_name)
        
        if not last_alert:
            return True
        
        cooldown = timedelta(seconds=self.alert_config.alert_cooldown)
        return now - last_alert > cooldown
    
    async def send_alert(self, result: MonitoringResult):
        """Send alert notification"""
        if not self.should_send_alert(result.rule_name):
            logger.debug(f"Alert cooldown active for {result.rule_name}")
            return
        
        alert_data = {
            'rule': result.rule_name,
            'timestamp': result.timestamp.isoformat(),
            'status': 'FAILURE' if not result.success else 'RECOVERY',
            'message': result.message,
            'details': result.details
        }
        
        # Send webhook alert
        if self.alert_config.webhook_url:
            try:
                async with self.session.post(self.alert_config.webhook_url, json=alert_data) as response:
                    if response.status == 200:
                        logger.info(f"Alert sent via webhook for {result.rule_name}")
                    else:
                        logger.error(f"Failed to send webhook alert: {response.status}")
            except Exception as e:
                logger.error(f"Webhook alert error: {e}")
        
        # Send Slack alert
        if self.alert_config.slack_webhook:
            slack_payload = {
                'text': f"DNS Monitor Alert: {result.rule_name}",
                'attachments': [
                    {
                        'color': 'danger' if not result.success else 'good',
                        'fields': [
                            {'title': 'Rule', 'value': result.rule_name, 'short': True},
                            {'title': 'Status', 'value': alert_data['status'], 'short': True},
                            {'title': 'Message', 'value': result.message, 'short': False}
                        ],
                        'timestamp': int(result.timestamp.timestamp())
                    }
                ]
            }
            
            try:
                async with self.session.post(self.alert_config.slack_webhook, json=slack_payload) as response:
                    if response.status == 200:
                        logger.info(f"Slack alert sent for {result.rule_name}")
                    else:
                        logger.error(f"Failed to send Slack alert: {response.status}")
            except Exception as e:
                logger.error(f"Slack alert error: {e}")
        
        # Update alert history
        self.alert_history[result.rule_name] = result.timestamp
    
    async def run_monitoring_cycle(self):
        """Run a single monitoring cycle"""
        if not self.monitoring_rules:
            logger.warning("No monitoring rules configured")
            return
        
        logger.info(f"Starting monitoring cycle with {len(self.monitoring_rules)} rules")
        
        # Run checks concurrently
        max_concurrent = self.config['monitoring']['max_concurrent_checks']
        semaphore = asyncio.Semaphore(max_concurrent)
        
        async def run_check_with_semaphore(rule):
            async with semaphore:
                return await self.check_dns_record(rule)
        
        # Execute all checks
        tasks = [run_check_with_semaphore(rule) for rule in self.monitoring_rules if rule.enabled]
        results = await asyncio.gather(*tasks, return_exceptions=True)
        
        # Process results
        for result in results:
            if isinstance(result, Exception):
                logger.error(f"Monitoring check exception: {result}")
                continue
            
            # Store result
            self.results_history.append(result)
            
            # Send alert if needed
            if not result.success:
                await self.send_alert(result)
            
            # Log result
            if result.success:
                logger.info(f"✓ {result.rule_name}: {result.message}")
            else:
                logger.warning(f"✗ {result.rule_name}: {result.message}")
        
        # Cleanup old results
        self._cleanup_old_results()
        
        logger.info(f"Monitoring cycle completed. Processed {len(results)} checks")
    
    def _cleanup_old_results(self):
        """Clean up old monitoring results"""
        retention_days = self.config['storage']['results_retention_days']
        cutoff_date = datetime.now() - timedelta(days=retention_days)
        
        initial_count = len(self.results_history)
        self.results_history = [r for r in self.results_history if r.timestamp > cutoff_date]
        cleaned_count = initial_count - len(self.results_history)
        
        if cleaned_count > 0:
            logger.info(f"Cleaned up {cleaned_count} old monitoring results")
    
    def get_monitoring_status(self) -> Dict:
        """Get current monitoring status"""
        if not self.results_history:
            return {
                'status': 'no_data',
                'total_rules': len(self.monitoring_rules),
                'enabled_rules': len([r for r in self.monitoring_rules if r.enabled]),
                'last_check': None,
                'success_rate': 0
            }
        
        # Get recent results (last hour)
        cutoff_time = datetime.now() - timedelta(hours=1)
        recent_results = [r for r in self.results_history if r.timestamp > cutoff_time]
        
        if not recent_results:
            return {
                'status': 'stale',
                'total_rules': len(self.monitoring_rules),
                'enabled_rules': len([r for r in self.monitoring_rules if r.enabled]),
                'last_check': max(r.timestamp for r in self.results_history),
                'success_rate': 0
            }
        
        # Calculate success rate
        successful = len([r for r in recent_results if r.success])
        success_rate = (successful / len(recent_results)) * 100
        
        # Determine overall status
        if success_rate >= 95:
            status = 'healthy'
        elif success_rate >= 80:
            status = 'degraded'
        else:
            status = 'critical'
        
        return {
            'status': status,
            'total_rules': len(self.monitoring_rules),
            'enabled_rules': len([r for r in self.monitoring_rules if r.enabled]),
            'last_check': max(r.timestamp for r in recent_results),
            'success_rate': success_rate,
            'recent_results': len(recent_results),
            'successful_checks': successful,
            'failed_checks': len(recent_results) - successful
        }
    
    def export_results(self, filepath: str = None, format: str = 'json'):
        """Export monitoring results to file"""
        if not filepath:
            filepath = self.config['storage']['export_path']
        
        export_data = {
            'export_timestamp': datetime.now().isoformat(),
            'monitoring_rules': [asdict(rule) for rule in self.monitoring_rules],
            'results': [result.to_dict() for result in self.results_history],
            'status': self.get_monitoring_status()
        }
        
        if format.lower() == 'yaml':
            with open(filepath, 'w') as f:
                yaml.dump(export_data, f, default_flow_style=False)
        else:
            with open(filepath, 'w') as f:
                json.dump(export_data, f, indent=2)
        
        logger.info(f"Exported {len(self.results_history)} results to {filepath}")
    
    async def start_monitoring(self):
        """Start continuous monitoring"""
        self.running = True
        await self._create_session()
        
        logger.info("Starting DNS monitoring service")
        
        try:
            while self.running:
                await self.run_monitoring_cycle()
                
                # Calculate next check interval
                min_interval = min(rule.check_interval for rule in self.monitoring_rules if rule.enabled)
                await asyncio.sleep(min_interval)
                
        except KeyboardInterrupt:
            logger.info("Monitoring stopped by user")
        except Exception as e:
            logger.error(f"Monitoring error: {e}")
        finally:
            await self._close_session()
    
    def stop_monitoring(self):
        """Stop monitoring"""
        self.running = False
        logger.info("DNS monitoring stop requested")

# CLI Interface
async def main():
    """Main CLI interface"""
    import argparse
    
    parser = argparse.ArgumentParser(description='DNS Monitor CLI')
    parser.add_argument('command', choices=[
        'start', 'check', 'status', 'export', 'blacklist', 'deliverability', 'health'
    ])
    parser.add_argument('--config', help='Config file path')
    parser.add_argument('--domain', help='Domain name')
    parser.add_argument('--ip', help='IP address')
    parser.add_argument('--output', help='Output file path')
    parser.add_argument('--format', choices=['json', 'yaml'], default='json')
    parser.add_argument('--daemon', action='store_true', help='Run as daemon')
    
    args = parser.parse_args()
    
    try:
        monitor = DNSMonitor(args.config)
        
        if args.command == 'start':
            if args.daemon:
                # Run as daemon (simplified)
                await monitor.start_monitoring()
            else:
                await monitor.run_monitoring_cycle()
                
        elif args.command == 'check':
            if not args.domain:
                raise ValueError("Domain required for check command")
            results = await monitor.comprehensive_domain_health_check(args.domain, args.ip or '')
            output = [result.to_dict() for result in results]
            
        elif args.command == 'status':
            output = monitor.get_monitoring_status()
            
        elif args.command == 'export':
            output_path = args.output or f"dns-monitor-export-{int(time.time())}.{args.format}"
            monitor.export_results(output_path, args.format)
            print(f"Results exported to {output_path}")
            return
            
        elif args.command == 'blacklist':
            if not args.ip:
                raise ValueError("IP address required for blacklist command")
            result = await monitor.check_blacklist_status(args.ip)
            output = result.to_dict()
            
        elif args.command == 'deliverability':
            if not args.domain:
                raise ValueError("Domain required for deliverability command")
            result = await monitor.test_email_deliverability(args.domain, f"test@{args.domain}")
            output = result.to_dict()
            
        elif args.command == 'health':
            if not args.domain:
                raise ValueError("Domain required for health command")
            results = await monitor.comprehensive_domain_health_check(args.domain, args.ip or '')
            output = {
                'domain': args.domain,
                'timestamp': datetime.now().isoformat(),
                'results': [result.to_dict() for result in results],
                'overall_health': all(r.success for r in results)
            }
        
        # Output results (if not handled above)
        if 'output' in locals():
            if args.format == 'yaml':
                print(yaml.dump(output, default_flow_style=False))
            else:
                print(json.dumps(output, indent=2))
                
    except Exception as e:
        logger.error(f"Command failed: {e}")
        sys.exit(1)

if __name__ == '__main__':
    asyncio.run(main())