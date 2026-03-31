resource "null_resource" "pip_install" {
  triggers = {
    requirements_in_hash = fileexists("${path.module}/../src/requirements.in") ? filemd5("${path.module}/../src/requirements.in") : ""
    requirements_hash    = fileexists("${path.module}/../src/requirements.txt") ? filemd5("${path.module}/../src/requirements.txt") : ""
  }

  provisioner "local-exec" {
    command = <<EOT
      rm -rf ${path.module}/../src/__pycache__
      if [ -f ${path.module}/../src/requirements.in ]; then
        pip install --upgrade pip pip-tools || true
        pip-compile ${path.module}/../src/requirements.in -o ${path.module}/../src/requirements.txt || true
      fi
      if [ -f ${path.module}/../src/requirements.txt ]; then
        pip install -r ${path.module}/../src/requirements.txt \
          -t ${path.module}/../src \
          --upgrade \
          --platform manylinux2014_x86_64 \
          --implementation cp \
          --python-version 3.13 \
          --only-binary=:all:
      fi
    EOT
  }
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../src"
  output_path = "${path.module}/lambda_function.zip"
  excludes    = ["requirements.txt"]

  depends_on = [null_resource.pip_install]
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

resource "aws_lambda_function" "holiday_scheduler_function" {
  function_name    = "holiday-scheduler-lambda"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.handler"
  runtime          = "python3.13"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256


  logging_config {
    log_format = "JSON"
    log_group  = aws_cloudwatch_log_group.lambda_log_group.name
  }

  environment {
    variables = {
      GCP_WORKLOAD_IDENTITY_POOL     = google_iam_workload_identity_pool.workload_pool.name
      GCP_WORKLOAD_IDENTITY_PROVIDER = google_iam_workload_identity_pool_provider.workload_provider.name
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

resource "google_iam_workload_identity_pool" "workload_pool" {
  provider = google

  workload_identity_pool_id = "aws-pool"
  display_name              = "AWS Workload Identity Pool"
  description               = "Pool for AWS Lambda to auth to GCP via Workload Identity Federation"
}

resource "google_iam_workload_identity_pool_provider" "workload_provider" {
  provider = google

  workload_identity_pool_id          = google_iam_workload_identity_pool.workload_pool.workload_identity_pool_id
  workload_identity_pool_provider_id = "aws-provider"
  display_name                       = "AWS Workload Provider"
  description                        = "Allow AWS STS tokens to be traded for GCP credentials"
  disabled                           = false
  attribute_condition                = "attribute.aws_account==\"${var.aws_account_id}\" && attribute.aws_role==\"${aws_iam_role.lambda_role.arn}\""
  attribute_mapping = {
    "google.subject"        = "assertion.arn"
    "attribute.aws_account" = "assertion.account"
    "attribute.aws_role"    = "assertion.arn.contains('assumed-role') ? assertion.arn.extract('{account_arn}assumed-role/') + 'assumed-role/' + assertion.arn.extract('assumed-role/{role_name}/') : assertion.arn"
  }
  aws {
    account_id = var.aws_account_id
  }
}

resource "google_project_iam_member" "workload_identity_user_member" {
  project = var.gcp_project
  role    = "roles/iam.workloadIdentityUser"
  member  = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.workload_pool.name}/attribute.aws_role/${aws_iam_role.lambda_role.arn}"
}
