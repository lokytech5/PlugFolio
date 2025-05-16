#!/bin/bash
exec > /var/log/user-data.log 2>&1
set -x

# Update the package index
sudo apt update -y && sudo apt upgrade -y

# Install required packages
sudo apt install -y awscli docker.io git nginx

# Configure Docker
sudo systemctl enable docker && sudo systemctl start docker
sudo usermod -aG docker ubuntu

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
sudo ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose

# Add 2GB Swap
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# Configure Nginx
sudo systemctl enable nginx && sudo systemctl start nginx

# Copy the systemd service file from your repo to the correct location
sudo cp /home/ubuntu/plugfolio-app/services/plugfolio-app.service /etc/systemd/system/plugfolio-app.service

# Reload systemd so it recognizes the new service
sudo systemctl daemon-reload

# Enable the service so it starts on boot (and you can start it right away)
sudo systemctl enable plugfolio-app.service

# Start the service
sudo systemctl start plugfolio-app.service
