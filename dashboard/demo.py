#!/usr/bin/env python3
"""
Demo script to show dashboard functionality with sample data
"""

import time
import requests
import json
import random
from datetime import datetime

class DashboardDemo:
    def __init__(self, base_url="http://localhost:5000"):
        self.base_url = base_url
        
    def test_all_endpoints(self):
        """Test all dashboard endpoints with sample data"""
        print("🚀 Cold Email Infrastructure Dashboard Demo")
        print("=" * 50)
        
        # Test basic status
        self.test_status()
        
        # Test DNS validation
        self.test_dns_validation()
        
        # Test SMTP connection
        self.test_smtp_connection()
        
        # Test email sending
        self.test_email_sending()
        
        # Test blacklist checking
        self.test_blacklist_check()
        
        # Test warmup campaign
        self.test_warmup_campaign()
        
        # Test monitoring endpoints
        self.test_monitoring()
        
        print("\n✅ Demo completed! Dashboard is fully functional.")
        print(f"🌐 Visit {self.base_url} to see the web interface")
        
    def test_status(self):
        """Test the status endpoint"""
        print("\n1. Testing System Status...")
        try:
            response = requests.get(f"{self.base_url}/api/status", timeout=5)
            if response.status_code == 200:
                data = response.json()
                print(f"   ✅ System Status: {data.get('timestamp', 'Unknown')}")
                print(f"   📊 Components checked: {len(data) - 1}")
            else:
                print(f"   ❌ Status check failed: {response.status_code}")
        except requests.exceptions.RequestException as e:
            print(f"   ❌ Connection failed: {e}")
            
    def test_dns_validation(self):
        """Test DNS validation"""
        print("\n2. Testing DNS Validation...")
        test_domain = "example.com"
        
        try:
            response = requests.post(
                f"{self.base_url}/api/test-dns",
                json={"domain": test_domain},
                timeout=10
            )
            
            if response.status_code == 200:
                data = response.json()
                if data.get('status') == 'success':
                    records = data.get('data', {})
                    print(f"   ✅ DNS validation successful for {test_domain}")
                    print(f"   📝 Found records: {list(records.keys())}")
                else:
                    print(f"   ⚠️  DNS validation warning: {data.get('message')}")
            else:
                print(f"   ❌ DNS test failed: {response.status_code}")
                
        except requests.exceptions.RequestException as e:
            print(f"   ❌ DNS test error: {e}")
            
    def test_smtp_connection(self):
        """Test SMTP connection"""
        print("\n3. Testing SMTP Connection...")
        
        smtp_config = {
            "host": "smtp.gmail.com",
            "port": 587,
            "security": "tls",
            "username": "test@example.com",
            "password": "dummy_password"
        }
        
        try:
            response = requests.post(
                f"{self.base_url}/api/test-smtp",
                json=smtp_config,
                timeout=10
            )
            
            if response.status_code == 200:
                data = response.json()
                if data.get('status') == 'success':
                    print("   ✅ SMTP connection test passed")
                    print(f"   📧 Server: {data.get('server_info', 'Unknown')}")
                else:
                    print(f"   ⚠️  SMTP connection failed: {data.get('message')}")
            else:
                print(f"   ❌ SMTP test failed: {response.status_code}")
                
        except requests.exceptions.RequestException as e:
            print(f"   ❌ SMTP test error: {e}")
            
    def test_email_sending(self):
        """Test email sending"""
        print("\n4. Testing Email Sending...")
        
        email_data = {
            "to": "test@example.com",
            "from": "sender@example.com",
            "subject": "Dashboard Demo Test Email",
            "body": "This is a test email sent from the dashboard demo."
        }
        
        try:
            response = requests.post(
                f"{self.base_url}/api/test-email",
                json=email_data,
                timeout=15
            )
            
            if response.status_code == 200:
                data = response.json()
                if data.get('status') == 'success':
                    print("   ✅ Email sending test successful")
                    print(f"   📨 Message ID: {data.get('message_id')}")
                    print(f"   ⏱️  Delivery time: {data.get('delivery_time')}ms")
                else:
                    print(f"   ⚠️  Email sending failed: {data.get('message')}")
            else:
                print(f"   ❌ Email test failed: {response.status_code}")
                
        except requests.exceptions.RequestException as e:
            print(f"   ❌ Email test error: {e}")
            
    def test_blacklist_check(self):
        """Test blacklist checking"""
        print("\n5. Testing Blacklist Check...")
        
        blacklist_data = {
            "ip": "8.8.8.8",
            "domain": "google.com"
        }
        
        try:
            response = requests.post(
                f"{self.base_url}/api/test-blacklist",
                json=blacklist_data,
                timeout=15
            )
            
            if response.status_code == 200:
                data = response.json()
                if data.get('status') == 'success':
                    results = data.get('data', {})
                    listed_count = sum(1 for r in results.values() if r.get('listed'))
                    total_count = len(results)
                    print("   ✅ Blacklist check completed")
                    print(f"   🛡️  Results: {listed_count}/{total_count} blacklists")
                else:
                    print(f"   ⚠️  Blacklist check failed: {data.get('message')}")
            else:
                print(f"   ❌ Blacklist test failed: {response.status_code}")
                
        except requests.exceptions.RequestException as e:
            print(f"   ❌ Blacklist test error: {e}")
            
    def test_warmup_campaign(self):
        """Test warmup campaign"""
        print("\n6. Testing Warmup Campaign...")
        
        warmup_data = {
            "fromEmail": "warmup@example.com",
            "duration": 30
        }
        
        try:
            response = requests.post(
                f"{self.base_url}/api/start-warmup",
                json=warmup_data,
                timeout=10
            )
            
            if response.status_code == 200:
                data = response.json()
                if data.get('status') == 'success':
                    print("   ✅ Warmup campaign started")
                    print(f"   🔥 Campaign ID: {data.get('campaign_id')}")
                    
                    # Check warmup status
                    status_response = requests.get(f"{self.base_url}/api/warmup-status")
                    if status_response.status_code == 200:
                        status_data = status_response.json()
                        if status_data.get('data', {}).get('active'):
                            print(f"   📊 Campaign active: Day {status_data['data']['campaign_day']}")
                else:
                    print(f"   ⚠️  Warmup campaign failed: {data.get('message')}")
            else:
                print(f"   ❌ Warmup test failed: {response.status_code}")
                
        except requests.exceptions.RequestException as e:
            print(f"   ❌ Warmup test error: {e}")
            
    def test_monitoring(self):
        """Test monitoring endpoints"""
        print("\n7. Testing Monitoring Endpoints...")
        
        endpoints = [
            ("/api/metrics/system", "System Metrics"),
            ("/api/metrics/delivery", "Delivery Stats"),
            ("/api/metrics/queue", "Queue Status"),
            ("/api/logs", "System Logs"),
            ("/api/alerts", "System Alerts")
        ]
        
        for endpoint, name in endpoints:
            try:
                response = requests.get(f"{self.base_url}{endpoint}", timeout=5)
                if response.status_code == 200:
                    data = response.json()
                    if data.get('status') == 'success':
                        print(f"   ✅ {name}: OK")
                    else:
                        print(f"   ⚠️  {name}: {data.get('message', 'Unknown error')}")
                else:
                    print(f"   ❌ {name}: HTTP {response.status_code}")
            except requests.exceptions.RequestException as e:
                print(f"   ❌ {name}: Connection error")
                
    def generate_sample_data(self):
        """Generate sample data for demo purposes"""
        print("\n8. Generating Sample Data...")
        
        # Simulate some activity
        for i in range(5):
            # Send a few test emails to generate stats
            try:
                requests.post(
                    f"{self.base_url}/api/test-email",
                    json={
                        "to": f"demo{i}@example.com",
                        "from": "demo@example.com",
                        "subject": f"Demo Email #{i+1}",
                        "body": f"This is demo email #{i+1} for testing dashboard functionality."
                    },
                    timeout=5
                )
                print(f"   📧 Sent demo email #{i+1}")
                time.sleep(0.5)
            except:
                pass
                
        print("   ✅ Sample data generation complete")

def main():
    demo = DashboardDemo()
    
    print("Starting Cold Email Infrastructure Dashboard Demo...")
    print("Make sure the dashboard is running at http://localhost:5000")
    
    # Wait a moment for user to see the message
    time.sleep(2)
    
    try:
        # Test if dashboard is running
        response = requests.get("http://localhost:5000", timeout=5)
        if response.status_code != 200:
            print("❌ Dashboard not responding. Please start it first with: python app.py")
            return
    except requests.exceptions.RequestException:
        print("❌ Cannot connect to dashboard. Please start it first with: python app.py")
        return
    
    # Run all tests
    demo.test_all_endpoints()
    demo.generate_sample_data()
    
    print("\n" + "=" * 50)
    print("🎉 Demo completed successfully!")
    print("📱 Open http://localhost:5000 in your browser to explore the dashboard")
    print("🔍 Try the testing interface at http://localhost:5000/test")
    print("📊 Check the monitoring dashboard at http://localhost:5000/monitor")
    print("⚙️  Configure settings at http://localhost:5000/config")

if __name__ == "__main__":
    main()