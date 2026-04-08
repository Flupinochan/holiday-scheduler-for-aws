resource "aws_ecr_repository" "lambda_repo" {
  name         = "holiday-scheduler"
  force_delete = true

  image_scanning_configuration {
    scan_on_push = false
  }
}

resource "aws_ecr_lifecycle_policy" "lambda_repo_policy" {
  repository = aws_ecr_repository.lambda_repo.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only 1 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 1
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

resource "aws_iam_role" "lambda_role" {
  name = "holiday-scheduler-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/holiday-scheduler-lambda"
  retention_in_days = 1
}

data "aws_ecr_image" "lambda_image" {
  repository_name = aws_ecr_repository.lambda_repo.name
  image_tag       = var.image_tag
}

resource "aws_lambda_function" "holiday_scheduler_function" {
  function_name = "holiday-scheduler-lambda"
  role          = aws_iam_role.lambda_role.arn
  timeout       = 60
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.lambda_repo.repository_url}@${data.aws_ecr_image.lambda_image.image_digest}"

  logging_config {
    log_format = "JSON"
    log_group  = aws_cloudwatch_log_group.lambda_log_group.name
  }

  depends_on = [aws_iam_role_policy_attachment.lambda_basic_execution]
}

resource "aws_iam_role" "scheduler_exec_role" {
  name = "holiday-scheduler-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "scheduler_invoke_policy" {
  name = "holiday-scheduler-invoke-lambda"
  role = aws_iam_role.scheduler_exec_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["lambda:InvokeFunction"]
      Resource = [aws_lambda_function.holiday_scheduler_function.arn]
    }]
  })
}

resource "aws_scheduler_schedule" "daily_schedule" {
  name                = "holiday-scheduler-daily"
  schedule_expression = "cron(0 15 * * ? *)"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.holiday_scheduler_function.arn
    role_arn = aws_iam_role.scheduler_exec_role.arn
  }
}

# 削除しても30日は残るらしい。すぐに再作成したい場合は別id名で作成すること
resource "google_iam_workload_identity_pool" "workload_pool" {
  provider = google

  workload_identity_pool_id = "aws-pool-20260406"
  display_name              = "AWS Workload Identity Pool"
  description               = "Pool for AWS Lambda to auth to GCP via Workload Identity Federation"

  depends_on = [
    google_project_service.calendar_api,
    google_project_service.iamcredentials_api,
    google_project_service.sts_api,
  ]
}

resource "google_iam_workload_identity_pool_provider" "workload_provider" {
  provider = google

  workload_identity_pool_id          = google_iam_workload_identity_pool.workload_pool.workload_identity_pool_id
  workload_identity_pool_provider_id = "aws-provider"
  display_name                       = "AWS Workload Provider"
  description                        = "Allow AWS STS tokens to be traded for GCP credentials"
  disabled                           = false
  attribute_mapping = {
    "google.subject"        = "assertion.account"
    "attribute.aws_account" = "assertion.account"
    "attribute.aws_role"    = "assertion.arn.contains('assumed-role') ? assertion.arn.extract('{account_arn}assumed-role/') + 'assumed-role/' + assertion.arn.extract('assumed-role/{role_name}/') : assertion.arn"
  }
  attribute_condition = "attribute.aws_account == \"${var.aws_account_id}\""

  aws {
    account_id = var.aws_account_id
  }
}

resource "google_service_account" "allow_calendar_api" {
  account_id   = "allow-calendar-api"
  display_name = "Service Account for Calendar API"
  project      = var.gcp_project
}

resource "google_project_iam_member" "workload_identity_user_member" {
  project = var.gcp_project
  role    = "roles/iam.workloadIdentityUser"
  member  = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.workload_pool.name}/attribute.aws_role/${aws_iam_role.lambda_role.arn}"
}

# Google Calendar API? の利用には、ServiceAccountTokenCreator権限が必要
# また、Google Calendar APIを「有効なAPIとサービス」で許可しておく必要があるかも

# 各権限の付与
resource "google_service_account_iam_binding" "sa_token_creator" {
  service_account_id = google_service_account.allow_calendar_api.name
  role               = "roles/iam.serviceAccountTokenCreator"
  members = [
    "principal://iam.googleapis.com/${google_iam_workload_identity_pool.workload_pool.name}/subject/${var.aws_account_id}",
    "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.workload_pool.name}/attribute.aws_account/${var.aws_account_id}",
  ]
}

resource "google_service_account_iam_binding" "workload_identity_user" {
  service_account_id = google_service_account.allow_calendar_api.name
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "principal://iam.googleapis.com/${google_iam_workload_identity_pool.workload_pool.name}/subject/${var.aws_account_id}",
    "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.workload_pool.name}/attribute.aws_account/${var.aws_account_id}",
  ]
}

# 各APIの有効化
resource "google_project_service" "calendar_api" {
  project            = var.gcp_project
  service            = "calendar-json.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "iamcredentials_api" {
  project            = var.gcp_project
  service            = "iamcredentials.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "sts_api" {
  project            = var.gcp_project
  service            = "sts.googleapis.com"
  disable_on_destroy = false
}

# ログ設定 (コストがかかるので必要に応じて有効化)
# resource "google_project_iam_audit_config" "audit" {
#   project = var.gcp_project
#   service = "allServices"

#   audit_log_config {
#     log_type = "DATA_READ"
#   }

#   audit_log_config {
#     log_type = "DATA_WRITE"
#   }
# }

# Outputs
data "google_project" "project" {
  project_id = var.gcp_project
}

output "project_number" {
  value = data.google_project.project.number
}

output "workload_identity_pool_id" {
  value = google_iam_workload_identity_pool.workload_pool.workload_identity_pool_id
}

output "workload_identity_provider_id" {
  value = google_iam_workload_identity_pool_provider.workload_provider.workload_identity_pool_provider_id
}

output "service_account_email" {
  value = google_service_account.allow_calendar_api.email
}
