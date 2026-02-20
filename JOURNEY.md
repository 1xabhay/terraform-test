# Journey Notes

1. `terraform init` - Prepares the Terraform working directory for use.
2. `AWS provider decision` - Terraform will use AWS API credentials to create and manage cloud resources.
3. `AWS credentials model` - Terraform AWS provider uses AWS SDK credential chain (not AWS CLI itself) to authenticate API calls.
4. `Credential switching` - Set `AWS_PROFILE` or access-key env vars before Terraform to choose the target AWS account.
5. `Identity check config` - Minimal Terraform code now reads current AWS caller identity and outputs account and ARN.
6. `Identity test run` - `terraform apply` confirmed current credentials map to AWS account `336162656437`.
7. `Docs alignment` - Configuration and credential flow matches current HashiCorp and AWS documentation.
8. `Open-source auth pattern` - Use named AWS profiles via environment variables, keep credentials out of Terraform code, and verify identity before apply.
9. `No fallback config` - Removed Terraform region default so AWS region/profile must come from environment or shared AWS config.
10. `Runtime-only execution` - Added `Makefile` commands that require `AWS_PROFILE` and `AWS_REGION` at command runtime.
11. `CI-ready auth path` - Added minimal README flow for local profile, container runner, and GitHub Actions OIDC role usage.
12. `Docs freshness` - Updated GitHub Actions auth example to `aws-actions/configure-aws-credentials@v5`.
13. `80/20 audit` - Removed non-essential workflow content and kept only account check, validate, apply, and smoke-test actions.
14. `Provision target` - Added one minimal AWS resource (`aws_s3_bucket`) so Terraform apply performs real infrastructure provisioning.
