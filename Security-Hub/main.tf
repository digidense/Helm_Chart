module "securityhub_export" {
  source = "./modules/securityhub_export"

  region               = var.region
  bucket_name          = var.bucket_name
  sns_email            = var.sns_email
  lambda_function_name = var.lambda_function_name
}