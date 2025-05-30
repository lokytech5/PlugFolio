#!/bin/bash

# Parameters passed by SSM Automation
REPO_URL="$1"
DOCKER_REGISTRY="$2"
NEW_TAG="$3"
SUBDOMAIN="$4"
LAST_KNOWN_GOOD_TAG="$5"
BUCKET_NAME="$6"
INTERNAL_PORT="$7"  # New parameter

# Application directory and container name
APP_DIR="/home/ubuntu/plugfolio-app"
CONTAINER_NAME="plugfolio-app-container"

# Default ports
EXTERNAL_PORT=80
INTERNAL_PORT=${INTERNAL_PORT:-8000}  # Fallback to 8000 if not provided

# Validate input parameters
if [ -z "$REPO_URL" ] || [ -z "$DOCKER_REGISTRY" ] || [ -z "$NEW_TAG" ] || [ -z "$SUBDOMAIN" ]; then
  echo "Error: Missing required parameters (REPO_URL, DOCKER_REGISTRY, NEW_TAG, SUBDOMAIN)" >&2
  exit 1
fi

# Ensure Docker is installed
if ! command -v docker &> /dev/null; then
  echo "Installing Docker..."
  sudo apt update -y
  sudo apt install -y docker.io
  sudo systemctl start docker
  sudo systemctl enable docker
  sudo usermod -aG docker ubuntu
fi

# Install Docker Compose if needed
if ! command -v docker-compose &> /dev/null; then
  sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
  sudo chmod +x /usr/local/bin/docker-compose
  sudo ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
fi

# Clone or pull the repository
if [ ! -d "$APP_DIR" ]; then
  mkdir -p "$APP_DIR"
  cd "$APP_DIR"
  sudo -u ubuntu git clone "$REPO_URL" .
else
  cd "$APP_DIR"
  sudo -u ubuntu git fetch origin
  sudo -u ubuntu git reset --hard origin/main
fi

# Set ownership
sudo chown -R ubuntu:ubuntu "$APP_DIR"

# Download docker-compose.yml from S3 if it exists
if [ -n "$BUCKET_NAME" ]; then
  aws s3 cp "s3://$BUCKET_NAME/docker-compose.yml" "$APP_DIR/docker-compose.yml" || true
fi

# Update docker-compose.yml port mapping if it exists
if [ -f "$APP_DIR/docker-compose.yml" ]; then
  sed -i "s/ports:.*$/ports:\n      - \"$EXTERNAL_PORT:$INTERNAL_PORT\"/" "$APP_DIR/docker-compose.yml"
fi

# Pull the new Docker image
echo "Pulling new Docker image: $DOCKER_REGISTRY:$NEW_TAG"
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $DOCKER_REGISTRY
docker pull "$DOCKER_REGISTRY:$NEW_TAG"

# Deploy the application (support both docker run and docker-compose)
if [ -f "$APP_DIR/docker-compose.yml" ]; then
  echo "Deploying with Docker Compose..."
  sudo -u ubuntu docker-compose -f "$APP_DIR/docker-compose.yml" up -d
else
  if docker ps -q -f name="$CONTAINER_NAME"; then
    echo "Stopping existing container..."
    docker stop "$CONTAINER_NAME"
    docker rm "$CONTAINER_NAME"
  fi
  echo "Starting new container..."
  docker run -d --name "$CONTAINER_NAME" -p $EXTERNAL_PORT:$INTERNAL_PORT "$DOCKER_REGISTRY:$NEW_TAG"
fi

# Configure Nginx for the subdomain
NGINX_CONF="/etc/nginx/sites-available/default"
sudo tee $NGINX_CONF > /dev/null <<EOF
server {
    listen $EXTERNAL_PORT;
    server_name $SUBDOMAIN;

    location = /health {
        proxy_pass http://localhost:$INTERNAL_PORT/health;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location / {
        proxy_pass http://localhost:$INTERNAL_PORT;
        include /etc/nginx/proxy_params;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# Validate and reload Nginx
echo "Reloading Nginx..."
if sudo nginx -t; then
  sudo systemctl reload nginx
else
  echo "Error: Nginx configuration test failed" >&2
  exit 1
fi

echo "Deployment completed successfully"
echo "Deploying new version: $NEW_TAG"
echo "Previous good version: $LAST_KNOWN_GOOD_TAG"