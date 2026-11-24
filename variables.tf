variable "region" {
  type    = string
  default = "us-east-1"
}

variable "environment" {
  description = "Also the ECR repository prefix (<env>/<service>). shoplite-gitops/overlays/eks expects \"dev\": change both together."
  type        = string
  default     = "dev"
}

variable "cluster_name" {
  description = "Also used as the prefix for the VPC and IAM roles."
  type        = string
  default     = "ecommerce"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version. Must be one AWS currently supports: aws eks describe-cluster-versions"
  type        = string
  default     = "1.37"
}

variable "vpc_cidr" {
  type    = string
  default = "10.30.0.0/16"
}

# ---------- Nodes ----------

variable "node_instance_type" {
  description = "x86 to match the linux/amd64 images built in shoplite-microservices. t3.medium fits 17 pods per node."
  type        = string
  default     = "t3.medium"
}

# 3 × t3.medium = 51 pod slots. The cluster needs ~35: system add-ons ~14,
# app Deployments 12, MongoDB ×3 + RabbitMQ 4, Argo CD 5. Two nodes (34 slots)
# leave pods Pending.
variable "node_desired_size" {
  type    = number
  default = 3
}

variable "node_min_size" {
  type    = number
  default = 2
}

# Upper bound only: nothing scales the group automatically (no Cluster
# Autoscaler or Karpenter). Change node_desired_size to resize.
variable "node_max_size" {
  type    = number
  default = 4
}

variable "node_disk_size_gb" {
  type    = number
  default = 20
}

# ---------- Access ----------

variable "cluster_endpoint_public_access_cidrs" {
  description = "Who may reach the Kubernetes API (kubectl). Narrow to your IP, e.g. [\"203.0.113.7/32\"]."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# ---------- Add-on versions ----------

variable "lb_controller_chart_version" {
  description = "aws-load-balancer-controller Helm chart. When changing it, also replace policies/aws-load-balancer-controller-v<version>.json with that release's docs/install/iam_policy.json."
  type        = string
  default     = "3.6.3"
}

variable "argocd_chart_version" {
  description = "argo-cd Helm chart (10.17.2 = Argo CD v3.6.1)."
  type        = string
  default     = "10.17.2"
}

variable "argocd_apps_chart_version" {
  description = "argocd-apps Helm chart, used to create the bootstrap Application."
  type        = string
  default     = "2.0.7"
}

# ---------- GitOps (what Argo CD deploys) ----------

variable "argocd_app_name" {
  type    = string
  default = "shoplite-eks"
}

variable "gitops_repo_url" {
  description = "Repo Argo CD syncs from. Must be public, or registered in Argo CD with credentials."
  type        = string
  default     = "https://github.com/raghav2306/shoplite-gitops.git"
}

variable "gitops_revision" {
  type    = string
  default = "main"
}

variable "gitops_path" {
  type    = string
  default = "overlays/eks"
}

# ---------- CI (GitHub Actions -> ECR) ----------

variable "github_repo" {
  description = "owner/name of the repo whose workflow may push images."
  type        = string
  default     = "raghav2306/shoplite-microservices"
}

variable "github_branch" {
  description = "Only workflow runs on this branch can assume the CI role."
  type        = string
  default     = "main"
}

variable "create_github_oidc_provider" {
  description = "false if this AWS account already has the token.actions.githubusercontent.com OIDC provider."
  type        = bool
  default     = true
}
