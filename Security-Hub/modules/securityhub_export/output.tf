output "sns_topic_arn" {
  value = aws_sns_topic.findings_topic.arn
}

output "s3_bucket_name" {
  value = aws_s3_bucket.securityhub_bucket.bucket
}

output "lambda_function_name" {
  value = aws_lambda_function.securityhub_export.function_name
}

output "lambda_arn" {
  value = aws_lambda_function.securityhub_export.arn
}

output "eventbridge_rule_arn" {
  value = aws_cloudwatch_event_rule.daily_rule.arn
}
