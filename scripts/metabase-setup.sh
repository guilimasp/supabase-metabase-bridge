#!/bin/bash

# Metabase setup script
# Configures admin user and adds Supabase Postgres database
# Idempotent: safe to run multiple times

set -euo pipefail

# Configuration
METABASE_URL="http://localhost:3000"
MAX_WAIT=120
WAIT_INTERVAL=5

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check dependencies
check_dependencies() {
    local missing=()
    
    if ! command -v curl &> /dev/null; then
        missing+=("curl")
    fi
    
    if ! command -v jq &> /dev/null; then
        missing+=("jq")
    fi
    
    if [ ${#missing[@]} -ne 0 ]; then
        log_error "Missing dependencies: ${missing[*]}"
        log_error "Install with: brew install ${missing[*]}"
        exit 1
    fi
}

# Wait for Metabase to be ready
wait_for_metabase() {
    log_info "Waiting for Metabase to be ready..."
    
    local count=0
    while [ $count -lt $MAX_WAIT ]; do
        if curl -fsS "${METABASE_URL}/api/health" &> /dev/null; then
            log_info "Metabase is ready"
            return 0
        fi
        
        sleep $WAIT_INTERVAL
        count=$((count + WAIT_INTERVAL))
    done
    
    log_error "Metabase failed to start within ${MAX_WAIT} seconds"
    exit 1
}

# Load environment variables
load_env() {
    if [ ! -f .env ]; then
        log_error ".env file not found. Copy .env.example to .env and configure it."
        exit 1
    fi
    
    # Source .env file
    set -a
    source .env
    set +a
    
    # Validate required variables
    local required_vars=(
        "MB_ADMIN_EMAIL"
        "MB_ADMIN_PASSWORD"
        "MB_ENCRYPTION_SECRET_KEY"
        "SUPABASE_DB_HOST"
        "SUPABASE_DB_NAME"
        "SUPABASE_DB_USER"
        "SUPABASE_DB_PASSWORD"
    )
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var:-}" ]; then
            log_error "Required environment variable $var is not set"
            exit 1
        fi
    done
    
    # Set defaults
    MB_SITE_NAME="${MB_SITE_NAME:-Local Metabase}"
    SUPABASE_DB_PORT="${SUPABASE_DB_PORT:-5432}"
    SUPABASE_SSL="${SUPABASE_SSL:-true}"
    SUPABASE_SSLMODE="${SUPABASE_SSLMODE:-require}"
}

# Check if setup is needed
check_setup_needed() {
    local response
    response=$(curl -fsS "${METABASE_URL}/api/session/properties" 2>/dev/null || echo "")
    
    if [ -z "$response" ]; then
        return 1
    fi
    
    local setup_token
    setup_token=$(echo "$response" | jq -r '.setup-token // empty')
    
    if [ -z "$setup_token" ] || [ "$setup_token" = "null" ]; then
        return 1
    fi
    
    echo "$setup_token"
}

# Perform initial setup
perform_setup() {
    local setup_token="$1"
    
    log_info "Performing initial Metabase setup..."
    
    local setup_payload
    setup_payload=$(cat <<EOF
{
  "token": "$setup_token",
  "user": {
    "first_name": "Local",
    "last_name": "Admin",
    "email": "$MB_ADMIN_EMAIL",
    "password": "$MB_ADMIN_PASSWORD"
  },
  "prefs": {
    "site_name": "$MB_SITE_NAME",
    "allow_tracking": false,
    "report_timezone": "UTC"
  },
  "database": {
    "engine": "postgres",
    "name": "Supabase",
    "details": {
      "host": "$SUPABASE_DB_HOST",
      "port": $SUPABASE_DB_PORT,
      "dbname": "$SUPABASE_DB_NAME",
      "user": "$SUPABASE_DB_USER",
      "password": "$SUPABASE_DB_PASSWORD",
      "ssl": $SUPABASE_SSL,
      "sslmode": "$SUPABASE_SSLMODE"
    }
  }
}
EOF
)
    
    local response
    if response=$(curl -fsS -X POST \
        -H "Content-Type: application/json" \
        -d "$setup_payload" \
        "${METABASE_URL}/api/setup" 2>/dev/null); then
        
        log_info "Setup completed successfully"
        return 0
    else
        log_error "Setup failed"
        return 1
    fi
}

# Login to get session
login() {
    log_info "Logging in..."
    
    local login_payload
    login_payload=$(cat <<EOF
{
  "username": "$MB_ADMIN_EMAIL",
  "password": "$MB_ADMIN_PASSWORD"
}
EOF
)
    
    local response
    if response=$(curl -fsS -X POST \
        -H "Content-Type: application/json" \
        -d "$login_payload" \
        "${METABASE_URL}/api/session" 2>/dev/null); then
        
        echo "$response" | jq -r '.id'
    else
        log_error "Login failed"
        return 1
    fi
}

# Check if database exists
check_database_exists() {
    local session_id="$1"
    
    local response
    response=$(curl -fsS -H "X-Metabase-Session: $session_id" \
        "${METABASE_URL}/api/database" 2>/dev/null)
    
    if [ -z "$response" ]; then
        return 1
    fi
    
    # Check if Supabase database exists
    local db_exists
    db_exists=$(echo "$response" | jq -r '.[] | select(.name == "Supabase") | .id // empty')
    
    if [ -n "$db_exists" ] && [ "$db_exists" != "null" ]; then
        echo "$db_exists"
        return 0
    else
        return 1
    fi
}

# Add database
add_database() {
    local session_id="$1"
    
    log_info "Adding Supabase database..."
    
    local db_payload
    db_payload=$(cat <<EOF
{
  "engine": "postgres",
  "name": "Supabase",
  "details": {
    "host": "$SUPABASE_DB_HOST",
    "port": $SUPABASE_DB_PORT,
    "dbname": "$SUPABASE_DB_NAME",
    "user": "$SUPABASE_DB_USER",
    "password": "$SUPABASE_DB_PASSWORD",
    "ssl": $SUPABASE_SSL,
    "sslmode": "$SUPABASE_SSLMODE"
  }
}
EOF
)
    
    if curl -fsS -X POST \
        -H "Content-Type: application/json" \
        -H "X-Metabase-Session: $session_id" \
        -d "$db_payload" \
        "${METABASE_URL}/api/database" &> /dev/null; then
        
        log_info "Database added successfully"
        return 0
    else
        log_error "Failed to add database"
        return 1
    fi
}

# Main function
main() {
    log_info "Starting Metabase setup..."
    
    check_dependencies
    load_env
    wait_for_metabase
    
    # Check if setup is needed
    local setup_token
    if setup_token=$(check_setup_needed); then
        perform_setup "$setup_token"
    else
        log_info "Metabase already configured, checking database..."
        
        local session_id
        if session_id=$(login); then
            if ! check_database_exists "$session_id"; then
                add_database "$session_id"
            else
                log_info "Supabase database already exists"
            fi
        else
            log_error "Failed to login"
            exit 1
        fi
    fi
    
    log_info "Setup completed successfully!"
    log_info "Access Metabase at: $METABASE_URL"
    log_info "Login with: $MB_ADMIN_EMAIL"
}

# Run main function
main "$@"
