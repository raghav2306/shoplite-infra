#!/usr/bin/env bash
# Creates (or updates) the whole platform and hands the cluster to Argo CD:
#
#   1. checks the tools and which AWS account you're about to use
#   2. terraform init + apply   (VPC, EKS, add-ons, LB controller, ECR, CI role, Argo CD)
#   3. points kubectl at the new cluster
#   4. creates the app's Secrets from shoplite-gitops (they're never in Git)
#   5. shows the Argo CD sync status and the values the next steps need
#
# Usage: scripts/apply.sh [extra terraform apply args, e.g. -auto-approve]
#   GITOPS_DIR  path to your shoplite-gitops clone (default: ../shoplite-gitops)
#
# Safe to re-run: Terraform only changes what differs, and Secrets are applied
# with kubectl apply.
set -euo pipefail
cd "$(dirname "$0")/.."
INFRA_DIR="$(pwd)"
GITOPS_DIR="${GITOPS_DIR:-$INFRA_DIR/../shoplite-gitops}"
SECRET_DIRS=(mongodb-users mongodb-products mongodb-orders rabbitmq user-service)

echo "==> 1/5 Checking prerequisites"
for tool in terraform aws kubectl; do
  command -v "$tool" >/dev/null || { echo "Missing: $tool" >&2; exit 1; }
done
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)" ||
  { echo "AWS credentials not working: run 'aws configure' or 'aws sso login'." >&2; exit 1; }
echo "    AWS account: $ACCOUNT"

echo "==> 2/5 terraform init + apply (first run takes ~20 min)"
terraform init -input=false
terraform apply "$@"

CLUSTER="$(terraform output -raw cluster_name)"
REGION="$(terraform output -raw region)"

echo "==> 3/5 Pointing kubectl at $CLUSTER"
aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION"
kubectl get nodes

echo "==> 4/5 Creating the app's Secrets in namespace ecommerce"
kubectl create namespace ecommerce --dry-run=client -o yaml | kubectl apply -f -
missing=()
for d in "${SECRET_DIRS[@]}"; do
  f="$GITOPS_DIR/base/$d/secret.yaml"
  if [ -f "$f" ]; then
    kubectl apply -f "$f"
  else
    missing+=("$d")
  fi
done
if [ ${#missing[@]} -gt 0 ]; then
  echo
  echo "    Not found, so not created: ${missing[*]}"
  echo "    In $GITOPS_DIR, for each of them:"
  echo "      cp base/<name>/secret.yaml.example base/<name>/secret.yaml   # then set real values"
  echo "    and re-run this script (or kubectl apply -f each file)."
  echo "    Pods that need them stay in CreateContainerConfigError until then."
fi

echo "==> 5/5 Argo CD"
APP="$(kubectl -n argocd get applications -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
if [ -n "$APP" ]; then
  kubectl -n argocd get application "$APP" \
    -o custom-columns='APP:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,REVISION:.status.sync.revision'
fi

cat <<EOF

Done. Next:
  Argo CD UI:     kubectl -n argocd port-forward svc/argocd-server 8080:443   -> https://localhost:8080
  Login:          admin, password from:
                  $(terraform output -raw argocd_admin_password_command)
  App URL:        kubectl -n ecommerce get ingress frontends   (ALB hostname, ~3 min after the first sync)
  Watch the app:  kubectl -n ecommerce get pods -w

  For CI in shoplite-microservices (GitHub Actions):
    role-to-assume: $(terraform output -raw github_ci_role_arn)
    ECR registry:   $(terraform output -raw ecr_registry)

  Tear down:      scripts/destroy.sh
EOF
