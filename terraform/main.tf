terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.97.0"
    }
  }
  backend "s3" {}
}
# PlugFolio Terraform configuration
provider "aws" {
  region = var.aws_region
}

#VPC and Networking
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "plugfolio-vpc"
  }
}

# Subnets, Internet Gateway, and Route Table
resource "aws_subnet" "public" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  tags = {
    Name = "plugfolio-public-subnet"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "plugfolio-igw"
  }
}
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "plugfolio-public-route-table"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id

}

# Security Groups
resource "aws_security_group" "plugfolio_sg" {
  vpc_id      = aws_vpc.main.id
  name        = "plugfolio-sg"
  description = "Allow HTTP, SSH access"
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]

  }
  tags = {
    Name = "plugfolio-security-group"
  }

}

# EC2 Instance
resource "aws_instance" "plugfolio_instance" {
  ami                    = "ami-084568db4383264d4"
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.plugfolio_sg.id]
  user_data = templatefile("../scripts/user-data.sh.tmpl", {
    my_app_service = file("../services/plugfolio-app.service")
  })
  key_name                    = data.aws_key_pair.existing.key_name
  associate_public_ip_address = true
  tags = {
    Name = "plugfolio-instance"
  }
}

#Fetch existing Route 53 Hosted Zone
data "aws_route53_zone" "main" {
  name         = var.root_domain
  private_zone = false
}

#Fetch existing Key Pair from AWS
data "aws_key_pair" "existing" {
  key_name = "ec2-login-key"
}

#EBS Volume for EC2
resource "aws_ebs_volume" "plugfolio_volume" {
  availability_zone = aws_instance.plugfolio_instance.availability_zone
  size              = 30
  type              = "gp2"
  tags = {
    Name = "plugfolio-ebs-volume"
  }
}

resource "aws_volume_attachment" "plugfolio_volume_attachment" {
  device_name = "/dev/xvdf"
  volume_id   = aws_ebs_volume.plugfolio_volume.id
  instance_id = aws_instance.plugfolio_instance.id

}

data "aws_iam_role" "plugfolio_lambda_role" {
  name = "PlugfolioLambdaRole"
}

data "aws_iam_role" "plugfolio_codebuild_role" {
  name = "PlugfolioCodeBuildRole"
}

data "aws_iam_role" "plugfolio_ssm_role" {
  name = "PlugfolioSSMRole"
}

data "aws_caller_identity" "current" {}

resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
  numeric = true
}

# S3 Bucket for
resource "aws_s3_bucket" "plugfolio_scripts" {
  bucket = "plugfolio-scripts${random_string.suffix.result}"
  tags = {
    Name = "PlugfolioScriptsBucket"
  }

}

resource "aws_s3_object" "deploy_app_script" {
  bucket       = aws_s3_bucket.plugfolio_scripts.bucket
  key          = "deploy-app.sh"
  source       = "${path.module}/../scripts/deploy-app.sh"
  etag         = filemd5("${path.module}/../scripts/deploy-app.sh")
  content_type = "text/x-shellscript"
  acl          = "private"
}

resource "aws_s3_object" "rollback_app_script" {
  bucket       = aws_s3_bucket.plugfolio_scripts.bucket
  key          = "rollback-app.sh"
  source       = "${path.module}/../scripts/rollback-app.sh"
  etag         = filemd5("${path.module}/../scripts/rollback-app.sh")
  content_type = "text/x-shellscript"
  acl          = "private"
}

#ECR Repository
resource "aws_ecr_repository" "plugfolio_repo" {
  name                 = "plugfolio-app"
  image_tag_mutability = "MUTABLE"
  tags = {
    Name = "PlugfolioECRRepo"
  }

}

#codeBuild project
resource "aws_codebuild_project" "plugfolio_build_docker_image" {
  name          = "PlugfolioBuildDockerImage"
  service_role  = data.aws_iam_role.plugfolio_codebuild_role.arn
  build_timeout = 10

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:5.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = var.aws_region
    }
    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = data.aws_caller_identity.current.account_id
    }
    environment_variable {
      name  = "IMAGE_REPO_NAME"
      value = aws_ecr_repository.plugfolio_repo.name
    }
  }
  source {
    type      = "NO_SOURCE"
    buildspec = file("${path.module}/../buildspecs/build-docker-image.yml")
  }
}

#Lmabda functions
resource "aws_lambda_function" "trigger_step_functions" {
  function_name    = "trigger-step-function-lambda"
  role             = data.aws_iam_role.plugfolio_lambda_role.arn
  handler          = "trigger_step_function_lambda.lambda_handler"
  runtime          = "python3.13"
  architectures    = ["x86_64"]
  source_code_hash = filebase64sha256("${path.module}/../lambda/trigger_step_function_lambda.zip")
  filename         = "${path.module}/../lambda/trigger_step_function_lambda.zip"
}

resource "aws_lambda_function" "fetch_parameters" {
  function_name    = "fetch-parameters-lambda"
  role             = data.aws_iam_role.plugfolio_lambda_role.arn
  handler          = "fetch_parameters_lambda.lambda_handler"
  runtime          = "python3.13"
  architectures    = ["x86_64"]
  source_code_hash = filebase64sha256("${path.module}/../lambda/fetch_parameters_lambda.zip")
  filename         = "${path.module}/../lambda/fetch_parameters_lambda.zip"
}

resource "aws_lambda_function" "create_subdomain" {
  function_name    = "create-subdomain-lambda"
  role             = data.aws_iam_role.plugfolio_lambda_role.arn
  handler          = "create_subdomain_lambda.lambda_handler"
  runtime          = "python3.13"
  architectures    = ["x86_64"]
  source_code_hash = filebase64sha256("${path.module}/../lambda/create_subdomain_lambda.zip")
  filename         = "${path.module}/../lambda/create_subdomain_lambda.zip"

}

resource "aws_lambda_function" "health_check" {
  function_name    = "health-check-lambda"
  role             = data.aws_iam_role.plugfolio_lambda_role.arn
  handler          = "health_check_lambda.lambda_handler"
  runtime          = "python3.13"
  architectures    = ["x86_64"]
  source_code_hash = filebase64sha256("${path.module}/../lambda/health_check_lambda.zip")
  filename         = "${path.module}/../lambda/health_check_lambda.zip"

}

resource "aws_lambda_function" "update_last_known_good" {
  function_name    = "update-last-known-good-lambda"
  role             = data.aws_iam_role.plugfolio_lambda_role.arn
  handler          = "update_last_known_good_lambda.lambda_handler"
  runtime          = "python3.13"
  architectures    = ["x86_64"]
  source_code_hash = filebase64sha256("${path.module}/../lambda/update_last_known_good_lambda.zip")
  filename         = "${path.module}/../lambda/update_last_known_good_lambda.zip"

}

# End of lambda functions


#APi Gateway
resource "aws_api_gateway_rest_api" "webhook" {
  name = "PlugfolioWebhook"
}

resource "aws_api_gateway_resource" "webhook_resource" {
  rest_api_id = aws_api_gateway_rest_api.webhook.id
  parent_id   = aws_api_gateway_rest_api.webhook.root_resource_id
  path_part   = "webhook"
}

resource "aws_api_gateway_method" "webhook_method" {
  rest_api_id   = aws_api_gateway_rest_api.webhook.id
  resource_id   = aws_api_gateway_resource.webhook_resource.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "webhook_integration" {
  rest_api_id             = aws_api_gateway_rest_api.webhook.id
  resource_id             = aws_api_gateway_resource.webhook_resource.id
  http_method             = aws_api_gateway_method.webhook_method.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = aws_lambda_function.trigger_step_functions.invoke_arn
}

resource "aws_api_gateway_deployment" "webhook_deployment" {
  rest_api_id = aws_api_gateway_rest_api.webhook.id
  depends_on  = [aws_api_gateway_integration.webhook_integration]
}

resource "aws_api_gateway_stage" "webhook_stage" {
  rest_api_id   = aws_api_gateway_rest_api.webhook.id
  deployment_id = aws_api_gateway_deployment.webhook_deployment.id
  stage_name    = "prod"
}

resource "aws_lambda_permission" "api_gateway_trigger" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.trigger_step_functions.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.webhook.execution_arn}/*/*"
}


#SNS Topic
resource "aws_sns_topic" "notification" {
  name = "PlugfolioNotifications"
}
resource "aws_sns_topic_subscription" "email_subscription" {
  topic_arn = aws_sns_topic.notification.arn
  protocol  = "email"
  endpoint  = "rukydiakodue@gmail.com"
}
