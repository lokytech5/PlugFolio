output "ec2_public_ip" {
  description = "Public IP of the EC2 instance"
  value       = aws_instance.plugfolio_instance.public_ip
}

output "api_gateway_url" {
  description = "URL of the API Gateway"
  value       = "https://${aws_api_gateway_rest_api.webhook.id}.execute-api.${var.aws_region}.amazonaws.com/${aws_api_gateway_stage.webhook_stage.stage_name}/webhook"
}


output "sns_topic_arn" {
  description = "ARN of the SNS topic"
  value       = aws_sns_topic.plugfolio-notification.arn
}

output "ecr_repository_url" {
  description = "URL of the ECR repository"
  value       = aws_ecr_repository.plugfolio_repo.repository_url
}
