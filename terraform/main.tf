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

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "lambda_secret_read" {
  name        = "holiday-scheduler-lambda-secret-read"
  description = "Allow Lambda to read the secret that contains GCP workload identity configuration"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_secret_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_secret_read.arn
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.lambda_function_name}"
  retention_in_days = 14
}

resource "aws_lambda_layer_version" "holiday_deps" {
  filename   = var.lambda_layer_package_path
  layer_name = "holiday-scheduler-deps"
  compatible_runtimes = [var.lambda_runtime]
}

resource "aws_lambda_function" "holiday_scheduler" {
  function_name = var.lambda_function_name
  role          = aws_iam_role.lambda_role.arn
  handler       = var.lambda_handler
  runtime       = var.lambda_runtime

  filename         = var.lambda_package_path
  source_code_hash = filebase64sha256(var.lambda_package_path)

  layers = [aws_lambda_layer_version.holiday_deps.arn]

  environment {
    variables = {
      GCP_WORKLOAD_IDENTITY_POOL   = google_iam_workload_identity_pool.aws_pool.name
      GCP_WORKLOAD_IDENTITY_PROVIDER = google_iam_workload_identity_pool_provider.aws_provider.name
      GCP_SERVICE_ACCOUNT_EMAIL    = google_service_account.calendar_sa.email
      GCP_PROJECT                 = var.gcp_project
    }
  }

  depends_on = [aws_iam_role_policy_attachment.lambda_logs, aws_iam_role_policy_attachment.lambda_secret_policy]
}

resource "aws_cloudwatch_event_rule" "daily_schedule" {
  name                = "holiday-scheduler-daily"
  description         = "Daily trigger at 00:00 JST"
  schedule_expression = "cron(0 15 * * ? *)" # JST midnight
}

resource "aws_cloudwatch_event_target" "run_lambda" {
  rule      = aws_cloudwatch_event_rule.daily_schedule.name
  target_id = "HolidaySchedulerLambda"
  arn       = aws_lambda_function.holiday_scheduler.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.holiday_scheduler.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_schedule.arn
}

############################
# GCP resources
############################

resource "google_project_service" "calendar_api" {
  service = "calendar.googleapis.com"

  disable_on_destroy = false
}

resource "google_iam_workload_identity_pool" "aws_pool" {
  provider = google

  workload_identity_pool_id = var.gcp_workload_identity_pool_id
  display_name              = "AWS Workload Identity Pool"
  description               = "Pool for AWS Lambda to auth to GCP via Workload Identity Federation"
}

resource "google_iam_workload_identity_pool_provider" "aws_provider" {
  provider = google

  workload_identity_pool_id = google_iam_workload_identity_pool.aws_pool.workload_identity_pool_id
  workload_identity_pool_provider_id = var.gcp_workload_identity_provider_id
  display_name = "AWS Provider for Workload Identity Federation"
  description  = "Allow AWS STS tokens to be traded for GCP credentials"

  oidc {
    issuer_uri     = "https://sts.amazonaws.com"
    allowed_audiences = ["arn:aws:iam::${var.aws_account_id}:role/${aws_iam_role.lambda_role.name}"]
  }

  attribute_mapping = {
    "google.subject"         = "assertion.sub"
    "attribute.aws_role"     = "assertion.aws.role"
    "attribute.aws_account"  = "assertion.aws.account_id"
    "attribute.aws_region"   = "assertion.aws.region"
    "attribute.aws_arn"      = "assertion.aws.arn"
  }
}

resource "google_service_account" "calendar_sa" {
  account_id   = "holiday-scheduler-sa"
  display_name = "Holiday Scheduler Service Account"
}

resource "google_project_iam_member" "calendar_api_reader" {
  project = var.gcp_project
  role    = "roles/calendar.reader"
  member  = "serviceAccount:${google_service_account.calendar_sa.email}"
}

resource "google_project_iam_member" "workload_identity_user" {
  project = var.gcp_project
  role    = "roles/iam.workloadIdentityUser"
  member  = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.aws_pool.name}/attribute.aws_role/${aws_iam_role.lambda_role.arn}"
}
