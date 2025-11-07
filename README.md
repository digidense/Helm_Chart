Run Terraform commands:

terraform init
terraform plan
terraform apply


Trigger the Lambda manually:

aws lambda invoke --function-name export-securityhub-findings output.json

Cleanup

If the bucket is not empty:

aws s3 rm s3://securityhub-findings-demo-bucket3456 --recursive
terraform destroy