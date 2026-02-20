.PHONY: check whoami init fmt validate plan apply test destroy

check:
	@test -n "$(AWS_PROFILE)" || (echo "Set AWS_PROFILE"; exit 1)
	@test -n "$(AWS_REGION)" || (echo "Set AWS_REGION"; exit 1)

whoami: check
	aws sts get-caller-identity

init: check
	terraform init

fmt:
	terraform fmt

validate: check
	terraform validate

plan: check
	terraform plan

apply: check
	terraform apply -auto-approve

test: check
	aws s3api head-bucket --bucket "$$(terraform output -raw bucket_name)"

destroy: check
	terraform destroy -auto-approve
