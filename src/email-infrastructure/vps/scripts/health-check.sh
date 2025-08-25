#!/bin/bash

# VPS Health Check Script for Cold Email Infrastructure
# Monitors system health, network connectivity, and mail server readiness
# Author: Cold Email Infrastructure Setup Agent
# Version: 1.0.0

set -euo pipefail

# =============================================================================
# CONFIGURATION AND CONSTANTS
# =============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BASE_DIR="$(dirname "$SCRIPT_DIR")"
readonly LOG_DIR="$BASE_DIR/logs"
readonly CONFIG_DIR="$BASE_DIR/config"
readonly MONITORING_DIR="$BASE_DIR/monitoring"

readonly HEALTH_LOG="$LOG_DIR/health-check-$(date +%Y%m%d_%H%M%S).log"
readonly STATUS_FILE="$MONITORING_DIR/vps-status.json"
readonly ALERT_THRESHOLDS_FILE="$CONFIG_DIR/alert-thresholds.yaml"

# Health check thresholds (defaults)
readonly CPU_THRESHOLD=80
readonly MEMORY_THRESHOLD=85
readonly DISK_THRESHOLD=90
readonly LOAD_THRESHOLD=5.0

# Mail server ports to check
readonly MAIL_PORTS=(25 587 465 143 993 110 995)
readonly WEB_PORTS=(80 443)

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$HEALTH_LOG"
}

log_info() {
    log "INFO" "$@"
}

log_warn() {
    log "WARN" "$@"
}

log_error() {
    log "ERROR" "$@"
}

log_success() {
    log "SUCCESS" "$@"
}

# Initialize health check results
init_health_results() {
    cat > "$STATUS_FILE" << 'EOF'
{
  "timestamp": "",
  "overall_status": "unknown",
  "checks": {
    "system": {
      "status": "unknown",
      "cpu_usage": 0,
      "memory_usage": 0,
      "disk_usage": 0,
      "load_average": 0,
      "uptime": ""
    },
    "network": {
      "status": "unknown",
      "interfaces": [],
      "connectivity": {
        "external": false,
        "dns": false
      }
    },
    "services": {
      "status": "unknown",
      "docker": false,
      "ufw": false,
      "fail2ban": false
    },
    "ports": {
      "status": "unknown",
      "mail_ports": {},
      "web_ports": {}
    },
    "security": {
      "status": "unknown",
      "failed_login_attempts": 0,
      "active_connections": 0
    }
  },
  "alerts": [],
  "recommendations": []
}
EOF
}

# =============================================================================
# SYSTEM HEALTH CHECKS
# =============================================================================

check_system_resources() {
    log_info "Checking system resources..."
    
    local cpu_usage memory_usage disk_usage load_avg uptime_info
    local alerts=()
    
    # CPU usage (1-minute average)
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')
    cpu_usage=${cpu_usage%.*}  # Remove decimal part
    
    # Memory usage
    memory_usage=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')
    
    # Disk usage (root partition)
    disk_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    
    # Load average (1-minute)
    load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $1}' | xargs)
    
    # Uptime
    uptime_info=$(uptime -p)
    
    # Check thresholds and generate alerts
    if (( cpu_usage > CPU_THRESHOLD )); then
        alerts+=("High CPU usage: ${cpu_usage}%")
    fi
    
    if (( memory_usage > MEMORY_THRESHOLD )); then
        alerts+=("High memory usage: ${memory_usage}%")
    fi
    
    if (( disk_usage > DISK_THRESHOLD )); then
        alerts+=("High disk usage: ${disk_usage}%")
    fi
    
    if (( $(echo "$load_avg > $LOAD_THRESHOLD" | bc -l 2>/dev/null || echo 0) )); then
        alerts+=("High load average: $load_avg")
    fi
    
    # Update status file
    python3 << EOF
import json
import sys

try:
    with open('$STATUS_FILE', 'r') as f:
        status = json.load(f)
    
    status['checks']['system'] = {
        'status': 'healthy' if not $([[ ${#alerts[@]} -eq 0 ]] && echo 'True' || echo 'False') else 'warning',
        'cpu_usage': $cpu_usage,
        'memory_usage': $memory_usage,
        'disk_usage': $disk_usage,
        'load_average': $load_avg,
        'uptime': '$uptime_info'
    }
    
    # Add alerts
    for alert in [$(printf "'%s'," "${alerts[@]}")]:
        if alert and alert not in status['alerts']:
            status['alerts'].append(alert)
    
    with open('$STATUS_FILE', 'w') as f:
        json.dump(status, f, indent=2)

except Exception as e:
    print(f"Error updating system status: {e}")
    sys.exit(1)
EOF

    if [[ ${#alerts[@]} -eq 0 ]]; then
        log_success "System resources healthy - CPU: ${cpu_usage}%, Memory: ${memory_usage}%, Disk: ${disk_usage}%, Load: ${load_avg}"
    else
        log_warn "System resource alerts: ${alerts[*]}"
    fi
}

check_network_interfaces() {
    log_info "Checking network interfaces..."
    
    local interfaces=()
    local status="healthy"
    
    # Get all active interfaces
    while IFS= read -r interface; do
        if [[ -n "$interface" && "$interface" != "lo" ]]; then
            local ip_addr state
            ip_addr=$(ip addr show "$interface" | grep "inet " | awk '{print $2}' | cut -d/ -f1)
            state=$(ip link show "$interface" | grep -o "state [A-Z]*" | awk '{print $2}')
            
            if [[ "$state" == "UP" && -n "$ip_addr" ]]; then
                interfaces+=("{\"name\": \"$interface\", \"ip\": \"$ip_addr\", \"state\": \"$state\"}")
            else
                status="warning"
                log_warn "Interface $interface is not properly configured"
            fi
        fi
    done <<< "$(ip -o link show | awk -F': ' '{print $2}' | cut -d'@' -f1)"
    
    # Check external connectivity
    local external_connectivity=false
    local dns_connectivity=false
    
    if ping -c1 -W3 8.8.8.8 &>/dev/null; then
        external_connectivity=true
        log_success "External connectivity test passed"
    else
        log_warn "External connectivity test failed"
        status="warning"
    fi
    
    if nslookup google.com 8.8.8.8 &>/dev/null; then
        dns_connectivity=true
        log_success "DNS resolution test passed"
    else
        log_warn "DNS resolution test failed"
        status="warning"
    fi
    
    # Update status file
    python3 << EOF
import json

try:
    with open('$STATUS_FILE', 'r') as f:
        status = json.load(f)
    
    interfaces_list = [$(IFS=,; echo "${interfaces[*]}")]
    
    status['checks']['network'] = {
        'status': '$status',
        'interfaces': interfaces_list,
        'connectivity': {
            'external': $external_connectivity,
            'dns': $dns_connectivity
        }
    }
    
    with open('$STATUS_FILE', 'w') as f:
        json.dump(status, f, indent=2)

except Exception as e:
    print(f"Error updating network status: {e}")
EOF
}

check_services() {
    log_info "Checking essential services..."
    
    local docker_status=false
    local ufw_status=false
    local fail2ban_status=false
    local overall_status="healthy"
    
    # Check Docker
    if systemctl is-active --quiet docker; then
        docker_status=true
        log_success "Docker service is running"
    else
        log_warn "Docker service is not running"
        overall_status="warning"
    fi
    
    # Check UFW
    if systemctl is-active --quiet ufw; then
        ufw_status=true
        log_success "UFW firewall is active"
    else
        log_warn "UFW firewall is not active"
        overall_status="warning"
    fi
    
    # Check Fail2Ban
    if systemctl is-active --quiet fail2ban; then
        fail2ban_status=true
        log_success "Fail2Ban service is running"
    else
        log_warn "Fail2Ban service is not running"
        overall_status="warning"
    fi
    
    # Update status file
    python3 << EOF
import json

try:
    with open('$STATUS_FILE', 'r') as f:
        status = json.load(f)
    
    status['checks']['services'] = {
        'status': '$overall_status',
        'docker': $docker_status,
        'ufw': $ufw_status,
        'fail2ban': $fail2ban_status
    }
    
    with open('$STATUS_FILE', 'w') as f:
        json.dump(status, f, indent=2)

except Exception as e:
    print(f"Error updating services status: {e}")
EOF
}

check_ports() {
    log_info "Checking mail server and web ports..."
    
    local mail_ports_status="{}"
    local web_ports_status="{}"
    local overall_status="healthy"
    
    # Check mail ports
    for port in "${MAIL_PORTS[@]}"; do
        if ss -tuln | grep -q ":$port "; then
            log_success "Port $port is open and listening"
            mail_ports_status=$(echo "$mail_ports_status" | jq ". + {\"$port\": true}")
        else
            log_info "Port $port is not listening (may be normal if service not started)"
            mail_ports_status=$(echo "$mail_ports_status" | jq ". + {\"$port\": false}")
        fi
    done
    
    # Check web ports
    for port in "${WEB_PORTS[@]}"; do
        if ss -tuln | grep -q ":$port "; then
            log_success "Port $port is open and listening"
            web_ports_status=$(echo "$web_ports_status" | jq ". + {\"$port\": true}")
        else
            log_info "Port $port is not listening"
            web_ports_status=$(echo "$web_ports_status" | jq ". + {\"$port\": false}")
        fi
    done
    
    # Update status file
    python3 << EOF
import json

try:
    with open('$STATUS_FILE', 'r') as f:
        status = json.load(f)
    
    status['checks']['ports'] = {
        'status': '$overall_status',
        'mail_ports': $mail_ports_status,
        'web_ports': $web_ports_status
    }
    
    with open('$STATUS_FILE', 'w') as f:
        json.dump(status, f, indent=2)

except Exception as e:
    print(f"Error updating ports status: {e}")
EOF
}

check_security() {
    log_info "Checking security status..."
    
    local failed_attempts=0
    local active_connections=0
    local overall_status="healthy"
    
    # Count failed SSH login attempts in last hour
    if [[ -f /var/log/auth.log ]]; then
        failed_attempts=$(grep "$(date -d '1 hour ago' '+%b %d %H')" /var/log/auth.log 2>/dev/null | grep -c "Failed password" || echo 0)
    fi
    
    # Count active SSH connections
    active_connections=$(ss -t | grep -c ssh || echo 0)
    
    # Check for high number of failed attempts
    if (( failed_attempts > 10 )); then
        log_warn "High number of failed SSH attempts in last hour: $failed_attempts"
        overall_status="warning"
    fi
    
    # Update status file
    python3 << EOF
import json

try:
    with open('$STATUS_FILE', 'r') as f:
        status = json.load(f)
    
    status['checks']['security'] = {
        'status': '$overall_status',
        'failed_login_attempts': $failed_attempts,
        'active_connections': $active_connections
    }
    
    with open('$STATUS_FILE', 'w') as f:
        json.dump(status, f, indent=2)

except Exception as e:
    print(f"Error updating security status: {e}")
EOF
    
    log_info "Failed login attempts (last hour): $failed_attempts"
    log_info "Active SSH connections: $active_connections"
}

# =============================================================================
# HEALTH CHECK ORCHESTRATION
# =============================================================================

generate_recommendations() {
    log_info "Generating system recommendations..."
    
    python3 << 'EOF'
import json

try:
    with open(os.environ['STATUS_FILE'], 'r') as f:
        status = json.load(f)
    
    recommendations = []
    checks = status['checks']
    
    # System recommendations
    sys_check = checks.get('system', {})
    if sys_check.get('cpu_usage', 0) > 70:
        recommendations.append("Consider optimizing CPU-intensive processes")
    if sys_check.get('memory_usage', 0) > 80:
        recommendations.append("Consider adding more RAM or optimizing memory usage")
    if sys_check.get('disk_usage', 0) > 85:
        recommendations.append("Clean up disk space or expand storage")
    
    # Network recommendations
    net_check = checks.get('network', {})
    if not net_check.get('connectivity', {}).get('external', False):
        recommendations.append("Check internet connectivity and routing")
    if not net_check.get('connectivity', {}).get('dns', False):
        recommendations.append("Verify DNS server configuration")
    
    # Service recommendations
    svc_check = checks.get('services', {})
    if not svc_check.get('docker', False):
        recommendations.append("Start Docker service for mail infrastructure")
    if not svc_check.get('ufw', False):
        recommendations.append("Enable UFW firewall for security")
    if not svc_check.get('fail2ban', False):
        recommendations.append("Start Fail2Ban service for intrusion prevention")
    
    # Security recommendations
    sec_check = checks.get('security', {})
    if sec_check.get('failed_login_attempts', 0) > 5:
        recommendations.append("Review SSH security configuration")
    
    # Update status with recommendations
    status['recommendations'] = recommendations
    
    with open(os.environ['STATUS_FILE'], 'w') as f:
        json.dump(status, f, indent=2)
    
    if recommendations:
        print("System recommendations:")
        for i, rec in enumerate(recommendations, 1):
            print(f"  {i}. {rec}")
    else:
        print("No specific recommendations at this time.")

except Exception as e:
    print(f"Error generating recommendations: {e}")
EOF
}

calculate_overall_status() {
    python3 << 'EOF'
import json
import os
from datetime import datetime

try:
    with open(os.environ['STATUS_FILE'], 'r') as f:
        status = json.load(f)
    
    checks = status['checks']
    overall_status = "healthy"
    
    # Check each component status
    for component, check_data in checks.items():
        if isinstance(check_data, dict) and 'status' in check_data:
            if check_data['status'] == 'warning':
                overall_status = "warning"
            elif check_data['status'] == 'error':
                overall_status = "error"
                break  # Error is the worst status
    
    # Update timestamp and overall status
    status['timestamp'] = datetime.now().isoformat()
    status['overall_status'] = overall_status
    
    with open(os.environ['STATUS_FILE'], 'w') as f:
        json.dump(status, f, indent=2)
    
    print(f"Overall system status: {overall_status.upper()}")

except Exception as e:
    print(f"Error calculating overall status: {e}")
EOF
}

display_health_summary() {
    log_info "=== VPS Health Check Summary ==="
    
    if [[ -f "$STATUS_FILE" ]]; then
        python3 << 'EOF'
import json
import os

try:
    with open(os.environ['STATUS_FILE'], 'r') as f:
        status = json.load(f)
    
    print(f"Timestamp: {status.get('timestamp', 'Unknown')}")
    print(f"Overall Status: {status.get('overall_status', 'Unknown').upper()}")
    print()
    
    checks = status.get('checks', {})
    
    # System status
    sys_check = checks.get('system', {})
    print(f"System Resources: {sys_check.get('status', 'Unknown').upper()}")
    print(f"  CPU Usage: {sys_check.get('cpu_usage', 0)}%")
    print(f"  Memory Usage: {sys_check.get('memory_usage', 0)}%")
    print(f"  Disk Usage: {sys_check.get('disk_usage', 0)}%")
    print(f"  Load Average: {sys_check.get('load_average', 0)}")
    print(f"  Uptime: {sys_check.get('uptime', 'Unknown')}")
    print()
    
    # Network status
    net_check = checks.get('network', {})
    print(f"Network: {net_check.get('status', 'Unknown').upper()}")
    interfaces = net_check.get('interfaces', [])
    print(f"  Active Interfaces: {len(interfaces)}")
    for iface in interfaces:
        print(f"    {iface.get('name', 'Unknown')}: {iface.get('ip', 'No IP')} ({iface.get('state', 'Unknown')})")
    connectivity = net_check.get('connectivity', {})
    print(f"  External Connectivity: {'✓' if connectivity.get('external') else '✗'}")
    print(f"  DNS Resolution: {'✓' if connectivity.get('dns') else '✗'}")
    print()
    
    # Services status
    svc_check = checks.get('services', {})
    print(f"Services: {svc_check.get('status', 'Unknown').upper()}")
    print(f"  Docker: {'✓' if svc_check.get('docker') else '✗'}")
    print(f"  UFW Firewall: {'✓' if svc_check.get('ufw') else '✗'}")
    print(f"  Fail2Ban: {'✓' if svc_check.get('fail2ban') else '✗'}")
    print()
    
    # Ports status
    ports_check = checks.get('ports', {})
    print(f"Ports: {ports_check.get('status', 'Unknown').upper()}")
    mail_ports = ports_check.get('mail_ports', {})
    web_ports = ports_check.get('web_ports', {})
    print(f"  Mail Ports Open: {sum(1 for v in mail_ports.values() if v)}/{len(mail_ports)}")
    print(f"  Web Ports Open: {sum(1 for v in web_ports.values() if v)}/{len(web_ports)}")
    print()
    
    # Security status
    sec_check = checks.get('security', {})
    print(f"Security: {sec_check.get('status', 'Unknown').upper()}")
    print(f"  Failed Login Attempts (1h): {sec_check.get('failed_login_attempts', 0)}")
    print(f"  Active SSH Connections: {sec_check.get('active_connections', 0)}")
    print()
    
    # Alerts
    alerts = status.get('alerts', [])
    if alerts:
        print("ALERTS:")
        for alert in alerts:
            print(f"  ⚠ {alert}")
        print()
    
    # Recommendations
    recommendations = status.get('recommendations', [])
    if recommendations:
        print("RECOMMENDATIONS:")
        for i, rec in enumerate(recommendations, 1):
            print(f"  {i}. {rec}")

except Exception as e:
    print(f"Error displaying health summary: {e}")
EOF
    else
        log_error "Status file not found: $STATUS_FILE"
    fi
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    local quiet_mode=false
    local json_output=false
    
    # Parse command line options
    while [[ $# -gt 0 ]]; do
        case $1 in
            -q|--quiet)
                quiet_mode=true
                shift
                ;;
            -j|--json)
                json_output=true
                shift
                ;;
            -h|--help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  -q, --quiet    Quiet mode (no verbose output)"
                echo "  -j, --json     Output results in JSON format"
                echo "  -h, --help     Show this help message"
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    if [[ "$quiet_mode" == false ]]; then
        log_info "Starting VPS health check..."
    fi
    
    # Create directories if they don't exist
    mkdir -p "$LOG_DIR" "$MONITORING_DIR"
    
    # Initialize health results
    init_health_results
    
    # Run all health checks
    check_system_resources
    check_network_interfaces
    check_services
    check_ports
    check_security
    
    # Generate analysis
    generate_recommendations
    calculate_overall_status
    
    # Output results
    if [[ "$json_output" == true ]]; then
        cat "$STATUS_FILE"
    elif [[ "$quiet_mode" == false ]]; then
        display_health_summary
        log_info "Health check completed. Status file: $STATUS_FILE"
        log_info "Log file: $HEALTH_LOG"
    fi
    
    # Set appropriate exit code
    overall_status=$(python3 -c "import json; print(json.load(open('$STATUS_FILE'))['overall_status'])")
    case "$overall_status" in
        "healthy") exit 0 ;;
        "warning") exit 1 ;;
        "error") exit 2 ;;
        *) exit 3 ;;
    esac
}

# =============================================================================
# SCRIPT ENTRY POINT
# =============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi