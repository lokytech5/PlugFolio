#!/bin/bash

# Parameters passed by SSM Automation
REPO_URL="$1"
DOCKER_REGISTRY="$2"
NEW_TAG="$3"
SUBDOMAIN="$4"
LAST_KNOWN_GOOD_TAG="$5"
BUCKET_NAME="$6"
INTERNAL_PORT="$7"  # Use the passed internal port

# Application directory and container name
APP_DIR="/home/ubuntu/plugfolio-app"
CONTAINER_NAME="plugfolio-app-container"
SERVICE_FILE="/etc/systemd/system/plugfolio-app.service"
SERVICE_TEMPLATE="$APP_DIR/plugfolio-app.service.template"

# Default ports
EXTERNAL_PORT=80
INTERNAL_PORT=${INTERNAL_PORT:-3000}  # Fallback to 3000 if not provided (safety net)

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

# Prepare the service file template if it doesn't exist
if [ ! -f "$SERVICE_TEMPLATE" ]; then
  cat << 'EOT' > "$SERVICE_TEMPLATE"
[Unit]
Description=Plugfolio App Docker Service
Requires=docker.service
After=docker.service network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c "cd /home/ubuntu/plugfolio-app && /usr/local/bin/docker-compose -f docker-compose.yml up -d || docker run -d --name plugfolio-app-container -p {{EXTERNAL_PORT}}:{{INTERNAL_PORT}} {{DOCKER_IMAGE}}"
ExecStop=/bin/bash -c "cd /home/ubuntu/plugfolio-app && /usr/local/bin/docker-compose -f docker-compose.yml down || docker stop plugfolio-app-container && docker rm plugfolio-app-container"
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOT
  sudo chown ubuntu:ubuntu "$SERVICE_TEMPLATE"
fi

# Update the service file with dynamic values
sed "s/{{EXTERNAL_PORT}}/$EXTERNAL_PORT/g; s/{{INTERNAL_PORT}}/$INTERNAL_PORT/g; s|{{DOCKER_IMAGE}}|$DOCKER_REGISTRY:$NEW_TAG|g" "$SERVICE_TEMPLATE" | sudo tee "$SERVICE_FILE" > /dev/null

# Reload systemd and restart the service
sudo systemctl daemon-reload
sudo systemctl restart plugfolio-app.service

# Configure Nginx for the subdomain
NGINX_CONF="/etc/nginx/sites-available/default"
sudo tee "$NGINX_CONF" > /dev/null <<EOF
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