#!/usr/bin/env python3
"""
DNS Verifier - DNS Propagation and Record Validation System
Verifies DNS records, checks propagation, and validates email infrastructure
"""

import json
import yaml
import time
import logging
import asyncio
import aiohttp
import dns.resolver
import dns.reversename
import dns.exception
from typing import Dict, List, Optional, Union, Any, Tuple
from datetime import datetime, timedelta
from dataclasses import dataclass, asdict
from pathlib import Path
import os
import sys
import re
import socket
import ssl
import smtplib
from email.mime.text import MIMEText

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/dns-verifier.log'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

@dataclass
class DNSCheckResult:
    """DNS check result data structure"""
    record_type: str
    name: str
    expected: str
    actual: List[str]
    passed: bool
    error: Optional[str] = None
    nameserver: Optional[str] = None
    response_time: Optional[float] = None
    
    def to_dict(self) -> Dict:
        return asdict(self)

@dataclass
class PropagationResult:
    """DNS propagation result data structure"""
    domain: str
    record_type: str
    name: str
    propagated: bool
    nameservers_checked: int
    nameservers_passed: int
    results: List[DNSCheckResult]
    propagation_percentage: float
    
    def to_dict(self) -> Dict:
        return {
            **asdict(self),
            'results': [result.to_dict() for result in self.results]
        }

class DNSVerifier:
    """DNS verification and propagation checking system"""
    
    def __init__(self, config_path: str = None):
        """Initialize DNS verifier with configuration"""
        self.config = self._load_config(config_path)
        self.session = None
        self.resolver = dns.resolver.Resolver()
        self.resolver.timeout = 5
        self.resolver.lifetime = 10
        
        # Default nameservers for propagation checking
        self.nameservers = [
            '8.8.8.8',        # Google
            '8.8.4.4',        # Google
            '1.1.1.1',        # Cloudflare
            '1.0.0.1',        # Cloudflare
            '208.67.222.222', # OpenDNS
            '208.67.220.220', # OpenDNS
            '9.9.9.9',        # Quad9
            '149.112.112.112', # Quad9
            '76.76.19.19',    # Alternate DNS
            '76.223.100.101'  # Alternate DNS
        ]
        
    def _load_config(self, config_path: str = None) -> Dict:
        """Load configuration from file"""
        if not config_path:
            config_path = os.path.join(os.path.dirname(__file__), 'dns-verifier-config.yaml')
        
        try:
            with open(config_path, 'r') as f:
                return yaml.safe_load(f)
        except FileNotFoundError:
            logger.warning(f"Config file not found: {config_path}, using defaults")
            return self._get_default_config()
    
    def _get_default_config(self) -> Dict:
        """Get default configuration"""
        return {
            'timeouts': {
                'dns_query': 5,
                'propagation_check': 300,
                'http_request': 10
            },
            'retries': {
                'dns_query': 3,
                'http_request': 2
            },
            'propagation': {
                'required_percentage': 80,
                'check_interval': 30,
                'max_wait_time': 1800
            },
            'validation': {
                'check_spf': True,
                'check_dkim': True,
                'check_dmarc': True,
                'check_mx': True,
                'check_ptr': True,
                'check_blacklist': True
            },
            'blacklist_servers': [
                'zen.spamhaus.org',
                'bl.spamcop.net',
                'dnsbl.sorbs.net',
                'cbl.abuseat.org',
                'pbl.spamhaus.org'
            ]
        }
    
    async def _create_session(self):
        """Create aiohttp session"""
        if not self.session:
            timeout = aiohttp.ClientTimeout(total=self.config['timeouts']['http_request'])
            self.session = aiohttp.ClientSession(timeout=timeout)
    
    async def _close_session(self):
        """Close aiohttp session"""
        if self.session:
            await self.session.close()
            self.session = None
    
    async def __aenter__(self):
        await self._create_session()
        return self
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        await self._close_session()
    
    def _query_dns(self, name: str, record_type: str, nameserver: str = None) -> Tuple[List[str], float]:
        """Query DNS record with timing"""
        start_time = time.time()
        
        try:
            resolver = dns.resolver.Resolver()
            resolver.timeout = self.config['timeouts']['dns_query']
            
            if nameserver:
                resolver.nameservers = [nameserver]
            
            # Handle different record types
            if record_type == 'PTR':
                # For PTR queries, convert IP to reverse DNS format
                if self._is_ip_address(name):
                    reversed_name = dns.reversename.from_address(name)
                    answers = resolver.resolve(reversed_name, 'PTR')
                else:
                    raise ValueError(f"Invalid IP address for PTR query: {name}")
            else:
                answers = resolver.resolve(name, record_type)
            
            results = []
            for rdata in answers:
                if record_type == 'MX':
                    results.append(f"{rdata.preference} {rdata.exchange}")
                elif record_type == 'SRV':
                    results.append(f"{rdata.priority} {rdata.weight} {rdata.port} {rdata.target}")
                else:
                    results.append(str(rdata).strip('"'))
            
            response_time = time.time() - start_time
            return results, response_time
            
        except dns.exception.DNSException as e:
            response_time = time.time() - start_time
            raise ValueError(f"DNS query failed: {e}")
    
    def _is_ip_address(self, addr: str) -> bool:
        """Check if string is a valid IP address"""
        try:
            socket.inet_aton(addr)
            return True
        except socket.error:
            return False
    
    async def check_single_record(self, name: str, record_type: str, 
                                expected: str, nameserver: str = None) -> DNSCheckResult:
        """Check a single DNS record"""
        try:
            actual, response_time = self._query_dns(name, record_type, nameserver)
            
            # Normalize expected and actual values for comparison
            expected_norm = self._normalize_dns_value(expected, record_type)
            actual_norm = [self._normalize_dns_value(val, record_type) for val in actual]
            
            # Check if expected value is in actual results
            passed = expected_norm in actual_norm
            
            return DNSCheckResult(
                record_type=record_type,
                name=name,
                expected=expected,
                actual=actual,
                passed=passed,
                nameserver=nameserver,
                response_time=response_time
            )
            
        except Exception as e:
            return DNSCheckResult(
                record_type=record_type,
                name=name,
                expected=expected,
                actual=[],
                passed=False,
                error=str(e),
                nameserver=nameserver
            )
    
    def _normalize_dns_value(self, value: str, record_type: str) -> str:
        """Normalize DNS value for comparison"""
        if record_type in ['CNAME', 'MX', 'PTR']:
            # Remove trailing dot if present
            return value.rstrip('.')
        elif record_type == 'TXT':
            # Remove quotes and normalize whitespace
            return re.sub(r'\s+', ' ', value.strip('"').strip())
        else:
            return value.strip()
    
    async def check_propagation(self, name: str, record_type: str, 
                              expected: str) -> PropagationResult:
        """Check DNS propagation across multiple nameservers"""
        results = []
        
        for nameserver in self.nameservers:
            try:
                result = await self.check_single_record(name, record_type, expected, nameserver)
                results.append(result)
            except Exception as e:
                logger.warning(f"Failed to check {nameserver}: {e}")
                results.append(DNSCheckResult(
                    record_type=record_type,
                    name=name,
                    expected=expected,
                    actual=[],
                    passed=False,
                    error=str(e),
                    nameserver=nameserver
                ))
        
        # Calculate propagation statistics
        passed_count = sum(1 for r in results if r.passed)
        total_count = len(results)
        propagation_percentage = (passed_count / total_count) * 100 if total_count > 0 else 0
        propagated = propagation_percentage >= self.config['propagation']['required_percentage']
        
        return PropagationResult(
            domain=name,
            record_type=record_type,
            name=name,
            propagated=propagated,
            nameservers_checked=total_count,
            nameservers_passed=passed_count,
            results=results,
            propagation_percentage=propagation_percentage
        )
    
    async def wait_for_propagation(self, name: str, record_type: str, 
                                 expected: str, timeout: int = None) -> PropagationResult:
        """Wait for DNS propagation to complete"""
        if timeout is None:
            timeout = self.config['propagation']['max_wait_time']
        
        interval = self.config['propagation']['check_interval']
        start_time = time.time()
        
        logger.info(f"Waiting for propagation of {record_type} {name}")
        
        while time.time() - start_time < timeout:
            result = await self.check_propagation(name, record_type, expected)
            
            logger.info(f"Propagation: {result.propagation_percentage:.1f}% "
                       f"({result.nameservers_passed}/{result.nameservers_checked})")
            
            if result.propagated:
                elapsed = time.time() - start_time
                logger.info(f"Propagation completed in {elapsed:.1f} seconds")
                return result
            
            await asyncio.sleep(interval)
        
        # Final check after timeout
        result = await self.check_propagation(name, record_type, expected)
        logger.warning(f"Propagation timeout reached. Final status: {result.propagation_percentage:.1f}%")
        return result
    
    async def verify_spf_record(self, domain: str) -> Dict:
        """Verify SPF record"""
        try:
            result = await self.check_single_record(domain, 'TXT', '')
            
            spf_records = [r for r in result.actual if r.startswith('v=spf1')]
            
            verification = {
                'found': len(spf_records) > 0,
                'count': len(spf_records),
                'valid': True,
                'records': spf_records,
                'warnings': [],
                'errors': []
            }
            
            if len(spf_records) == 0:
                verification['errors'].append("No SPF record found")
                verification['valid'] = False
            elif len(spf_records) > 1:
                verification['errors'].append("Multiple SPF records found")
                verification['valid'] = False
            else:
                # Validate SPF record syntax
                spf_record = spf_records[0]
                
                # Check for common issues
                if len(spf_record) > 255:
                    verification['errors'].append("SPF record too long (>255 characters)")
                    verification['valid'] = False
                
                if spf_record.count('include:') > 10:
                    verification['warnings'].append("Too many includes in SPF record")
                
                if not spf_record.endswith(('~all', '-all', '?all', '+all')):
                    verification['warnings'].append("SPF record should end with an all mechanism")
                
                # Check for IP addresses
                if not re.search(r'ip4:|ip6:', spf_record):
                    verification['warnings'].append("No IP addresses specified in SPF record")
            
            return verification
            
        except Exception as e:
            return {
                'found': False,
                'valid': False,
                'error': str(e),
                'records': [],
                'warnings': [],
                'errors': [str(e)]
            }
    
    async def verify_dkim_record(self, domain: str, selector: str) -> Dict:
        """Verify DKIM record"""
        dkim_domain = f"{selector}._domainkey.{domain}"
        
        try:
            result = await self.check_single_record(dkim_domain, 'TXT', '')
            
            dkim_records = [r for r in result.actual if 'v=DKIM1' in r]
            
            verification = {
                'found': len(dkim_records) > 0,
                'selector': selector,
                'domain': dkim_domain,
                'records': dkim_records,
                'valid': True,
                'warnings': [],
                'errors': []
            }
            
            if len(dkim_records) == 0:
                verification['errors'].append(f"No DKIM record found for selector {selector}")
                verification['valid'] = False
            else:
                dkim_record = dkim_records[0]
                
                # Check for required parameters
                if 'k=rsa' not in dkim_record:
                    verification['warnings'].append("Key type not specified, assuming RSA")
                
                if 'p=' not in dkim_record:
                    verification['errors'].append("Public key not found in DKIM record")
                    verification['valid'] = False
                elif 'p=PLACEHOLDER' in dkim_record:
                    verification['warnings'].append("DKIM record contains placeholder public key")
            
            return verification
            
        except Exception as e:
            return {
                'found': False,
                'valid': False,
                'error': str(e),
                'selector': selector,
                'domain': dkim_domain,
                'records': [],
                'warnings': [],
                'errors': [str(e)]
            }
    
    async def verify_dmarc_record(self, domain: str) -> Dict:
        """Verify DMARC record"""
        dmarc_domain = f"_dmarc.{domain}"
        
        try:
            result = await self.check_single_record(dmarc_domain, 'TXT', '')
            
            dmarc_records = [r for r in result.actual if r.startswith('v=DMARC1')]
            
            verification = {
                'found': len(dmarc_records) > 0,
                'domain': dmarc_domain,
                'records': dmarc_records,
                'valid': True,
                'policy': None,
                'warnings': [],
                'errors': []
            }
            
            if len(dmarc_records) == 0:
                verification['errors'].append("No DMARC record found")
                verification['valid'] = False
            elif len(dmarc_records) > 1:
                verification['errors'].append("Multiple DMARC records found")
                verification['valid'] = False
            else:
                dmarc_record = dmarc_records[0]
                
                # Extract policy
                policy_match = re.search(r'p=([^;]+)', dmarc_record)
                if policy_match:
                    verification['policy'] = policy_match.group(1)
                else:
                    verification['errors'].append("No policy found in DMARC record")
                    verification['valid'] = False
                
                # Check for reporting addresses
                if 'rua=' not in dmarc_record:
                    verification['warnings'].append("No aggregate reporting address specified")
                
                if 'ruf=' not in dmarc_record:
                    verification['warnings'].append("No forensic reporting address specified")
                
                # Check percentage
                pct_match = re.search(r'pct=(\d+)', dmarc_record)
                if pct_match and int(pct_match.group(1)) < 100:
                    verification['warnings'].append(f"DMARC policy applied to only {pct_match.group(1)}% of messages")
            
            return verification
            
        except Exception as e:
            return {
                'found': False,
                'valid': False,
                'error': str(e),
                'domain': dmarc_domain,
                'records': [],
                'warnings': [],
                'errors': [str(e)]
            }
    
    async def verify_mx_records(self, domain: str) -> Dict:
        """Verify MX records"""
        try:
            result = await self.check_single_record(domain, 'MX', '')
            
            verification = {
                'found': len(result.actual) > 0,
                'count': len(result.actual),
                'records': result.actual,
                'valid': True,
                'warnings': [],
                'errors': []
            }
            
            if len(result.actual) == 0:
                verification['errors'].append("No MX records found")
                verification['valid'] = False
            else:
                # Parse MX records and check priorities
                mx_priorities = []
                for mx_record in result.actual:
                    try:
                        priority, exchange = mx_record.split(' ', 1)
                        mx_priorities.append(int(priority))
                        
                        # Check if MX target is reachable
                        try:
                            await self.check_single_record(exchange.rstrip('.'), 'A', '')
                        except Exception:
                            verification['warnings'].append(f"MX target {exchange} may not be reachable")
                    except ValueError:
                        verification['errors'].append(f"Invalid MX record format: {mx_record}")
                        verification['valid'] = False
                
                # Check for backup MX
                if len(mx_priorities) == 1:
                    verification['warnings'].append("Only one MX record found, consider adding backup")
                
                # Check priority values
                if mx_priorities and min(mx_priorities) > 50:
                    verification['warnings'].append("MX priorities seem high, consider lower values")
            
            return verification
            
        except Exception as e:
            return {
                'found': False,
                'valid': False,
                'error': str(e),
                'records': [],
                'warnings': [],
                'errors': [str(e)]
            }
    
    async def verify_ptr_record(self, ip_address: str, expected_hostname: str) -> Dict:
        """Verify PTR (reverse DNS) record"""
        try:
            result = await self.check_single_record(ip_address, 'PTR', expected_hostname)
            
            verification = {
                'ip_address': ip_address,
                'expected': expected_hostname,
                'actual': result.actual,
                'found': len(result.actual) > 0,
                'valid': result.passed,
                'warnings': [],
                'errors': []
            }
            
            if not result.actual:
                verification['errors'].append(f"No PTR record found for {ip_address}")
            elif not result.passed:
                verification['errors'].append(f"PTR record mismatch. Expected: {expected_hostname}, Got: {result.actual}")
            
            return verification
            
        except Exception as e:
            return {
                'ip_address': ip_address,
                'expected': expected_hostname,
                'found': False,
                'valid': False,
                'error': str(e),
                'actual': [],
                'warnings': [],
                'errors': [str(e)]
            }
    
    async def check_blacklist_status(self, ip_address: str) -> Dict:
        """Check if IP is listed in DNS blacklists"""
        blacklist_results = {}
        
        for blacklist in self.config['blacklist_servers']:
            try:
                # Create reverse IP for blacklist query
                ip_parts = ip_address.split('.')
                reversed_ip = '.'.join(reversed(ip_parts))
                blacklist_query = f"{reversed_ip}.{blacklist}"
                
                try:
                    result = await self.check_single_record(blacklist_query, 'A', '')
                    blacklist_results[blacklist] = {
                        'listed': True,
                        'response': result.actual,
                        'error': None
                    }
                except Exception:
                    # Not listed (DNS query failed)
                    blacklist_results[blacklist] = {
                        'listed': False,
                        'response': [],
                        'error': None
                    }
                    
            except Exception as e:
                blacklist_results[blacklist] = {
                    'listed': None,
                    'response': [],
                    'error': str(e)
                }
        
        # Calculate summary
        total_checked = len(blacklist_results)
        listed_count = sum(1 for result in blacklist_results.values() if result['listed'])
        clean = listed_count == 0
        
        return {
            'ip_address': ip_address,
            'clean': clean,
            'total_checked': total_checked,
            'listed_count': listed_count,
            'blacklists': blacklist_results
        }
    
    async def test_smtp_connectivity(self, hostname: str, port: int = 587) -> Dict:
        """Test SMTP connectivity and authentication"""
        try:
            # Test connection
            server = smtplib.SMTP(hostname, port, timeout=10)
            server.set_debuglevel(0)
            
            # Test STARTTLS
            starttls_supported = False
            try:
                server.starttls()
                starttls_supported = True
            except Exception:
                pass
            
            # Get server capabilities
            esmtp_features = server.esmtp_features
            
            server.quit()
            
            return {
                'hostname': hostname,
                'port': port,
                'connected': True,
                'starttls_supported': starttls_supported,
                'esmtp_features': dict(esmtp_features) if esmtp_features else {},
                'error': None
            }
            
        except Exception as e:
            return {
                'hostname': hostname,
                'port': port,
                'connected': False,
                'error': str(e)
            }
    
    async def comprehensive_domain_check(self, domain: str, server_ip: str = None, 
                                       dkim_selector: str = 'default') -> Dict:
        """Perform comprehensive domain verification"""
        logger.info(f"Starting comprehensive check for domain: {domain}")
        
        results = {
            'domain': domain,
            'timestamp': datetime.now().isoformat(),
            'overall_status': 'unknown',
            'score': 0,
            'max_score': 100,
            'checks': {}
        }
        
        # SPF Check
        logger.info("Checking SPF record...")
        spf_result = await self.verify_spf_record(domain)
        results['checks']['spf'] = spf_result
        if spf_result['valid']:
            results['score'] += 20
        
        # DKIM Check
        logger.info("Checking DKIM record...")
        dkim_result = await self.verify_dkim_record(domain, dkim_selector)
        results['checks']['dkim'] = dkim_result
        if dkim_result['valid']:
            results['score'] += 20
        
        # DMARC Check
        logger.info("Checking DMARC record...")
        dmarc_result = await self.verify_dmarc_record(domain)
        results['checks']['dmarc'] = dmarc_result
        if dmarc_result['valid']:
            results['score'] += 15
        
        # MX Check
        logger.info("Checking MX records...")
        mx_result = await self.verify_mx_records(domain)
        results['checks']['mx'] = mx_result
        if mx_result['valid']:
            results['score'] += 25
        
        # PTR Check (if IP provided)
        if server_ip:
            logger.info("Checking PTR record...")
            ptr_result = await self.verify_ptr_record(server_ip, domain)
            results['checks']['ptr'] = ptr_result
            if ptr_result['valid']:
                results['score'] += 10
            
            # Blacklist Check
            logger.info("Checking blacklist status...")
            blacklist_result = await self.check_blacklist_status(server_ip)
            results['checks']['blacklist'] = blacklist_result
            if blacklist_result['clean']:
                results['score'] += 10
        
        # Determine overall status
        if results['score'] >= 90:
            results['overall_status'] = 'excellent'
        elif results['score'] >= 70:
            results['overall_status'] = 'good'
        elif results['score'] >= 50:
            results['overall_status'] = 'fair'
        else:
            results['overall_status'] = 'poor'
        
        logger.info(f"Comprehensive check completed. Score: {results['score']}/{results['max_score']} ({results['overall_status']})")
        
        return results
    
    async def monitor_dns_changes(self, domain: str, record_type: str, 
                                expected: str, interval: int = 300) -> None:
        """Monitor DNS record for changes"""
        logger.info(f"Starting DNS monitoring for {record_type} {domain}")
        
        last_result = None
        
        while True:
            try:
                result = await self.check_single_record(domain, record_type, expected)
                
                if last_result is None:
                    logger.info(f"Initial check: {record_type} {domain} = {result.actual}")
                elif result.actual != last_result.actual:
                    logger.warning(f"DNS change detected: {record_type} {domain}")
                    logger.warning(f"  Previous: {last_result.actual}")
                    logger.warning(f"  Current:  {result.actual}")
                
                last_result = result
                
            except Exception as e:
                logger.error(f"DNS monitoring error: {e}")
            
            await asyncio.sleep(interval)

# CLI Interface
async def main():
    """Main CLI interface"""
    import argparse
    
    parser = argparse.ArgumentParser(description='DNS Verifier CLI')
    parser.add_argument('command', choices=[
        'check', 'propagation', 'wait-propagation', 'comprehensive',
        'spf', 'dkim', 'dmarc', 'mx', 'ptr', 'blacklist', 'monitor'
    ])
    parser.add_argument('--domain', required=True, help='Domain name')
    parser.add_argument('--type', default='A', help='DNS record type')
    parser.add_argument('--expected', help='Expected value')
    parser.add_argument('--ip', help='IP address')
    parser.add_argument('--selector', default='default', help='DKIM selector')
    parser.add_argument('--timeout', type=int, help='Timeout in seconds')
    parser.add_argument('--interval', type=int, default=300, help='Check interval for monitoring')
    parser.add_argument('--config', help='Config file path')
    parser.add_argument('--output', help='Output file path')
    parser.add_argument('--format', choices=['json', 'yaml'], default='json', help='Output format')
    
    args = parser.parse_args()
    
    async with DNSVerifier(args.config) as verifier:
        try:
            if args.command == 'check':
                if not args.expected:
                    raise ValueError("Expected value required for check command")
                result = await verifier.check_single_record(args.domain, args.type, args.expected)
                output = result.to_dict()
                
            elif args.command == 'propagation':
                if not args.expected:
                    raise ValueError("Expected value required for propagation command")
                result = await verifier.check_propagation(args.domain, args.type, args.expected)
                output = result.to_dict()
                
            elif args.command == 'wait-propagation':
                if not args.expected:
                    raise ValueError("Expected value required for wait-propagation command")
                result = await verifier.wait_for_propagation(args.domain, args.type, args.expected, args.timeout)
                output = result.to_dict()
                
            elif args.command == 'comprehensive':
                result = await verifier.comprehensive_domain_check(args.domain, args.ip, args.selector)
                output = result
                
            elif args.command == 'spf':
                result = await verifier.verify_spf_record(args.domain)
                output = result
                
            elif args.command == 'dkim':
                result = await verifier.verify_dkim_record(args.domain, args.selector)
                output = result
                
            elif args.command == 'dmarc':
                result = await verifier.verify_dmarc_record(args.domain)
                output = result
                
            elif args.command == 'mx':
                result = await verifier.verify_mx_records(args.domain)
                output = result
                
            elif args.command == 'ptr':
                if not args.ip:
                    raise ValueError("IP address required for PTR command")
                result = await verifier.verify_ptr_record(args.ip, args.domain)
                output = result
                
            elif args.command == 'blacklist':
                if not args.ip:
                    raise ValueError("IP address required for blacklist command")
                result = await verifier.check_blacklist_status(args.ip)
                output = result
                
            elif args.command == 'monitor':
                if not args.expected:
                    raise ValueError("Expected value required for monitor command")
                await verifier.monitor_dns_changes(args.domain, args.type, args.expected, args.interval)
                return  # Monitor runs indefinitely
            
            # Output results
            if args.format == 'yaml':
                output_str = yaml.dump(output, default_flow_style=False)
            else:
                output_str = json.dumps(output, indent=2)
            
            if args.output:
                with open(args.output, 'w') as f:
                    f.write(output_str)
            else:
                print(output_str)
                
        except Exception as e:
            logger.error(f"Command failed: {e}")
            sys.exit(1)

if __name__ == '__main__':
    asyncio.run(main())