#!/bin/bash

# Parameters passed by SSM Automation
REPO_URL="$1"
DOCKER_REGISTRY="$2"
NEW_TAG="$3"
SUBDOMAIN="$4"

# Application directory and container name
APP_DIR="/home/ubuntu/plugfolio-app"
CONTAINER_NAME="plugfolio-app-container"

# Default app port (will be overridden by plugfolio.yml)
APP_PORT=80

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

# Read port from plugfolio.yml if it exists
if [ -f "$APP_DIR/plugfolio.yml" ]; then
  APP_PORT=$(grep "port:" "$APP_DIR/plugfolio.yml" | awk '{print $2}' || echo "80")
fi

# Pull the new Docker image
echo "Pulling new Docker image: $DOCKER_REGISTRY:$NEW_TAG"
docker pull "$DOCKER_REGISTRY:$NEW_TAG"

# Deploy the application (support both docker run and docker-compose)
if [ -f "$APP_DIR/docker-compose.yml" ]; then
  # Use Docker Compose if available
  echo "Deploying with Docker Compose..."
  sudo -u ubuntu docker-compose -f "$APP_DIR/docker-compose.yml" up -d
else
  # Otherwise, use a single container
  if docker ps -q -f name="$CONTAINER_NAME"; then
    echo "Stopping existing container..."
    docker stop "$CONTAINER_NAME"
    docker rm "$CONTAINER_NAME"
  fi
  echo "Starting new container..."
  docker run -d --name "$CONTAINER_NAME" -p 80:$APP_PORT "$DOCKER_REGISTRY:$NEW_TAG"
fi

# Configure Nginx for the subdomain
NGINX_CONF="/etc/nginx/sites-available/default"
sudo tee $NGINX_CONF > /dev/null <<EOF
server {
    listen 80;
    server_name $SUBDOMAIN;

    location = /health {
        proxy_pass http://localhost:$APP_PORT/health;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location / {
        proxy_pass http://localhost:$APP_PORT;
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