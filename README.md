# Terraform 80/20

Goal: minimal flow to verify AWS account, validate Terraform, provision infra, and run a smoke test.

## Setup

```bash
aws configure --profile myproj
export AWS_PROFILE=myproj
export AWS_REGION=us-east-1
```

## Run

```bash
make whoami
make init
make fmt
make validate
make plan
make apply
make test
```

## Cleanup

```bash
make destroy
```
