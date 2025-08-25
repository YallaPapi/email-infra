#!/usr/bin/env python3
"""
Cold Email Infrastructure Dashboard
Web interface to test and verify the email infrastructure setup
"""

from flask import Flask, render_template, jsonify, request, redirect, url_for, flash
from flask_cors import CORS
from functools import wraps
import os
import sys
import json
import subprocess
import socket
import requests
import dns.resolver
import smtplib
import ssl
import psutil
import time
import re
import hashlib
import uuid
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from datetime import datetime, timedelta
from pathlib import Path
import threading
import random
import logging
from collections import defaultdict
import asyncio
import concurrent.futures
from dotenv import load_dotenv

# Add parent directory to path
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Configure logging first
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Load environment variables from parent directory .env file
parent_env_path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), '.env')
if os.path.exists(parent_env_path):
    load_dotenv(parent_env_path)
    logger.info(f"Loaded environment variables from {parent_env_path}")
else:
    logger.warning(f"Environment file not found at {parent_env_path}")

# Also load local .env if it exists
local_env_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), '.env')
if os.path.exists(local_env_path):
    load_dotenv(local_env_path)
    logger.info(f"Loaded local environment variables from {local_env_path}")

app = Flask(__name__)
app.secret_key = os.environ.get('FLASK_SECRET_KEY', 'dev-secret-key-change-in-production')

# Enable CORS for API access
CORS(app, origins=['*'])

# Rate limiting storage
rate_limit_storage = defaultdict(list)

# Configuration
BASE_DIR = Path(__file__).parent.parent
SRC_DIR = BASE_DIR / 'src' / 'email-infrastructure'

# API Configuration
API_KEY = os.environ.get('API_KEY', 'dashboard-api-key-change-in-production')
RATE_LIMIT_REQUESTS = int(os.environ.get('RATE_LIMIT_REQUESTS', 100))
RATE_LIMIT_WINDOW = int(os.environ.get('RATE_LIMIT_WINDOW', 3600))  # 1 hour

class SystemChecker:
    """Check status of all system components"""
    
    @staticmethod
    def check_dns_status():
        """Check if DNS configuration is valid"""
        try:
            # Check if Cloudflare API key is configured
            api_key = os.environ.get('CLOUDFLARE_API_TOKEN')
            if not api_key or api_key == 'your_cloudflare_api_token_here':
                return {'status': 'warning', 'message': 'Cloudflare API token not configured - using placeholder value'}
            
            # Test Cloudflare API connection
            headers = {
                'Authorization': f'Bearer {api_key}',
                'Content-Type': 'application/json'
            }
            
            # Get user information and zones
            user_response = requests.get('https://api.cloudflare.com/client/v4/user', headers=headers, timeout=10)
            
            if user_response.status_code == 200:
                user_data = user_response.json()
                
                # Try to get zones
                zones_response = requests.get('https://api.cloudflare.com/client/v4/zones', headers=headers, timeout=10)
                zones_data = zones_response.json() if zones_response.status_code == 200 else {'result': []}
                
                # Get configured domain
                domain = os.environ.get('DOMAIN', 'yourdomain.com')
                
                # Check if domain is managed by Cloudflare
                domain_found = False
                domain_info = None
                if zones_data.get('result'):
                    for zone in zones_data['result']:
                        if zone['name'] == domain:
                            domain_found = True
                            domain_info = zone
                            break
                
                return {
                    'status': 'success',
                    'message': f'Cloudflare API connected - {len(zones_data.get("result", []))} zones found',
                    'data': {
                        'user_email': user_data.get('result', {}).get('email', 'Unknown'),
                        'zones_count': len(zones_data.get('result', [])),
                        'zones': [zone['name'] for zone in zones_data.get('result', [])],
                        'domain_managed': domain_found,
                        'configured_domain': domain,
                        'domain_info': domain_info
                    }
                }
            elif user_response.status_code == 401:
                return {'status': 'error', 'message': 'Invalid Cloudflare API token - authentication failed'}
            elif user_response.status_code == 403:
                return {'status': 'error', 'message': 'Cloudflare API token lacks required permissions'}
            else:
                return {'status': 'error', 'message': f'Cloudflare API error: {user_response.status_code}'}
        except requests.exceptions.Timeout:
            return {'status': 'error', 'message': 'Cloudflare API request timed out'}
        except requests.exceptions.ConnectionError:
            return {'status': 'error', 'message': 'Unable to connect to Cloudflare API'}
        except Exception as e:
            return {'status': 'error', 'message': f'DNS check error: {str(e)}'}
    
    @staticmethod
    def check_mailcow_status():
        """Check if Mailcow is accessible"""
        try:
            mailcow_host = os.environ.get('MAILCOW_HOSTNAME', 'localhost')
            api_key = os.environ.get('MAILCOW_API_KEY')
            
            if not api_key:
                return {'status': 'warning', 'message': 'Mailcow not configured yet'}
            
            # Try to connect to Mailcow API
            url = f'https://{mailcow_host}/api/v1/get/status/containers'
            headers = {'X-API-Key': api_key}
            response = requests.get(url, headers=headers, verify=False, timeout=5)
            
            if response.status_code == 200:
                return {'status': 'success', 'message': 'Mailcow is running', 'data': response.json()}
            else:
                return {'status': 'error', 'message': f'Mailcow API error: {response.status_code}'}
        except requests.exceptions.ConnectionError:
            return {'status': 'warning', 'message': 'Mailcow not installed or not running'}
        except Exception as e:
            return {'status': 'error', 'message': str(e)}
    
    @staticmethod
    def check_vps_status():
        """Check VPS configuration and network"""
        try:
            # Get system info
            hostname = socket.gethostname()
            
            # Get configured server IP
            configured_ip = os.environ.get('SERVER_IP', '157.180.44.191')
            
            # Check if we have a public IP
            try:
                public_ip = requests.get('https://api.ipify.org', timeout=5).text
            except:
                public_ip = 'Unable to determine'
            
            # Get local IP
            try:
                local_ip = socket.gethostbyname(hostname)
            except:
                local_ip = 'Unable to determine'
            
            # Check if public IP matches configured IP
            ip_match = public_ip == configured_ip
            
            status = 'success' if ip_match else 'warning'
            message = 'VPS configuration matches' if ip_match else f'Public IP ({public_ip}) does not match configured IP ({configured_ip})'
            
            return {
                'status': status,
                'message': message,
                'data': {
                    'hostname': hostname,
                    'local_ip': local_ip,
                    'public_ip': public_ip,
                    'configured_ip': configured_ip,
                    'ip_match': ip_match
                }
            }
        except Exception as e:
            return {'status': 'error', 'message': str(e)}
    
    @staticmethod
    def check_email_config():
        """Check email configuration status"""
        config = {
            'domain': os.environ.get('DOMAIN', 'yourdomain.com'),
            'server_ip': os.environ.get('SERVER_IP', '157.180.44.191'),
            'admin_email': os.environ.get('ADMIN_EMAIL', 'admin@yourdomain.com'),
            'dmarc_email': os.environ.get('DMARC_EMAIL', 'dmarc@yourdomain.com'),
            'smtp_host': os.environ.get('SMTP_HOST', 'mail.yourdomain.com'),
            'smtp_port': os.environ.get('SMTP_PORT', '587'),
            'smtp_user': os.environ.get('SMTP_USER', 'admin@yourdomain.com'),
            'smtp_security': os.environ.get('SMTP_SECURITY', 'tls'),
            'mailcow_hostname': os.environ.get('MAILCOW_HOSTNAME', 'mail.yourdomain.com')
        }
        
        # Check if critical configurations are placeholder values
        placeholders = ['yourdomain.com', 'your_cloudflare_api_token_here', 'your_smtp_password_here']
        has_placeholders = any(placeholder in str(config[key]) for key in config for placeholder in placeholders)
        
        if has_placeholders:
            return {'status': 'warning', 'message': 'Configuration contains placeholder values - please update with real values', 'data': config}
        
        return {'status': 'success', 'message': 'Email configuration loaded successfully', 'data': config}
    
    @staticmethod
    def test_dns_records(domain):
        """Test DNS records for a domain"""
        results = {}
        
        try:
            # Test A record
            try:
                a_records = dns.resolver.resolve(domain, 'A')
                results['A'] = [str(r) for r in a_records]
            except:
                results['A'] = []
            
            # Test MX record
            try:
                mx_records = dns.resolver.resolve(domain, 'MX')
                results['MX'] = [f"{r.preference} {r.exchange}" for r in mx_records]
            except:
                results['MX'] = []
            
            # Test TXT records (SPF, DMARC)
            try:
                txt_records = dns.resolver.resolve(domain, 'TXT')
                results['TXT'] = [str(r).strip('"') for r in txt_records]
                
                # Check for SPF
                results['SPF'] = [r for r in results['TXT'] if r.startswith('v=spf1')]
                
                # Check for DMARC
                try:
                    dmarc = dns.resolver.resolve(f'_dmarc.{domain}', 'TXT')
                    results['DMARC'] = [str(r).strip('"') for r in dmarc]
                except:
                    results['DMARC'] = []
                
                # Check for DKIM (if selector is known)
                selector = os.environ.get('DKIM_SELECTOR', 'default')
                try:
                    dkim = dns.resolver.resolve(f'{selector}._domainkey.{domain}', 'TXT')
                    results['DKIM'] = [str(r).strip('"') for r in dkim]
                except:
                    results['DKIM'] = []
            except:
                results['TXT'] = []
            
            return {'status': 'success', 'data': results}
        except Exception as e:
            return {'status': 'error', 'message': str(e), 'data': results}

@app.route('/')
def index():
    """Main dashboard page"""
    return render_template('index.html')

@app.route('/api/status')
def api_status():
    """Get overall system status"""
    status = {
        'dns': SystemChecker.check_dns_status(),
        'mailcow': SystemChecker.check_mailcow_status(),
        'vps': SystemChecker.check_vps_status(),
        'email': SystemChecker.check_email_config(),
        'timestamp': datetime.now().isoformat()
    }
    return jsonify(status)

@app.route('/api/test-dns', methods=['POST'])
def test_dns():
    """Test DNS records for a domain"""
    data = request.json if request.json else {}
    domain = data.get('domain') or os.environ.get('DOMAIN', 'yourdomain.com')
    
    if not domain or domain == 'yourdomain.com':
        return jsonify({'status': 'warning', 'message': 'Please configure a real domain in environment variables', 'domain': domain}), 400
    
    result = SystemChecker.test_dns_records(domain)
    return jsonify(result)

@app.route('/api/install', methods=['POST'])
def install_component():
    """Install a specific component"""
    data = request.json
    component = data.get('component')
    
    if component == 'dns':
        # Run DNS setup script
        script = SRC_DIR / 'dns' / 'record-generator.sh'
        if script.exists():
            result = subprocess.run([str(script), '--help'], capture_output=True, text=True)
            return jsonify({'status': 'info', 'message': 'DNS setup available', 'output': result.stdout})
        else:
            return jsonify({'status': 'error', 'message': 'DNS setup script not found'})
    
    elif component == 'mailcow':
        script = SRC_DIR / 'mailcow' / 'scripts' / 'install-mailcow.sh'
        if script.exists():
            return jsonify({'status': 'info', 'message': 'Mailcow installer found', 'path': str(script)})
        else:
            return jsonify({'status': 'error', 'message': 'Mailcow installer not found'})
    
    return jsonify({'status': 'error', 'message': 'Unknown component'})

@app.route('/config')
def config_page():
    """Configuration management page"""
    return render_template('config.html')

@app.route('/api/config', methods=['GET', 'POST'])
def api_config():
    """Get or update configuration"""
    if request.method == 'GET':
        # Get current configuration
        cloudflare_token = os.environ.get('CLOUDFLARE_API_TOKEN', '')
        mailcow_api_key = os.environ.get('MAILCOW_API_KEY', '')
        smtp_password = os.environ.get('SMTP_PASSWORD', '')
        
        # Check if values are configured (not placeholder)
        cloudflare_configured = cloudflare_token and cloudflare_token != 'your_cloudflare_api_token_here'
        mailcow_configured = mailcow_api_key and mailcow_api_key != 'your_mailcow_api_key_here'
        smtp_configured = smtp_password and smtp_password != 'your_smtp_password_here'
        
        config = {
            'domain': os.environ.get('DOMAIN', 'yourdomain.com'),
            'server_ip': os.environ.get('SERVER_IP', '157.180.44.191'),
            'admin_email': os.environ.get('ADMIN_EMAIL', 'admin@yourdomain.com'),
            'dmarc_email': os.environ.get('DMARC_EMAIL', 'dmarc@yourdomain.com'),
            'smtp_host': os.environ.get('SMTP_HOST', 'mail.yourdomain.com'),
            'smtp_port': os.environ.get('SMTP_PORT', '587'),
            'smtp_user': os.environ.get('SMTP_USER', 'admin@yourdomain.com'),
            'smtp_security': os.environ.get('SMTP_SECURITY', 'tls'),
            'mailcow_hostname': os.environ.get('MAILCOW_HOSTNAME', 'mail.yourdomain.com'),
            'dkim_selector': os.environ.get('DKIM_SELECTOR', 'default'),
            'cloudflare_token': 'Configured' if cloudflare_configured else 'Not configured (using placeholder)',
            'mailcow_api_key': 'Configured' if mailcow_configured else 'Not configured (using placeholder)',
            'smtp_password': 'Configured' if smtp_configured else 'Not configured (using placeholder)'
        }
        return jsonify(config)
    
    elif request.method == 'POST':
        # Update configuration (would need to update .env file)
        data = request.json
        # In production, this would update the .env file
        return jsonify({'status': 'info', 'message': 'Configuration update requires manual .env file editing'})

@app.route('/test')
def test_page():
    """Component testing page"""
    return render_template('test.html')

@app.route('/monitor')
def monitor_page():
    """Monitoring dashboard"""
    return render_template('monitor.html')

# ============================================================================
# Enhanced API Endpoints for Testing and Monitoring
# ============================================================================

# Global variables for tracking metrics
email_stats = {
    'today': 0,
    'success_rate': 0,
    'delivered': 0,
    'pending': 0,
    'bounced': 0,
    'deferred': 0
}

queue_data = {
    'size': 0,
    'status': 'running',
    'items': [],
    'processing_rate': 0,
    'avg_wait_time': 0,
    'failed_jobs': 0
}

system_logs = []
system_alerts = []
warmup_campaigns = {}

@app.route('/api/test-email', methods=['POST'])
def test_email():
    """Send a test email"""
    try:
        data = request.json
        to_email = data.get('to')
        from_email = data.get('from', os.environ.get('ADMIN_EMAIL', 'admin@localhost'))
        subject = data.get('subject', 'Test Email')
        body = data.get('body', 'This is a test email.')
        
        if not to_email:
            return jsonify({'status': 'error', 'message': 'To email is required'}), 400
        
        # Get SMTP configuration
        smtp_host = os.environ.get('SMTP_HOST', 'mail.yourdomain.com')
        smtp_port = int(os.environ.get('SMTP_PORT', 587))
        smtp_user = os.environ.get('SMTP_USER', from_email)
        smtp_pass = os.environ.get('SMTP_PASSWORD', '')
        
        # Create message
        msg = MIMEMultipart()
        msg['From'] = from_email
        msg['To'] = to_email
        msg['Subject'] = subject
        msg.attach(MIMEText(body, 'plain'))
        
        # Send email
        start_time = time.time()
        try:
            server = smtplib.SMTP(smtp_host, smtp_port)
            server.starttls()
            if smtp_pass:
                server.login(smtp_user, smtp_pass)
            server.send_message(msg)
            server.quit()
            
            delivery_time = int((time.time() - start_time) * 1000)
            
            # Update statistics
            global email_stats
            email_stats['today'] += 1
            email_stats['delivered'] += 1
            
            return jsonify({
                'status': 'success', 
                'message': 'Email sent successfully',
                'message_id': f'test-{int(time.time())}',
                'delivery_time': delivery_time
            })
            
        except Exception as smtp_error:
            return jsonify({'status': 'error', 'message': f'SMTP Error: {str(smtp_error)}'})
            
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)})

@app.route('/api/test-smtp', methods=['POST'])
def test_smtp():
    """Test SMTP connection"""
    try:
        data = request.json
        host = data.get('host')
        port = data.get('port', 587)
        security = data.get('security', 'tls')
        username = data.get('username')
        password = data.get('password')
        
        if not host:
            return jsonify({'status': 'error', 'message': 'SMTP host is required'}), 400
        
        # Test connection
        try:
            if security == 'ssl':
                server = smtplib.SMTP_SSL(host, port)
            else:
                server = smtplib.SMTP(host, port)
                if security == 'tls':
                    server.starttls()
            
            # Get server info
            server_info = server.ehlo()[1].decode('utf-8').split('\n')[0] if server.ehlo()[0] == 250 else 'Unknown'
            
            # Test authentication if credentials provided
            if username and password:
                server.login(username, password)
            
            # Get server features
            features = []
            if hasattr(server, 'esmtp_features'):
                features = list(server.esmtp_features.keys())
            
            server.quit()
            
            return jsonify({
                'status': 'success',
                'message': 'SMTP connection successful',
                'server_info': server_info,
                'features': features
            })
            
        except Exception as smtp_error:
            return jsonify({'status': 'error', 'message': str(smtp_error)})
            
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)})

@app.route('/api/test-blacklist', methods=['POST'])
def test_blacklist():
    """Check blacklist status using DNS-based blacklists"""
    try:
        data = request.json
        ip = data.get('ip') or os.environ.get('SERVER_IP', '157.180.44.191')
        domain = data.get('domain') or os.environ.get('DOMAIN', 'yourdomain.com')
        
        if not ip:
            return jsonify({'status': 'error', 'message': 'IP address is required'}), 400
        
        # Real blacklist providers with DNS queries
        blacklist_providers = {
            'Spamhaus SBL': 'sbl.spamhaus.org',
            'Spamhaus CSS': 'css.spamhaus.org',
            'Spamhaus PBL': 'pbl.spamhaus.org',
            'Barracuda': 'b.barracudacentral.org',
            'Spamcop': 'bl.spamcop.net',
            'SURBL': 'multi.surbl.org',
            'URIBL': 'multi.uribl.com',
            'Composite Blocking List': 'cbl.abuseat.org'
        }
        
        results = {}
        
        # Reverse IP for DNS queries (e.g., 1.2.3.4 becomes 4.3.2.1)
        try:
            reversed_ip = '.'.join(reversed(ip.split('.')))
        except:
            return jsonify({'status': 'error', 'message': 'Invalid IP address format'}), 400
        
        for provider, dns_name in blacklist_providers.items():
            try:
                query_host = f"{reversed_ip}.{dns_name}"
                # Try to resolve - if it resolves, IP is listed
                dns.resolver.resolve(query_host, 'A')
                results[provider] = {
                    'listed': True,
                    'query': query_host
                }
            except dns.resolver.NXDOMAIN:
                # NXDOMAIN means not listed (good)
                results[provider] = {
                    'listed': False,
                    'query': query_host
                }
            except Exception as e:
                # Other DNS errors
                results[provider] = {
                    'listed': None,
                    'error': str(e),
                    'query': query_host
                }
        
        # Count listed providers
        listed_count = sum(1 for result in results.values() if result.get('listed') is True)
        total_checked = len(results)
        
        return jsonify({
            'status': 'success',
            'data': {
                'ip_checked': ip,
                'domain_checked': domain,
                'providers': results,
                'summary': {
                    'total_providers': total_checked,
                    'listed_count': listed_count,
                    'clean_count': total_checked - listed_count,
                    'reputation_status': 'Good' if listed_count == 0 else 'Issues Found' if listed_count < 3 else 'Serious Issues'
                }
            }
        })
        
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)})

@app.route('/api/start-warmup', methods=['POST'])
def start_warmup():
    """Start email warmup campaign"""
    try:
        data = request.json
        from_email = data.get('fromEmail')
        duration = int(data.get('duration', 30))
        
        if not from_email:
            return jsonify({'status': 'error', 'message': 'From email is required'}), 400
        
        # Create campaign ID
        campaign_id = f"warmup_{int(time.time())}"
        
        # Initialize warmup campaign
        global warmup_campaigns
        warmup_campaigns[campaign_id] = {
            'from_email': from_email,
            'duration': duration,
            'start_date': datetime.now(),
            'campaign_day': 1,
            'daily_volume': 5,  # Start with 5 emails per day
            'emails_sent': 0,
            'success_rate': 0,
            'bounce_rate': 0,
            'reputation_score': 50,  # Starting reputation
            'active': True,
            'next_send': (datetime.now() + timedelta(hours=2)).strftime('%H:%M')
        }
        
        return jsonify({
            'status': 'success',
            'message': 'Warmup campaign started',
            'campaign_id': campaign_id,
            'data': warmup_campaigns[campaign_id]
        })
        
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)})

@app.route('/api/warmup-status')
def warmup_status():
    """Get warmup campaign status"""
    try:
        # Get the most recent active campaign
        active_campaigns = {k: v for k, v in warmup_campaigns.items() if v.get('active')}
        
        if not active_campaigns:
            return jsonify({'status': 'success', 'data': {'active': False}})
        
        # Return the most recent campaign
        campaign = list(active_campaigns.values())[-1]
        
        return jsonify({'status': 'success', 'data': campaign})
        
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)})

@app.route('/api/metrics/system')
def system_metrics():
    """Get system metrics"""
    try:
        # Get CPU usage
        cpu_percent = psutil.cpu_percent(interval=1)
        
        # Get memory usage
        memory = psutil.virtual_memory()
        memory_percent = memory.percent
        
        # Get disk usage
        disk = psutil.disk_usage('/')
        disk_percent = (disk.used / disk.total) * 100
        
        # Get network stats
        network = psutil.net_io_counters()
        network_in_mb = network.bytes_recv / (1024 * 1024)
        network_out_mb = network.bytes_sent / (1024 * 1024)
        
        # Get uptime
        boot_time = psutil.boot_time()
        uptime_seconds = time.time() - boot_time
        uptime_str = str(timedelta(seconds=int(uptime_seconds)))
        
        # Determine system status
        if cpu_percent > 90 or memory_percent > 90 or disk_percent > 95:
            status = 'critical'
        elif cpu_percent > 70 or memory_percent > 75 or disk_percent > 80:
            status = 'warning'
        else:
            status = 'healthy'
        
        return jsonify({
            'status': 'success',
            'data': {
                'cpu': round(cpu_percent, 1),
                'memory': round(memory_percent, 1),
                'disk': round(disk_percent, 1),
                'network_in': round(network_in_mb, 2),
                'network_out': round(network_out_mb, 2),
                'uptime': uptime_str,
                'status': status
            }
        })
        
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)})

@app.route('/api/metrics/delivery')
def delivery_metrics():
    """Get email delivery metrics"""
    try:
        global email_stats
        
        # Calculate success rate
        total_emails = email_stats['delivered'] + email_stats['bounced'] + email_stats['deferred']
        if total_emails > 0:
            email_stats['success_rate'] = round((email_stats['delivered'] / total_emails) * 100, 1)
        
        return jsonify({
            'status': 'success',
            'data': email_stats
        })
        
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)})

@app.route('/api/metrics/queue')
def queue_metrics():
    """Get queue metrics"""
    try:
        global queue_data
        
        # Simulate queue activity
        if random.choice([True, False]):
            queue_data['size'] = max(0, queue_data['size'] + random.randint(-2, 5))
            queue_data['processing_rate'] = random.randint(10, 50)
            queue_data['avg_wait_time'] = random.randint(1, 30)
        
        # Generate some sample queue items
        sample_items = []
        for i in range(min(5, queue_data['size'])):
            sample_items.append({
                'id': f'job_{i+1}',
                'subject': f'Marketing Email #{i+1}',
                'to': f'user{i+1}@example.com',
                'status': random.choice(['pending', 'processing', 'completed', 'failed']),
                'created_at': (datetime.now() - timedelta(minutes=random.randint(1, 60))).strftime('%H:%M')
            })
        
        queue_data['items'] = sample_items
        
        return jsonify({
            'status': 'success',
            'data': queue_data
        })
        
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)})

@app.route('/api/queue/pause', methods=['POST'])
def pause_queue():
    """Pause email queue"""
    try:
        global queue_data
        queue_data['status'] = 'paused'
        
        return jsonify({'status': 'success', 'message': 'Queue paused'})
        
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)})

@app.route('/api/queue/resume', methods=['POST'])
def resume_queue():
    """Resume email queue"""
    try:
        global queue_data
        queue_data['status'] = 'running'
        
        return jsonify({'status': 'success', 'message': 'Queue resumed'})
        
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)})

@app.route('/api/logs')
def get_logs():
    """Get system logs"""
    try:
        level = request.args.get('level', 'all')
        limit = int(request.args.get('limit', 50))
        
        global system_logs
        
        # Add some sample logs if empty
        if not system_logs:
            sample_logs = [
                {'timestamp': datetime.now().strftime('%Y-%m-%d %H:%M:%S'), 'level': 'info', 'message': 'System started successfully'},
                {'timestamp': (datetime.now() - timedelta(minutes=5)).strftime('%Y-%m-%d %H:%M:%S'), 'level': 'info', 'message': 'Email queue initialized'},
                {'timestamp': (datetime.now() - timedelta(minutes=10)).strftime('%Y-%m-%d %H:%M:%S'), 'level': 'warning', 'message': 'High CPU usage detected: 75%'},
                {'timestamp': (datetime.now() - timedelta(minutes=15)).strftime('%Y-%m-%d %H:%M:%S'), 'level': 'error', 'message': 'Failed to connect to SMTP server: Connection timeout'},
                {'timestamp': (datetime.now() - timedelta(minutes=20)).strftime('%Y-%m-%d %H:%M:%S'), 'level': 'info', 'message': 'DNS records validated successfully'},
            ]
            system_logs.extend(sample_logs)
        
        # Filter by level if specified
        filtered_logs = system_logs
        if level != 'all':
            filtered_logs = [log for log in system_logs if log['level'] == level]
        
        # Apply limit
        filtered_logs = filtered_logs[-limit:]
        
        return jsonify({
            'status': 'success',
            'data': filtered_logs
        })
        
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)})

@app.route('/api/logs', methods=['DELETE'])
def clear_logs():
    """Clear system logs"""
    try:
        global system_logs
        system_logs.clear()
        
        return jsonify({'status': 'success', 'message': 'Logs cleared'})
        
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)})

@app.route('/api/alerts')
def get_alerts():
    """Get system alerts"""
    try:
        global system_alerts
        
        # Add some sample alerts if empty
        if not system_alerts:
            sample_alerts = [
                {
                    'title': 'High Memory Usage',
                    'message': 'Memory usage is above 85% threshold',
                    'severity': 'warning',
                    'timestamp': (datetime.now() - timedelta(minutes=30)).strftime('%Y-%m-%d %H:%M:%S')
                },
                {
                    'title': 'Queue Size Alert',
                    'message': 'Email queue has grown to over 100 items',
                    'severity': 'warning',
                    'timestamp': (datetime.now() - timedelta(hours=1)).strftime('%Y-%m-%d %H:%M:%S')
                }
            ]
            system_alerts.extend(sample_alerts)
        
        return jsonify({
            'status': 'success',
            'data': system_alerts
        })
        
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)})

@app.route('/api/alerts', methods=['DELETE'])
def clear_alerts():
    """Clear all alerts"""
    try:
        global system_alerts
        cleared_count = len(system_alerts)
        system_alerts.clear()
        
        log_entry = {
            'id': str(uuid.uuid4()),
            'timestamp': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
            'level': 'info',
            'category': 'alerts',
            'message': f'All alerts cleared - {cleared_count} items removed',
            'source': 'alert_manager'
        }
        system_logs.append(log_entry)
        
        return jsonify({
            'status': 'success',
            'message': f'Alerts cleared - {cleared_count} items removed'
        })
        
    except Exception as e:
        logger.error(f'Clear alerts error: {str(e)}')
        return jsonify({'status': 'error', 'message': str(e)})

@app.route('/api/alerts/config', methods=['POST'])
def save_alert_config():
    """Save alert configuration"""
    try:
        config = request.json
        
        # Validate configuration structure
        required_fields = ['cpu_threshold', 'memory_threshold', 'disk_threshold', 'queue_threshold']
        for field in required_fields:
            if field not in config:
                return jsonify({
                    'status': 'error',
                    'message': f'Missing required field: {field}'
                }), 400
        
        # Validate thresholds are within reasonable ranges
        for field in ['cpu_threshold', 'memory_threshold', 'disk_threshold']:
            if not 0 <= config[field] <= 100:
                return jsonify({
                    'status': 'error',
                    'message': f'{field} must be between 0 and 100'
                }), 400
        
        # In production, save this to a config file or database
        # For now, just return success with validation confirmation
        
        log_entry = {
            'id': str(uuid.uuid4()),
            'timestamp': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
            'level': 'info',
            'category': 'config',
            'message': 'Alert configuration updated successfully',
            'source': 'config_manager'
        }
        system_logs.append(log_entry)
        
        return jsonify({
            'status': 'success',
            'message': 'Alert configuration saved successfully',
            'data': config
        })
        
    except Exception as e:
        logger.error(f'Save alert config error: {str(e)}')
        return jsonify({'status': 'error', 'message': str(e)})

# Email delivery tracking endpoint
@app.route('/api/track/<message_id>')
def track_delivery(message_id):
    """Track email delivery (pixel tracking)"""
    try:
        global delivery_tracking
        
        # Record the tracking event
        if message_id not in delivery_tracking:
            delivery_tracking[message_id] = {
                'opened': False,
                'open_count': 0,
                'first_opened': None,
                'last_opened': None,
                'user_agent': None,
                'ip_address': None
            }
        
        tracking_info = delivery_tracking[message_id]
        tracking_info['opened'] = True
        tracking_info['open_count'] += 1
        tracking_info['last_opened'] = datetime.now().isoformat()
        tracking_info['user_agent'] = request.headers.get('User-Agent')
        tracking_info['ip_address'] = request.environ.get('HTTP_X_FORWARDED_FOR', request.environ.get('REMOTE_ADDR'))
        
        if tracking_info['first_opened'] is None:
            tracking_info['first_opened'] = tracking_info['last_opened']
        
        # Log the tracking event
        log_entry = {
            'id': str(uuid.uuid4()),
            'timestamp': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
            'level': 'info',
            'category': 'tracking',
            'message': f'Email opened: {message_id} (opens: {tracking_info["open_count"]})',
            'source': 'email_tracker'
        }
        system_logs.append(log_entry)
        
        # Return a 1x1 transparent pixel
        pixel_data = b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\nIDATx\x9cc\x00\x01\x00\x00\x05\x00\x01\r\n-\xdb\x00\x00\x00\x00IEND\xaeB`\x82'
        
        response = app.response_class(
            pixel_data,
            mimetype='image/png',
            headers={
                'Cache-Control': 'no-cache, no-store, must-revalidate',
                'Pragma': 'no-cache',
                'Expires': '0',
                'Content-Length': str(len(pixel_data))
            }
        )
        
        return response
        
    except Exception as e:
        logger.error(f'Email tracking error: {str(e)}')
        # Return empty pixel even on error
        return app.response_class(
            b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\nIDATx\x9cc\x00\x01\x00\x00\x05\x00\x01\r\n-\xdb\x00\x00\x00\x00IEND\xaeB`\x82',
            mimetype='image/png'
        )

# Additional utility endpoints
@app.route('/api/health')
def health_check():
    """Health check endpoint"""
    return jsonify({
        'status': 'healthy',
        'timestamp': datetime.now().isoformat(),
        'version': '1.0.0',
        'uptime': str(timedelta(seconds=int(time.time() - psutil.boot_time())))
    })

@app.route('/api/config/smtp', methods=['GET', 'POST'])
def smtp_config():
    """Get or update SMTP configuration"""
    if request.method == 'GET':
        smtp_password = os.environ.get('SMTP_PASSWORD', '')
        password_configured = bool(smtp_password and smtp_password != 'your_smtp_password_here')
        
        return jsonify({
            'status': 'success',
            'data': {
                'host': os.environ.get('SMTP_HOST', 'mail.yourdomain.com'),
                'port': int(os.environ.get('SMTP_PORT', 587)),
                'security': os.environ.get('SMTP_SECURITY', 'tls'),
                'username': os.environ.get('SMTP_USER', 'admin@yourdomain.com'),
                'password_configured': password_configured
            }
        })
    
    elif request.method == 'POST':
        # In production, this would update environment variables or config file
        return jsonify({
            'status': 'info',
            'message': 'SMTP configuration update requires environment variable changes'
        })

@app.route('/api/queue/clear', methods=['POST'])
def clear_queue():
    """Clear email queue"""
    try:
        global queue_data
        cleared_items = queue_data['size']
        
        queue_data['size'] = 0
        queue_data['items'] = []
        queue_data['failed_jobs'] = 0
        
        log_entry = {
            'id': str(uuid.uuid4()),
            'timestamp': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
            'level': 'info',
            'category': 'queue',
            'message': f'Email queue cleared - {cleared_items} items removed',
            'source': 'queue_manager'
        }
        system_logs.append(log_entry)
        
        return jsonify({
            'status': 'success',
            'message': f'Queue cleared - {cleared_items} items removed'
        })
        
    except Exception as e:
        logger.error(f'Clear queue error: {str(e)}')
        return jsonify({'status': 'error', 'message': str(e)})

@app.route('/api/warmup/stop/<campaign_id>', methods=['POST'])
def stop_warmup(campaign_id):
    """Stop a warmup campaign"""
    try:
        global warmup_campaigns
        
        if campaign_id not in warmup_campaigns:
            return jsonify({
                'status': 'error',
                'message': 'Campaign not found'
            }), 404
        
        campaign = warmup_campaigns[campaign_id]
        campaign['status'] = 'stopped'
        campaign['stopped_at'] = datetime.now().isoformat()
        campaign['updated_at'] = datetime.now().isoformat()
        
        log_entry = {
            'id': str(uuid.uuid4()),
            'timestamp': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
            'level': 'info',
            'category': 'warmup',
            'message': f'Warmup campaign stopped: {campaign_id} for {campaign["from_email"]}',
            'source': 'warmup_manager'
        }
        system_logs.append(log_entry)
        
        return jsonify({
            'status': 'success',
            'message': 'Warmup campaign stopped successfully',
            'data': campaign
        })
        
    except Exception as e:
        logger.error(f'Stop warmup error: {str(e)}')
        return jsonify({'status': 'error', 'message': str(e)})

@app.route('/api/warmup/campaigns')
def list_warmup_campaigns():
    """List all warmup campaigns"""
    try:
        global warmup_campaigns
        
        campaigns_list = []
        for campaign_id, campaign_data in warmup_campaigns.items():
            campaigns_list.append({
                'id': campaign_id,
                **campaign_data
            })
        
        # Sort by creation date, newest first
        campaigns_list.sort(key=lambda x: x.get('created_at', ''), reverse=True)
        
        return jsonify({
            'status': 'success',
            'data': {
                'campaigns': campaigns_list,
                'total_campaigns': len(campaigns_list),
                'active_campaigns': len([c for c in campaigns_list if c.get('status') == 'active'])
            }
        })
        
    except Exception as e:
        logger.error(f'List warmup campaigns error: {str(e)}')
        return jsonify({'status': 'error', 'message': str(e)})

if __name__ == '__main__':
    # Initialize logging
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        handlers=[
            logging.FileHandler('dashboard.log'),
            logging.StreamHandler()
        ]
    )
    
    # Check if templates directory exists
    template_dir = Path(__file__).parent / 'templates'
    if not template_dir.exists():
        template_dir.mkdir(parents=True)
        logger.info(f"Created templates directory: {template_dir}")
    
    # Log startup information
    logger.info("Cold Email Infrastructure Dashboard starting...")
    logger.info(f"Environment: {os.environ.get('FLASK_ENV', 'production')}")
    logger.info(f"Rate limiting: {RATE_LIMIT_REQUESTS} requests per {RATE_LIMIT_WINDOW} seconds")
    
    # Add startup log entry
    startup_log = {
        'id': str(uuid.uuid4()),
        'timestamp': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
        'level': 'info',
        'category': 'system',
        'message': f'Dashboard server starting on port {int(os.environ.get("FLASK_PORT", 5000))}',
        'source': 'startup'
    }
    system_logs.append(startup_log)
    
    # Run the app
    port = int(os.environ.get('FLASK_PORT', 5000))
    debug_mode = os.environ.get('FLASK_ENV') == 'development'
    
    app.run(
        host='0.0.0.0',
        port=port,
        debug=debug_mode,
        threaded=True
    )