#!/bin/bash
set -e

echo "Cloning repository..."
git clone "$REPO_URL" app
cd app

echo "Files in repo:"
ls -l

# Detect tech stack
if [ -f "plugfolio.yml" ]; then
  TECH=$(grep "tech:" plugfolio.yml | awk '{print $2}')
else
  if [ -f "package.json" ]; then
    TECH="typescript"
  elif [ -f "requirements.txt" ]; then
    TECH="python"
  else
    echo "Error: Could not detect tech stack"
    exit 1
  fi
fi

echo "Detected tech stack: $TECH"

# Generate Dockerfile if not present
if [ ! -f "Dockerfile" ]; then
  if [ "$TECH" = "typescript" ] || [ "$TECH" = "node" ]; then
    cat <<EOT > Dockerfile
FROM node:16
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN if [ -f "tsconfig.json" ]; then npm install typescript && npm run build; else npm install; fi
EXPOSE 3000
CMD ["npm", "start"]
EOT
  elif [ "$TECH" = "python" ]; then
    cat <<EOT > Dockerfile
FROM python:3.9-slim
WORKDIR /app
COPY requirements.txt ./
RUN pip install -r requirements.txt
COPY . .
EXPOSE 5000
CMD ["python", "app.py"]
EOT
  else
    echo "Error: Unsupported tech stack: $TECH"
    exit 1
  fi
fi

echo "Building Docker image..."
docker build -t "$IMAGE_REPO_NAME:$IMAGE_TAG" .
docker tag "$IMAGE_REPO_NAME:$IMAGE_TAG" "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$IMAGE_REPO_NAME:$IMAGE_TAG"
