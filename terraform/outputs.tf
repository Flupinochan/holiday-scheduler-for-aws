output "lambda_function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.holiday_scheduler.function_name
}

output "eventbridge_rule_name" {
  description = "EventBridge rule name"
  value       = aws_cloudwatch_event_rule.daily_schedule.name
}

output "gcp_workload_identity_pool_name" {
  description = "Workload Identity Pool full name"
  value       = google_iam_workload_identity_pool.aws_pool.name
}

output "gcp_service_account_email" {
  description = "GCP service account used by workload identity"
  value       = google_service_account.calendar_sa.email
}
