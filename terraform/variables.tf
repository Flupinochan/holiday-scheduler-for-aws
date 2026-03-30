variable "aws_region" {
  description = "AWS region for Lambda/EventBridge resources"
  type        = string
  default     = "ap-northeast-1"
}

variable "aws_account_id" {
  description = "AWS account id used for workload identity role binding"
  type        = string
}

variable "lambda_function_name" {
  description = "Lambda function name. Must exist as a zip artifact." 
  type        = string
  default     = "holiday-scheduler-lambda"
}

variable "lambda_runtime" {
  type    = string
  default = "python3.11"
}

variable "lambda_handler" {
  type    = string
  default = "lambda_function.handler"
}

variable "lambda_package_path" {
  description = "Path to Lambda zip package from terraform module root"
  type        = string
  default     = "../lambda_function.zip"
}

variable "lambda_layer_package_path" {
  description = "Path to Lambda layer zip package (python dependencies)"
  type        = string
  default     = "../lambda_layer.zip"
}

variable "gcp_project" {
  type        = string
  description = "GCP project ID"
}

variable "gcp_region" {
  type    = string
  default = "asia-northeast1"
}

variable "gcp_workload_identity_pool_id" {
  description = "Workload Identity Pool ID"
  type        = string
  default     = "aws-workload-pool"
}

variable "gcp_workload_identity_provider_id" {
  description = "Workload Identity Pool Provider ID"
  type        = string
  default     = "aws-provider"
}
