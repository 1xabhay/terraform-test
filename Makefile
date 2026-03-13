.DEFAULT_GOAL := help

.PHONY: help whoami init validate plan apply test

help:
	@echo "make whoami"
	@echo "make init"
	@echo "make validate"
	@echo "make plan"
	@echo "make apply"
	@echo "make test BUCKET=<bucket-name>"

whoami:
	aws sts get-caller-identity --output json

init:
	terraform init

validate:
	terraform validate

plan:
	terraform plan

apply:
	terraform apply

test:
	@test -n "$(BUCKET)" || (echo "BUCKET is required"; exit 1)
	printf "terraform-s3-validation\n" | aws s3 cp - s3://$(BUCKET)/test.txt
	aws s3 cp s3://$(BUCKET)/test.txt -
