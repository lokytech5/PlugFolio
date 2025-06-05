#!/bin/bash

# Parameters passed by SSM Automation
DOCKER_REGISTRY="$1"
LAST_KNOWN_GOOD_TAG="$2"
SUBDOMAIN="$3"
BUCKET_NAME="$4"
INTERNAL_PORT="$5"  # New parameter

# Application directory and container name
APP_DIR="/home/ubuntu/plugfolio-app"
CONTAINER_NAME="plugfolio-app-container"

# Default ports
EXTERNAL_PORT=80
INTERNAL_PORT=${INTERNAL_PORT:-3000}  # Fallback to 3000 if not provided

# Validate input parameters
if [ -z "$DOCKER_REGISTRY" ] || [ -z "$LAST_KNOWN_GOOD_TAG" ] || [ -z "$SUBDOMAIN" ]; then
  echo "Error: Missing required parameters (DOCKER_REGISTRY, LAST_KNOWN_GOOD_TAG, SUBDOMAIN)" >&2
  exit 1
fi

# Stop the current application
if [ -f "$APP_DIR/docker-compose.yml" ]; then
  echo "Stopping Docker Compose services..."
  cd "$APP_DIR"
  sudo -u ubuntu docker-compose -f "$APP_DIR/docker-compose.yml" down
else
  if docker ps -q -f name="$CONTAINER_NAME"; then
    echo "Stopping existing container..."
    docker stop "$CONTAINER_NAME"
    docker rm "$CONTAINER_NAME"
  fi
fi

# Pull the last known good Docker image
echo "Pulling last known good Docker image: $DOCKER_REGISTRY:$LAST_KNOWN_GOOD_TAG"
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $DOCKER_REGISTRY
docker pull "$DOCKER_REGISTRY:$LAST_KNOWN_GOOD_TAG"

# Deploy the last known good image (support both docker run and docker-compose)
if [ -f "$APP_DIR/docker-compose.yml" ]; then
  echo "Deploying with Docker Compose..."
  cd "$APP_DIR"
  sudo -u ubuntu docker-compose -f "$APP_DIR/docker-compose.yml" up -d
else
  echo "Starting last known good container..."
  docker run -d --name "$CONTAINER_NAME" -p $EXTERNAL_PORT:$INTERNAL_PORT "$DOCKER_REGISTRY:$LAST_KNOWN_GOOD_TAG"
fi

# Nginx configuration is already set from deploy-app.sh, so no changes needed
# Validate and reload Nginx (just to ensure it's running)
echo "Reloading Nginx..."
if sudo nginx -t; then
  sudo systemctl reload nginx
else
  echo "Error: Nginx configuration test failed" >&2
  exit 1
fi

echo "Rollback completed successfully"