provider "aws" {
  region = var.region
}

# S3 bucket for findings
resource "aws_s3_bucket" "securityhub_bucket" {
  bucket        = var.bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "versioning" {
  bucket = aws_s3_bucket.securityhub_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "public_access_block" {
  bucket                  = aws_s3_bucket.securityhub_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# SNS topic and subscription
resource "aws_sns_topic" "findings_topic" {
  name = "securityhub-findings"
}

resource "aws_sns_topic_subscription" "email_subscription" {
  topic_arn = aws_sns_topic.findings_topic.arn
  protocol  = "email"
  endpoint  = var.sns_email
}

# IAM role for Lambda
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_role" {
  name               = "lambda-securityhub-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

# Inline IAM policy for Lambda
data "aws_iam_policy_document" "lambda_policy" {
  statement {
    sid    = "AllowSecurityHubRead"
    effect = "Allow"
    actions = [
      "securityhub:GetFindings",
      "securityhub:DescribeHub",
      "securityhub:BatchGet*"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowS3PutAndGet"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:PutObjectAcl",
      "s3:PutObjectTagging"
    ]
    resources = ["${aws_s3_bucket.securityhub_bucket.arn}/*"]
  }

  statement {
    sid       = "AllowSNSPublish"
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.findings_topic.arn]
  }

  statement {
    sid    = "AllowCloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }
}

resource "aws_iam_role_policy" "lambda_policy" {
  name   = "lambda-securityhub-policy"
  role   = aws_iam_role.lambda_role.id
  policy = data.aws_iam_policy_document.lambda_policy.json
}

# Lambda package
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda_function.zip"
}

resource "aws_lambda_function" "securityhub_export" {
  filename      = data.archive_file.lambda_zip.output_path
  function_name = var.lambda_function_name
  role          = aws_iam_role.lambda_role.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.9"
  timeout       = 120
  memory_size   = 512

  environment {
    variables = {
      S3_BUCKET            = aws_s3_bucket.securityhub_bucket.bucket
      SNS_TOPIC_ARN        = aws_sns_topic.findings_topic.arn
      PRESIGNED_EXPIRATION = "86400"
    }
  }
}

# EventBridge (CloudWatch Rule)
resource "aws_cloudwatch_event_rule" "daily_rule" {
  name                = "securityhub-daily-export"
  schedule_expression = "cron(0 0 * * ? *)"
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.daily_rule.name
  target_id = "SecurityHubLambda"
  arn       = aws_lambda_function.securityhub_export.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.securityhub_export.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_rule.arn
}
