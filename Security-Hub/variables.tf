variable "region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region"
}

variable "bucket_name" {
  type        = string
  default     = "securityhub-findings-demo-bucket3456"
  description = "Name of the S3 bucket for SecurityHub findings"
}

variable "sns_email" {
  type        = string
  description = "Email address for SNS notifications"
  default     = "shijinjoy76@gmail.com"
}

variable "lambda_function_name" {
  type        = string
  default     = "export-securityhub-findings"
  description = "Lambda function name"
}
