#!/bin/bash
# scripts/system_health_check.sh
# Purpose: Comprehensive host health validation for SRE pipelines
# Exit Codes: 0=Healthy, 1=Warning (Degraded), 2=Critical (Fail)

set -uo pipefail

# Color variables for professional CLI output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

REPORT_FILE="/tmp/health_report_$(date +%Y%m%d_%H%M%S).txt"
OVERALL_STATUS=0

# --- HELPER FUNCTIONS ---

log_result() {
    local check_name=$1
    local status=$2
    local detail=$3
    
    case $status in
        0) printf "[${GREEN}PASS${NC}] %-20s — %s\n" "$check_name" "$detail" ;;
        1) printf "[${YELLOW}WARN${NC}] %-20s — %s\n" "$check_name" "$detail" ;;
        2) printf "[${RED}FAIL${NC}] %-20s — %s\n" "$check_name" "$detail" ;;
    esac
}

# --- HEALTH CHECKS ---

check_cpu() {
    # Read CPU idle from /proc/stat
    local cpu_idle=$(top -bn1 | grep "Cpu(s)" | awk '{print $8}')
    local cpu_usage=$(echo "100 - $cpu_idle" | bc)
    
    if (( $(echo "$cpu_usage > 90" | bc -l) )); then
        log_result "CPU Usage" 2 "${cpu_usage}% (Critical)"
        [[ $OVERALL_STATUS -lt 2 ]] && OVERALL_STATUS=2
    elif (( $(echo "$cpu_usage > 75" | bc -l) )); then
        log_result "CPU Usage" 1 "${cpu_usage}% (Warning)"
        [[ $OVERALL_STATUS -lt 1 ]] && OVERALL_STATUS=1
    else
        log_result "CPU Usage" 0 "${cpu_usage}%"
    fi
}

check_memory() {
    local mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local mem_avail=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    local mem_used_pct=$(( (mem_total - mem_avail) * 100 / mem_total ))

    if [ "$mem_used_pct" -gt 95 ]; then
        log_result "Memory Usage" 2 "${mem_used_pct}% (Critical)"
        [[ $OVERALL_STATUS -lt 2 ]] && OVERALL_STATUS=2
    elif [ "$mem_used_pct" -gt 80 ]; then
        log_result "Memory Usage" 1 "${mem_used_pct}% (Warning)"
        [[ $OVERALL_STATUS -lt 1 ]] && OVERALL_STATUS=1
    else
        log_result "Memory Usage" 0 "${mem_used_pct}%"
    fi
}

check_disk() {
    local disk_usage=$(df -h / | tail -1 | awk '{print $5}' | sed 's/%//')
    if [ "$disk_usage" -gt 90 ]; then
        log_result "Disk Usage" 2 "${disk_usage}% (Critical)"
        [[ $OVERALL_STATUS -lt 2 ]] && OVERALL_STATUS=2
    else
        log_result "Disk Usage" 0 "${disk_usage}%"
    fi
}

check_docker() {
    if docker ps --quiet > /dev/null 2>&1; then
        log_result "Docker Engine" 0 "Running"
    else
        log_result "Docker Engine" 2 "Down / No Permission"
        [[ $OVERALL_STATUS -lt 2 ]] && OVERALL_STATUS=2
    fi
}

check_postgres() {
    # Try pg_isready first, fallback to nc (Netcat) for port check
    if command -v pg_isready >/dev/null 2>&1; then
        if pg_isready -h localhost -p 5432 >/dev/null 2>&1; then
            log_result "PostgreSQL" 0 "Responding"
            return
        fi
    elif nc -z localhost 5432 >/dev/null 2>&1; then
        log_result "PostgreSQL" 0 "TCP Port 5432 Open"
        return
    fi
    log_result "PostgreSQL" 2 "Not Responding"
    [[ $OVERALL_STATUS -lt 2 ]] && OVERALL_STATUS=2
}

check_dns() {
    if nslookup google.com > /dev/null 2>&1; then
        log_result "DNS Resolution" 0 "Working"
    else
        log_result "DNS Resolution" 2 "Failed"
        [[ $OVERALL_STATUS -lt 2 ]] && OVERALL_STATUS=2
    fi
}

# --- EXECUTION ---

echo -e "${BLUE}==================================================${NC}"
echo -e "  SentinelFlow Health Check | Host: $(hostname)"
echo -e "  Date: $(date)"
echo -e "${BLUE}==================================================${NC}"

check_cpu
check_memory
check_disk
check_docker
check_postgres
check_dns

echo -e "${BLUE}--------------------------------------------------${NC}"
case $OVERALL_STATUS in
    0) echo -e "OVERALL STATUS: ${GREEN}HEALTHY${NC}" ;;
    1) echo -e "OVERALL STATUS: ${YELLOW}DEGRADED (WARNINGS)${NC}" ;;
    2) echo -e "OVERALL STATUS: ${RED}CRITICAL (ABORT)${NC}" ;;
esac

# Write to report file for pipeline artifacts
{
    echo "SentinelFlow Health Report"
    echo "Generated: $(date)"
    echo "Overall Status: $OVERALL_STATUS"
} > "$REPORT_FILE"

echo -e "Report saved to: $REPORT_FILE"
exit $OVERALL_STATUS