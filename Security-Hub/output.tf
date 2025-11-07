output "sns_topic_arn" {
  value = module.securityhub_export.sns_topic_arn
}

output "s3_bucket_name" {
  value = module.securityhub_export.s3_bucket_name
}

output "lambda_function_name" {
  value = module.securityhub_export.lambda_function_name
}

output "lambda_arn" {
  value = module.securityhub_export.lambda_arn
}

output "eventbridge_rule_arn" {
  value = module.securityhub_export.eventbridge_rule_arn
}
