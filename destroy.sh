#!/bin/bash

# Ensure the script is run from the repository root where the 'terraform' directory exists
if [ ! -d "terraform" ]; then
  echo "Error: Please run this script from the root of the PlugFolio repository, where the 'terraform' folder is located."
  exit 1
fi

# Verify that the script is executed on the 'dev' branch only
current_branch=$(git rev-parse --abbrev-ref HEAD)
if [ "$current_branch" != "dev" ]; then
  echo "Error: This script is designed to run only on the 'dev' branch for safety. You are currently on '$current_branch'. Please switch to 'dev' and try again."
  exit 1
fi

# Prompt the user to confirm destruction with the exact keyword 'destroy'
read -p "To proceed with destroying the PlugFolio dev environment, please type 'destroy' and press Enter: " input
if [ "$input" != "destroy" ]; then
  echo "Destruction cancelled. You did not enter 'destroy' as required for confirmation."
  exit 1
fi

# Check if the AWS CLI is installed and available
if ! command -v aws &> /dev/null; then
  echo "Error: The AWS CLI is not installed on your system. Please install it (e.g., 'sudo apt install awscli' on Ubuntu) and try again."
  exit 1
fi

# Check if jq is installed for parsing JSON responses
if ! command -v jq &> /dev/null; then
  echo "Error: The 'jq' tool is not installed. Please install it (e.g., 'sudo apt install jq') to process AWS role credentials."
  exit 1
fi

# Define the IAM role ARN for assuming permissions
ROLE_ARN="arn:aws:iam::061039798341:role/github-actions-plugfolio-role"
echo "Attempting to assume the IAM role '$ROLE_ARN' for this destruction process..."
TEMP_ROLE=$(aws sts assume-role --role-arn "$ROLE_ARN" --role-session-name "LocalDestroySession" --output json)
if [ $? -ne 0 ]; then
  echo "Error: Failed to assume the IAM role. Please verify your AWS CLI setup and ensure the role is accessible."
  exit 1
fi

# Export temporary AWS credentials from the assumed role
export AWS_ACCESS_KEY_ID=$(echo "$TEMP_ROLE" | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$TEMP_ROLE" | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$TEMP_ROLE" | jq -r '.Credentials.SessionToken')
echo "Successfully assumed role and set temporary AWS credentials."

# Navigate to the terraform directory and initialize the backend
cd terraform
echo "Setting up Terraform to use the S3 backend for state management..."
terraform init \
  -backend-config="bucket=plugfolio-terraform-state" \
  -backend-config="key=dev/terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="encrypt=true" \
  -backend-config="dynamodb_table=plugfolio-terraform-locks"
if [ $? -ne 0 ]; then
  echo "Error: Failed to initialize Terraform. Please check the backend configuration or network connection."
  exit 1
fi

# Generate and display the destruction plan
echo "Generating a preview of the resources to be destroyed in the dev environment..."
terraform plan -destroy
if [ $? -ne 0 ]; then
  echo "Error: Failed to create a destruction plan. Please review the output for permission or configuration issues."
  exit 1
fi

# Execute the destruction of all managed resources
echo "Proceeding to destroy the PlugFolio dev infrastructure..."
terraform destroy -auto-approve
if [ $? -ne 0 ]; then
  echo "Error: Failed to destroy the infrastructure. Check the output for detailed errors (e.g., permission issues)."
  exit 1
fi

# Check the state file and provide feedback on its status
echo "Verifying the Terraform state after destruction..."
if terraform state list > /dev/null 2>&1; then
  echo "Warning: The state file (s3://plugfolio-terraform-state/dev/terraform.tfstate) still contains resource references. Manual cleanup may be needed—run 'terraform state list' and 'terraform state rm <resource>' if necessary."
else
  echo "Success: The PlugFolio dev infrastructure has been fully destroyed, and the state file is empty."
fi