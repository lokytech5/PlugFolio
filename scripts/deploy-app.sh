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
INTERNAL_PORT=${INTERNAL_PORT:-3000}  # Fallback to 3000 if not provided

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

# Authenticate with ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin "$DOCKER_REGISTRY"

# Update docker-compose.yml with the correct image tag if it exists
if [ -f "$APP_DIR/docker-compose.yml" ]; then
  sed -i "s|image:.*|image: $DOCKER_REGISTRY:$NEW_TAG|" "$APP_DIR/docker-compose.yml" || true
fi

# Prepare the service file template based on deployment method
if [ ! -f "$SERVICE_TEMPLATE" ]; then
  if [ -f "$APP_DIR/docker-compose.yml" ]; then
    # Use docker-compose if docker-compose.yml exists
    cat << 'EOT' > "$SERVICE_TEMPLATE"
[Unit]
Description=Plugfolio App Docker Service
Requires=docker.service
After=docker.service network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c "cd /home/ubuntu/plugfolio-app && docker-compose -f docker-compose.yml up -d"
ExecStop=/bin/bash -c "cd /home/ubuntu/plugfolio-app && docker-compose -f docker-compose.yml down"
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
    EOT
  else
    # Use docker run if no docker-compose.yml
    cat << 'EOT' > "$SERVICE_TEMPLATE"
[Unit]
Description=Plugfolio App Docker Service
Requires=docker.service
After=docker.service network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c "docker run -d --name plugfolio-app-container -p {{EXTERNAL_PORT}}:{{INTERNAL_PORT}} {{DOCKER_IMAGE}}"
ExecStop=/bin/bash -c "docker stop plugfolio-app-container && docker rm plugfolio-app-container"
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
    EOT
  fi
  sudo chown ubuntu:ubuntu "$SERVICE_TEMPLATE"
fi

# Update the service file with dynamic values
if [ -f "$APP_DIR/docker-compose.yml" ]; then
  # For docker-compose, just copy the template (image is updated in docker-compose.yml)
  cp "$SERVICE_TEMPLATE" "$SERVICE_FILE"
else
  # For docker run, replace placeholders
  sed "s/{{EXTERNAL_PORT}}/$EXTERNAL_PORT/g; s/{{INTERNAL_PORT}}/$INTERNAL_PORT/g; s|{{DOCKER_IMAGE}}|$DOCKER_REGISTRY:$NEW_TAG|g" "$SERVICE_TEMPLATE" | sudo tee "$SERVICE_FILE" > /dev/null
fi

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