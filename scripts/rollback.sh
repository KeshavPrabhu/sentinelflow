#!/bin/bash
# scripts/rollback.sh
# Usage: ./scripts/rollback.sh <staging|prod> [target_tag]

set -uo pipefail

ENV=${1:-"staging"}
PREV_TAG_FILE=".last_successful_tag"
LOG_FILE="logs/deploy_$(date +%Y%m%d).log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ROLLBACK] $1" | tee -a "$LOG_FILE"
}

# Determine which tag to roll back to
if [ $# -eq 2 ]; then
    TARGET_TAG=$2
elif [ -f "$PREV_TAG_FILE" ]; then
    TARGET_TAG=$(cat "$PREV_TAG_FILE")
else
    log "ERROR: No previous tag found and no tag provided. Cannot rollback."
    exit 2
fi

log "Initiating rollback of $ENV to version $TARGET_TAG..."

# Execute the deployment script with the old tag
# We reuse deploy.sh to ensure the same health checks are applied to the rollback
if bash scripts/deploy.sh "$ENV" "$TARGET_TAG"; then
    log "SUCCESS: Rollback to $TARGET_TAG completed."
    
    # Notify API of the rollback event
    curl -sf -X POST -H "Content-Type: application/json" \
         -d "{\"version\":\"$TARGET_TAG\", \"environment\":\"$ENV\", \"status\":\"rollback\", \"deployed_by\":\"$(whoami)\"}" \
         http://localhost:5000/api/deployments || true
    exit 0
else
    log "CRITICAL: Rollback failed. Manual intervention required!"
    exit 2
fi