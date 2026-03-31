############################
# AWS resources
############################

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
  name              = "/aws/lambda/${var.lambda_function_name}"
  retention_in_days = 1
}



resource "aws_lambda_function" "holiday_scheduler_function" {
  function_name    = var.lambda_function_name
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.handler"
  runtime          = "python3.13"
  filename         = var.lambda_package_path
  source_code_hash = filebase64sha256(var.lambda_package_path)

  logging_config {
    log_format = "JSON"
    log_group  = aws_cloudwatch_log_group.lambda_log_group.name
  }

  environment {
    variables = {
      GCP_WORKLOAD_IDENTITY_POOL     = google_iam_workload_identity_pool.workload_pool.name
      GCP_WORKLOAD_IDENTITY_PROVIDER = google_iam_workload_identity_pool_provider.workload_provider.name
      GCP_SERVICE_ACCOUNT_EMAIL      = google_service_account.calendar_service_account.email
      GCP_PROJECT                    = var.gcp_project
    }
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

############################
# GCP resources
############################

resource "google_project_service" "calendar_api" {
  service = "calendar.googleapis.com"

  disable_on_destroy = false
}

resource "google_iam_workload_identity_pool" "workload_pool" {
  provider = google

  workload_identity_pool_id = var.gcp_workload_identity_pool_id
  display_name              = "AWS Workload Identity Pool"
  description               = "Pool for AWS Lambda to auth to GCP via Workload Identity Federation"
}

resource "google_iam_workload_identity_pool_provider" "workload_provider" {
  provider = google

  workload_identity_pool_id          = google_iam_workload_identity_pool.workload_pool.workload_identity_pool_id
  workload_identity_pool_provider_id = var.gcp_workload_identity_provider_id
  display_name                       = "AWS Provider for Workload Identity Federation"
  description                        = "Allow AWS STS tokens to be traded for GCP credentials"

  oidc {
    issuer_uri        = "https://sts.amazonaws.com"
    allowed_audiences = ["arn:aws:iam::${var.aws_account_id}:role/${aws_iam_role.lambda_role.name}"]
  }

  attribute_mapping = {
    "google.subject"        = "assertion.sub"
    "attribute.aws_role"    = "assertion.aws.role"
    "attribute.aws_account" = "assertion.aws.account_id"
    "attribute.aws_region"  = "assertion.aws.region"
    "attribute.aws_arn"     = "assertion.aws.arn"
  }
}

resource "google_service_account" "calendar_service_account" {
  account_id   = "holiday-scheduler-sa"
  display_name = "Holiday Scheduler Service Account"
}

resource "google_project_iam_member" "calendar_api_reader_member" {
  project = var.gcp_project
  role    = "roles/calendar.reader"
  member  = "serviceAccount:${google_service_account.calendar_service_account.email}"
}

resource "google_project_iam_member" "workload_identity_user_member" {
  project = var.gcp_project
  role    = "roles/iam.workloadIdentityUser"
  member  = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.workload_pool.name}/attribute.aws_role/${aws_iam_role.lambda_role.arn}"
}
