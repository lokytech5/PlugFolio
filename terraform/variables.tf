variable "aws_region" {
  description = "The AWS region to deploy the resources in"
  type        = string
  default     = "us-east-1"

}

variable "root_domain" {
  description = "The root domain for the application"
  type        = string
  default     = "plugfolio.cloud"
}
