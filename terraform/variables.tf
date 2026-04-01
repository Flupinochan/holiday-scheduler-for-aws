variable "image_tag" {
  type        = string
  description = "ECR image tag to deploy"
}

variable "aws_region" {
  description = "AWS region for Lambda/EventBridge resources"
  type        = string
  default     = "ap-northeast-1"
}

variable "aws_account_id" {
  description = "AWS account id used for workload identity role binding"
  type        = string
}


variable "gcp_project" {
  type        = string
  description = "GCP project ID"
}

variable "gcp_region" {
  type    = string
  default = "asia-northeast1"
}

