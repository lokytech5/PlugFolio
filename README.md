# Plugfolio

Plugfolio is a Platform as a Service (PaaS) designed to simplify **backend application deployment** for non-technical users. With Plugfolio, you can "plug in" your Dockerized backend application by pushing code to GitHub, and the platform handles building, deploying, and managing your app on AWS. Each user gets a unique subdomain (e.g., `yourname.plugfolio.cloud`) to access their application.

## Features
- **Simple Deployment**: Push code to GitHub, and Plugfolio deploys your backend app automatically.
- **Subdomain Automation**: Get a unique subdomain for your app (e.g., `yourname.plugfolio.cloud`).
- **Reliability**: Health checks and automatic rollback if deployment fails.
- **Cost-Effective**: Low cost (~$1.20/month with AWS Free Tier, or ~$9.67/month without).
- **Flexibility**: Supports both single-container and Docker Compose deployments for backend apps (e.g., app + database).

## Directory Structure
- `scripts/`: Deployment scripts (`deploy-app.sh`, `rollback-app.sh`).
- `lambda/`: Lambda functions for the pipeline.
- `terraform/`: Infrastructure as Code (Terraform).
- `.github/workflows/`: CI/CD pipeline for infrastructure deployment (`deploy.yml`).

## Setup (For Administrators)
coming soon

## Usage (For Users)
Coming soon

## Architecture
Plugfolio uses an AWS-native pipeline:
- **Trigger**: GitHub Actions webhook via API Gateway and Lambda.
- **Orchestration**: Step Functions to manage the workflow.
- **Build**: CodeBuild builds Docker images and pushes to ECR.
- **Domain**: Route 53 creates subdomains (e.g., `yourname.plugfolio.cloud`).
- **Deployment**: SSM Automation deploys the container on an EC2 instance.
- **Networking**: Nginx routes traffic to your backend app.
- **Reliability**: Health checks, rollback, and systemd for container persistence.
- **Notifications**: SNS notifies users of deployment status.
- **Instance Type**: t2.micro (1 vCPU, 1 GiB RAM), suitable for small-scale backend apps.

## Cost
- **EC2 (t2.micro)**: ~$8.47/month (or $0/month with AWS Free Tier for 750 hours/month).
- **EBS (8 GiB gp3)**: ~$0.64/month.


## Notes
- **Backend Focus**: Plugfolio currently focuses on deploying backend applications (e.g., Node.js, Python, Java apps) that expose a port and a `/health` endpoint.

