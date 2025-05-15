#!/bin/bash
if [ ! -d "terraform" ]; then
  echo "Error: This script must be run from the repository root (where the 'terraform' directory exists)."
  exit 1
fi
current_branch=$(git rev-parse --abbrev-ref HEAD)
if [ "$current_branch" != "dev" ]; then
  echo "Error: This script can only be run on the 'dev' branch. Current branch: $current_branch"
  exit 1
fi
read -p "Enter 'destroy' to confirm infrastructure destruction: " input
if [ "$input" != "destroy" ]; then
  echo "Destruction aborted. Keyword 'destroy' not provided."
  exit 1
fi
if ! command -v aws &> /dev/null; then
  echo "Error: AWS CLI is not installed. Please install it and try again."
  exit 1
fi
if ! command -v jq &> /dev/null; then
  echo "Error: jq is not installed. Please install it (e.g., 'sudo apt install jq') and try again."
  exit 1
fi
ROLE_ARN="arn:aws:iam::061039798341:role/github-actions-plugfolio-role"
echo "Assuming IAM role $ROLE_ARN..."
TEMP_ROLE=$(aws sts assume-role --role-arn "$ROLE_ARN" --role-session-name "LocalDestroySession" --output json)
if [ $? -ne 0 ]; then
  echo "Error: Failed to assume IAM role. Check AWS CLI configuration and permissions."
  exit 1
fi
export AWS_ACCESS_KEY_ID=$(echo "$TEMP_ROLE" | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$TEMP_ROLE" | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$TEMP_ROLE" | jq -r '.Credentials.SessionToken')
cd terraform
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
echo "Previewing destruction plan..."
terraform plan -destroy
if [ $? -ne 0 ]; then
  echo "Error: Terraform plan failed."
  exit 1
fi
echo "Destroying infrastructure..."
terraform destroy -auto-approve
if [ $? -ne 0 ]; then
  echo "Error: Terraform destroy failed."
  exit 1
fi
if terraform state list > /dev/null 2>&1; then
  echo "Warning: State file still contains resources. Manual cleanup may be required."
else
  echo "Infrastructure destroyed successfully. State file (s3://plugfolio-terraform-state/dev/terraform.tfstate) is empty."
fi