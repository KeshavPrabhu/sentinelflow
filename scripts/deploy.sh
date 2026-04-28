#!/bin/bash
# scripts/deploy.sh
# Usage: ./scripts/deploy.sh <staging|prod> <image_tag>

set -uo pipefail

# --- CONFIGURATION ---
ENV=${1:-""}
IMAGE_TAG=${2:-""}
LOG_DIR="logs"
LOG_FILE="${LOG_DIR}/deploy_$(date +%Y%m%d).log"
PREV_TAG_FILE=".last_successful_tag"
HEALTH_URL="http://localhost:5000/health"

mkdir -p "$LOG_DIR"

# --- HELPERS ---
log() {
    local level=$1
    local msg=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[$timestamp] [$level] $msg" | tee -a "$LOG_FILE"
}

usage() {
    echo "Usage: $0 <staging|prod> <image_tag>"
    exit 1
}

# --- VALIDATION ---
[[ -z "$ENV" || -z "$IMAGE_TAG" ]] && usage
[[ "$ENV" != "staging" && "$ENV" != "prod" ]] && log ERROR "Invalid env: $ENV" && usage

# --- STEP 1: PRE-DEPLOY HEALTH CHECK ---
pre_deploy_checks() {
    log INFO "Starting pre-deploy health gate for $ENV..."
    bash scripts/system_health_check.sh
    local exit_code=$?
    
    if [ $exit_code -eq 2 ]; then
        log FATAL "Host system is in CRITICAL state. Aborting deployment."
        exit 2
    elif [ $exit_code -eq 1 ]; then
        log WARN "Host system has warnings. Proceeding with caution..."
    else
        log SUCCESS "Host health check passed."
    fi
}

# --- STEP 2: DOCKER DEPLOYMENT ---
do_deploy() {
    log INFO "Deploying SentinelFlow version: $IMAGE_TAG to $ENV environment..."
    
    # Select the correct compose file
    local COMPOSE_FILE="docker-compose.yml"
    [[ "$ENV" == "staging" ]] && COMPOSE_FILE="docker-compose.staging.yml"
    
    export IMAGE_TAG=$IMAGE_TAG
    
    log INFO "Pulling latest image and restarting container..."
    docker compose -f "$COMPOSE_FILE" pull app 2>>"$LOG_FILE"
    docker compose -f "$COMPOSE_FILE" up -d --no-deps app 2>>"$LOG_FILE"
    
    log INFO "Wait 15s for application bootstrap..."
    sleep 15
}

# --- STEP 3: POST-DEPLOY VERIFICATION (Smoke Test) ---
verify_deploy() {
    local MAX_RETRIES=5
    local DELAY=5
    log INFO "Verifying application health at $HEALTH_URL..."

    for ((i=1; i<=MAX_RETRIES; i++)); do
        local status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$HEALTH_URL")
        if [ "$status" == "200" ]; then
            log SUCCESS "Health check passed on attempt $i."
            # Save the tag for future rollbacks
            echo "$IMAGE_TAG" > "$PREV_TAG_FILE"
            return 0
        fi
        log WARN "Attempt $i: Status $status. Retrying in ${DELAY}s..."
        sleep $DELAY
    done

    log ERROR "Application failed to become healthy after $MAX_RETRIES attempts."
    return 1
}

# --- STEP 4: RECORD DEPLOYMENT TO API ---
record_deployment() {
    local status=$1
    log INFO "Recording deployment status ($status) to API..."
    
    # Payload for our Internal Dashboard
    local payload=$(cat <<EOF
{
  "version": "$IMAGE_TAG",
  "environment": "$ENV",
  "status": "$status",
  "deployed_by": "$(whoami)",
  "pipeline": "automated-script"
}
EOF
)

    curl -sf -X POST -H "Content-Type: application/json" \
         -d "$payload" http://localhost:5000/api/deployments || \
         log WARN "Could not record to API (app might be down). Check DB manually."
}

# --- MAIN EXECUTION ---
start_time=$(date +%s)

pre_deploy_checks
do_deploy

if ! verify_deploy; then
    record_deployment "failed"
    log FATAL "Deployment failed! Triggering automated rollback..."
    bash scripts/rollback.sh "$ENV"
    exit 1
fi

record_deployment "success"
end_time=$(date +%s)
duration=$((end_time - start_time))

log SUCCESS "Deployment of $IMAGE_TAG to $ENV completed in ${duration}s."
exit 0