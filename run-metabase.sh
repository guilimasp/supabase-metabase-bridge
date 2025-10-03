#!/bin/bash

# Load environment variables
source .env

# Set Metabase environment variables
export MB_DB_TYPE=h2
export MB_DB_FILE=./metabase-data/metabase.db
export MB_ANON_TRACKING_OPTOUT=true
export MB_ENCRYPTION_SECRET_KEY="$MB_ENCRYPTION_SECRET_KEY"

# Create data directory if it doesn't exist
mkdir -p metabase-data

# Run Metabase
echo "Starting Metabase..."
echo "Access at: http://localhost:3000"
echo "Admin email: $MB_ADMIN_EMAIL"
echo "Press Ctrl+C to stop"

java -jar metabase.jar
