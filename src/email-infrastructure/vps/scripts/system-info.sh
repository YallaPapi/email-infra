#!/bin/bash

# System Information Script for Cold Email Infrastructure VPS
# Provides comprehensive system information and diagnostics
# Author: Cold Email Infrastructure Setup Agent
# Version: 1.0.0

set -euo pipefail

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

print_header() {
    local title="$1"
    local length=${#title}
    local line=$(printf "%*s" $((length + 4)) | tr ' ' '=')
    echo
    echo "$line"
    echo "= $title ="
    echo "$line"
    echo
}

print_section() {
    local title="$1"
    echo
    echo "--- $title ---"
}

check_command() {
    local cmd="$1"
    command -v "$cmd" >/dev/null 2>&1
}

safe_exec() {
    local cmd="$1"
    if eval "$cmd" 2>/dev/null; then
        return 0
    else
        echo "Command failed or not available: $cmd"
        return 1
    fi
}

# =============================================================================
# SYSTEM INFORMATION FUNCTIONS
# =============================================================================

show_system_overview() {
    print_header "SYSTEM OVERVIEW"
    
    echo "Hostname: $(hostname -f 2>/dev/null || hostname)"
    echo "Date: $(date)"
    echo "Timezone: $(timedatectl show --property=Timezone --value 2>/dev/null || date +%Z)"
    echo "Uptime: $(uptime -p 2>/dev/null || uptime)"
    
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "OS: $PRETTY_NAME"
        echo "Version: $VERSION"
        echo "ID: $ID"
    fi
    
    echo "Kernel: $(uname -r)"
    echo "Architecture: $(uname -m)"
    
    if check_command lscpu; then
        echo "CPU: $(lscpu | grep 'Model name' | cut -d':' -f2 | xargs)"
        echo "CPU Cores: $(nproc)"
    fi
    
    echo "Total Memory: $(free -h | grep Mem | awk '{print $2}')"
}

show_hardware_info() {
    print_header "HARDWARE INFORMATION"
    
    if check_command lscpu; then
        print_section "CPU Information"
        lscpu | grep -E "(Architecture|CPU|Thread|Socket|Core|Model|Stepping|BogoMIPS|Cache)"
    fi
    
    print_section "Memory Information"
    free -h
    echo
    if [[ -f /proc/meminfo ]]; then
        echo "Detailed Memory Info:"
        head -20 /proc/meminfo
    fi
    
    print_section "Disk Information"
    df -h
    echo
    if check_command lsblk; then
        echo "Block Devices:"
        lsblk
    fi
    
    if check_command fdisk && [[ $EUID -eq 0 ]]; then
        echo
        echo "Disk Partitions:"
        fdisk -l 2>/dev/null | grep -E "(Disk /dev/|Device.*Start)" | head -20
    fi
}

show_network_info() {
    print_header "NETWORK INFORMATION"
    
    print_section "Network Interfaces"
    if check_command ip; then
        ip addr show
    else
        ifconfig 2>/dev/null || echo "No network interface information available"
    fi
    
    print_section "Routing Table"
    if check_command ip; then
        ip route show
    else
        route -n 2>/dev/null || echo "No routing information available"
    fi
    
    print_section "DNS Configuration"
    if [[ -f /etc/resolv.conf ]]; then
        echo "DNS Servers:"
        cat /etc/resolv.conf
    fi
    
    print_section "Network Connectivity Test"
    echo -n "Internet connectivity (ping 8.8.8.8): "
    if ping -c1 -W3 8.8.8.8 &>/dev/null; then
        echo "✓ Available"
    else
        echo "✗ Not available"
    fi
    
    echo -n "DNS resolution (google.com): "
    if nslookup google.com 8.8.8.8 &>/dev/null; then
        echo "✓ Working"
    else
        echo "✗ Not working"
    fi
    
    print_section "Active Network Connections"
    if check_command ss; then
        echo "Listening services:"
        ss -tuln | head -20
        echo
        echo "Established connections:"
        ss -tupn | grep ESTAB | head -10
    elif check_command netstat; then
        echo "Listening services:"
        netstat -tuln | head -20
        echo
        echo "Established connections:"
        netstat -tupn | grep ESTABLISHED | head -10
    fi
}

show_services_info() {
    print_header "SERVICES INFORMATION"
    
    print_section "System Services Status"
    if check_command systemctl; then
        echo "Failed services:"
        systemctl --failed --no-legend 2>/dev/null || echo "No failed services found"
        
        echo
        echo "Key services status:"
        for service in docker ufw fail2ban ssh nginx apache2 postfix dovecot; do
            if systemctl list-unit-files | grep -q "^$service.service"; then
                status=$(systemctl is-active "$service" 2>/dev/null || echo "not-found")
                enabled=$(systemctl is-enabled "$service" 2>/dev/null || echo "not-found")
                printf "%-12s: %s (%s)\n" "$service" "$status" "$enabled"
            fi
        done
    fi
    
    print_section "Running Processes (Top 10 by CPU)"
    ps aux --sort=-%cpu | head -11
    
    print_section "Running Processes (Top 10 by Memory)"
    ps aux --sort=-%mem | head -11
}

show_security_info() {
    print_header "SECURITY INFORMATION"
    
    print_section "Firewall Status"
    if check_command ufw; then
        ufw status verbose 2>/dev/null || echo "UFW not configured or available"
    fi
    
    if check_command iptables && [[ $EUID -eq 0 ]]; then
        echo
        echo "IPTables rules (first 20):"
        iptables -L -n | head -20 2>/dev/null || echo "Cannot access iptables"
    fi
    
    print_section "Authentication Logs (Last 10 SSH attempts)"
    if [[ -f /var/log/auth.log ]]; then
        grep "sshd" /var/log/auth.log | tail -10 2>/dev/null || echo "No SSH logs found"
    elif [[ -f /var/log/secure ]]; then
        grep "sshd" /var/log/secure | tail -10 2>/dev/null || echo "No SSH logs found"
    fi
    
    print_section "Fail2Ban Status"
    if check_command fail2ban-client; then
        echo "Fail2Ban status:"
        fail2ban-client status 2>/dev/null || echo "Fail2Ban not available"
        
        echo
        echo "Active jails:"
        fail2ban-client status 2>/dev/null | grep "Jail list:" | cut -d: -f2 | xargs -n1 | while read jail; do
            if [[ -n "$jail" ]]; then
                echo "  $jail:"
                fail2ban-client status "$jail" 2>/dev/null | grep -E "(Currently failed|Currently banned)" || true
            fi
        done
    fi
    
    print_section "User Sessions"
    echo "Currently logged in users:"
    who 2>/dev/null || echo "No session information available"
    
    echo
    echo "Last 10 logins:"
    last -10 2>/dev/null || echo "No login history available"
}

show_mail_server_info() {
    print_header "MAIL SERVER INFORMATION"
    
    print_section "Mail Server Ports"
    echo "Checking standard mail server ports:"
    for port in 25 587 465 143 993 110 995; do
        printf "Port %3s: " "$port"
        if ss -tuln 2>/dev/null | grep -q ":$port "; then
            echo "✓ Listening"
        else
            echo "✗ Not listening"
        fi
    done
    
    print_section "Mail Service Status"
    for service in postfix dovecot exim4 sendmail; do
        if systemctl list-unit-files 2>/dev/null | grep -q "^$service.service"; then
            status=$(systemctl is-active "$service" 2>/dev/null)
            printf "%-12s: %s\n" "$service" "$status"
        fi
    done
    
    print_section "Mail Logs (Last 10 entries)"
    if [[ -f /var/log/mail.log ]]; then
        tail -10 /var/log/mail.log 2>/dev/null || echo "No mail logs found"
    elif [[ -f /var/log/maillog ]]; then
        tail -10 /var/log/maillog 2>/dev/null || echo "No mail logs found"
    else
        echo "No mail log files found"
    fi
    
    print_section "DNS Records Check"
    if check_command dig; then
        hostname=$(hostname -f 2>/dev/null || hostname)
        echo "Checking DNS records for $hostname:"
        
        echo -n "A record: "
        dig +short A "$hostname" 2>/dev/null || echo "Not found"
        
        echo -n "MX record: "
        dig +short MX "$hostname" 2>/dev/null || echo "Not found"
        
        echo -n "PTR record (reverse DNS): "
        primary_ip=$(ip route get 8.8.8.8 | grep -oP 'src \K[^ ]+' 2>/dev/null || echo "unknown")
        if [[ "$primary_ip" != "unknown" ]]; then
            dig +short -x "$primary_ip" 2>/dev/null || echo "Not configured"
        else
            echo "Cannot determine IP"
        fi
    fi
}

show_docker_info() {
    print_header "DOCKER INFORMATION"
    
    if check_command docker; then
        print_section "Docker Version"
        docker --version 2>/dev/null || echo "Docker not available"
        
        if docker info &>/dev/null; then
            print_section "Docker System Info"
            docker info 2>/dev/null | grep -E "(Server Version|Storage Driver|Kernel Version|Operating System|CPUs|Total Memory|Docker Root Dir)" || echo "Cannot access Docker info"
            
            print_section "Docker Containers"
            echo "Running containers:"
            docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "No running containers"
            
            echo
            echo "All containers:"
            docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" 2>/dev/null || echo "No containers found"
            
            print_section "Docker Images"
            docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}" 2>/dev/null || echo "No images found"
            
            print_section "Docker Volumes"
            docker volume ls 2>/dev/null || echo "No volumes found"
            
            print_section "Docker Networks"
            docker network ls 2>/dev/null || echo "No networks found"
        else
            echo "Cannot access Docker daemon (may not be running or insufficient permissions)"
        fi
        
        if check_command docker-compose; then
            echo
            echo "Docker Compose version:"
            docker-compose --version 2>/dev/null || echo "Docker Compose not available"
        fi
    else
        echo "Docker is not installed"
    fi
}

show_performance_info() {
    print_header "PERFORMANCE INFORMATION"
    
    print_section "System Load"
    echo "Load averages: $(uptime | awk -F'load average:' '{print $2}')"
    
    if [[ -f /proc/loadavg ]]; then
        echo "Detailed load: $(cat /proc/loadavg)"
    fi
    
    print_section "CPU Usage"
    if check_command top; then
        echo "Current CPU usage:"
        top -bn1 | grep "Cpu(s)" || echo "Cannot determine CPU usage"
    fi
    
    print_section "Memory Usage"
    free -h
    
    if [[ -f /proc/meminfo ]]; then
        echo
        echo "Memory details:"
        grep -E "(MemTotal|MemFree|MemAvailable|Buffers|Cached|SwapTotal|SwapFree)" /proc/meminfo
    fi
    
    print_section "Disk Usage"
    df -h
    
    print_section "Disk I/O"
    if check_command iostat; then
        echo "Disk I/O statistics:"
        iostat -x 1 1 2>/dev/null || echo "iostat not available"
    fi
    
    if [[ -f /proc/diskstats ]]; then
        echo "Raw disk statistics:"
        head -10 /proc/diskstats
    fi
}

show_logs_info() {
    print_header "SYSTEM LOGS INFORMATION"
    
    print_section "System Log (Last 20 entries)"
    if check_command journalctl; then
        journalctl -n 20 --no-pager 2>/dev/null || echo "Cannot access system journal"
    elif [[ -f /var/log/syslog ]]; then
        tail -20 /var/log/syslog 2>/dev/null || echo "Cannot access syslog"
    elif [[ -f /var/log/messages ]]; then
        tail -20 /var/log/messages 2>/dev/null || echo "Cannot access messages log"
    fi
    
    print_section "Kernel Messages (Last 10)"
    dmesg | tail -10 2>/dev/null || echo "Cannot access kernel messages"
    
    print_section "Cron Logs (Last 10 entries)"
    if [[ -f /var/log/cron ]]; then
        tail -10 /var/log/cron 2>/dev/null || echo "No cron logs found"
    elif grep -l cron /var/log/* 2>/dev/null | head -1; then
        tail -10 "$(grep -l cron /var/log/* 2>/dev/null | head -1)" 2>/dev/null || echo "Cannot read cron logs"
    fi
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    local section="all"
    
    # Parse command line options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --system|--sys)
                section="system"
                shift
                ;;
            --hardware|--hw)
                section="hardware"
                shift
                ;;
            --network|--net)
                section="network"
                shift
                ;;
            --services|--svc)
                section="services"
                shift
                ;;
            --security|--sec)
                section="security"
                shift
                ;;
            --mail)
                section="mail"
                shift
                ;;
            --docker)
                section="docker"
                shift
                ;;
            --performance|--perf)
                section="performance"
                shift
                ;;
            --logs)
                section="logs"
                shift
                ;;
            -h|--help)
                echo "Usage: $0 [SECTION]"
                echo "Sections:"
                echo "  --system      System overview"
                echo "  --hardware    Hardware information"
                echo "  --network     Network configuration"
                echo "  --services    Services status"
                echo "  --security    Security information"
                echo "  --mail        Mail server information"
                echo "  --docker      Docker information"
                echo "  --performance Performance metrics"
                echo "  --logs        System logs"
                echo "  --help        Show this help"
                echo ""
                echo "Default: Show all sections"
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    case "$section" in
        "system")
            show_system_overview
            ;;
        "hardware")
            show_hardware_info
            ;;
        "network")
            show_network_info
            ;;
        "services")
            show_services_info
            ;;
        "security")
            show_security_info
            ;;
        "mail")
            show_mail_server_info
            ;;
        "docker")
            show_docker_info
            ;;
        "performance")
            show_performance_info
            ;;
        "logs")
            show_logs_info
            ;;
        "all"|*)
            show_system_overview
            show_hardware_info
            show_network_info
            show_services_info
            show_security_info
            show_mail_server_info
            show_docker_info
            show_performance_info
            show_logs_info
            ;;
    esac
    
    echo
    print_header "SYSTEM INFORMATION COMPLETE"
    echo "Generated on: $(date)"
    echo "For more specific information, run with section flags (--help for options)"
}

# Create the system info script function that's called from setup-vps.sh
create_system_info_script() {
    # This function is called from setup-vps.sh to create the system info script
    local monitoring_dir="$1"
    
    cp "${BASH_SOURCE[0]}" "$monitoring_dir/system-info.sh"
    chmod +x "$monitoring_dir/system-info.sh"
}

# =============================================================================
# SCRIPT ENTRY POINT
# =============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi