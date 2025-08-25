#!/usr/bin/env python3
"""
Test script for Cold Email Infrastructure Dashboard API
"""

import requests
import json
import sys
import time

# Base URL for the API
BASE_URL = 'http://localhost:5000'

def test_endpoint(method, endpoint, data=None, expected_status=200):
    """Test an API endpoint"""
    url = f"{BASE_URL}{endpoint}"
    
    try:
        if method.upper() == 'GET':
            response = requests.get(url)
        elif method.upper() == 'POST':
            response = requests.post(url, json=data)
        elif method.upper() == 'DELETE':
            response = requests.delete(url)
        else:
            print(f"❌ Unsupported method: {method}")
            return False
        
        if response.status_code == expected_status:
            print(f"✅ {method.upper()} {endpoint} - Status: {response.status_code}")
            try:
                result = response.json()
                if result.get('status') in ['success', 'info']:
                    return True
                else:
                    print(f"   Response: {result.get('message', 'Unknown error')}")
                    return False
            except:
                return True  # Non-JSON response (like tracking pixel)
        else:
            print(f"❌ {method.upper()} {endpoint} - Expected {expected_status}, got {response.status_code}")
            try:
                print(f"   Error: {response.json()}")
            except:
                print(f"   Error: {response.text}")
            return False
            
    except requests.exceptions.ConnectionError:
        print(f"❌ {method.upper()} {endpoint} - Connection failed (is the server running?)")
        return False
    except Exception as e:
        print(f"❌ {method.upper()} {endpoint} - Error: {str(e)}")
        return False

def main():
    """Run API tests"""
    print("🧪 Testing Cold Email Infrastructure Dashboard API")
    print("=" * 60)
    
    # Test basic endpoints
    tests = [
        # Health and status
        ('GET', '/api/health'),
        ('GET', '/api/status'),
        
        # Metrics
        ('GET', '/api/metrics'),
        ('GET', '/api/metrics/system'),
        ('GET', '/api/metrics/delivery'),
        ('GET', '/api/queue'),
        
        # DNS validation
        ('POST', '/api/validate-spf', {'domain': 'google.com'}),
        ('POST', '/api/validate-dkim', {'domain': 'google.com', 'selector': 'default'}),
        ('POST', '/api/validate-dmarc', {'domain': 'google.com'}),
        
        # SMTP testing (will fail without proper config)
        ('POST', '/api/test-smtp', {
            'host': 'smtp.gmail.com',
            'port': 587,
            'security': 'tls',
            'username': 'test@gmail.com',
            'password': 'invalid'
        }),
        
        # Blacklist checking
        ('POST', '/api/check-blacklist', {'ip': '8.8.8.8', 'domain': 'google.com'}),
        
        # Queue management
        ('POST', '/api/queue/pause'),
        ('POST', '/api/queue/resume'),
        
        # Logs and alerts
        ('GET', '/api/logs'),
        ('GET', '/api/alerts'),
        
        # Configuration
        ('GET', '/api/config/smtp'),
        
        # Warmup campaigns
        ('GET', '/api/warmup/campaigns'),
        ('GET', '/api/warmup/status'),
    ]
    
    passed = 0
    total = len(tests)
    
    for method, endpoint, *args in tests:
        data = args[0] if args else None
        if test_endpoint(method, endpoint, data):
            passed += 1
        time.sleep(0.1)  # Small delay between requests
    
    print("\n" + "=" * 60)
    print(f"📊 Test Results: {passed}/{total} tests passed ({passed/total*100:.1f}%)")
    
    if passed == total:
        print("🎉 All tests passed! API is working correctly.")
        return 0
    else:
        print(f"⚠️  {total - passed} tests failed. Check the server logs for details.")
        return 1

if __name__ == '__main__':
    exit(main())