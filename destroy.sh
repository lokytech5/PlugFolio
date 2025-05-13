#!/bin/bash

# Ensure the script is run from the repository root
if [ ! -d "terraform" ]; then
  echo "Error: This script must be run from the repository root (where the 'terraform' directory exists)."
  exit 1
fi

# Check if on dev branch
current_branch=$(git rev-parse --abbrev-ref HEAD)
if [ "$current_branch" != "dev" ]; then
  echo "Error: This script can only be run on the 'dev' branch. Current branch: $current_branch"
  exit 1
fi

# Prompt for destroy keyword
read -p "Enter 'destroy' to confirm infrastructure destruction: " input
if [ "$input" != "destroy" ]; then
  echo "Destruction aborted. Keyword 'destroy' not provided."
  exit 1
fi

# Navigate to terraform directory
cd terraform

# Initialize Terraform with the same backend as deploy.yml
echo "Initializing Terraform..."
terraform init \
  -backend-config="bucket=plugfolio-terraform-state" \
  -backend-config="key=dev/terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="encrypt=true" \
  -backend-config="dynamodb_table=plugfolio-terraform-locks"

if [ $? -ne 0 ]; then
  echo "Error: Terraform init failed."
  exit 1
fi

# Preview destruction
echo "Previewing destruction plan..."
terraform plan -destroy

if [ $? -ne 0 ]; then
  echo "Error: Terraform plan failed."
  exit 1
fi

# Execute destruction
echo "Destroying infrastructure..."
terraform destroy -auto-approve

if [ $? -ne 0 ]; then
  echo "Error: Terraform destroy failed."
  exit 1
fi

echo "Infrastructure destroyed successfully. State file updated: s3://plugfolio-terraform-state/dev/terraform.tfstate"