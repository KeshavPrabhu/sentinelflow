#!/bin/bash
# scripts/incident_report.sh
# Purpose: Automated data gathering for Post-Mortem / RCA

set -uo pipefail

REPORT_DIR="reports"
mkdir -p "$REPORT_DIR"
REPORT_FILE="${REPORT_DIR}/incident_$(date +%Y%m%d_%H%M%S).txt"

# Configuration (Defaults to local Docker Compose setup)
APP_URL="http://localhost:5000"
PROM_URL="http://localhost:9090"

{
    echo "================================================"
    echo "         SENTINELFLOW INCIDENT REPORT          "
    echo "================================================"
    echo "Timestamp  : $(date)"
    echo "Host       : $(hostname)"
    echo "GeneratedBy: $(whoami)"
    echo "------------------------------------------------"

    echo -e "\n[1] RECENT DEPLOYMENTS (from API):"
    curl -sf "${APP_URL}/api/deployments" | python3 -m json.tool | head -n 20 || echo "API Unreachable"

    echo -e "\n[2] ACTIVE SYSTEM ALERTS (Alertmanager):"
    # Queries Alertmanager for active firing alerts
    curl -sf "http://localhost:9093/api/v2/alerts" | python3 -m json.tool || echo "No active alerts found or Alertmanager down."

    echo -e "\n[3] RECENT APPLICATION ERRORS (Last 50 lines):"
    docker compose logs --tail=50 app | grep -i "error" || echo "No errors found in recent logs."

    echo -e "\n[4] RESOURCE SNAPSHOT (USE Method):"
    echo "CPU Load:"
    uptime
    echo "Memory State:"
    free -h
    echo "Disk State:"
    df -h /

    echo -e "\n[5] RECOMMENDATIONS:"
    echo "1. Verify if the 'failed' deployment matches a spike in application errors."
    echo "2. Check Prometheus for memory leak patterns (gradual increase before crash)."
    echo "3. Run 'docker compose ps' to check for container flapping."
    echo "------------------------------------------------"
    echo "END OF REPORT"
} | tee "$REPORT_FILE"

echo -e "\nIncident report saved to: $REPORT_FILE"