terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
  }

  # State is local by default. For a team, use a remote backend, e.g.:
  # backend "s3" {
  #   bucket       = "my-terraform-state"
  #   key          = "shoplite-infra/terraform.tfstate"
  #   region       = "us-east-1"
  #   use_lockfile = true
  # }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "shoplite"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# Talks to the new cluster to install the AWS Load Balancer Controller.
# Authenticates with the same AWS credentials Terraform uses.
provider "helm" {
  # Own (empty) repo config and cache, not ~/Library/Preferences/helm: charts are
  # fetched by URL, so a broken or stale local `helm repo` can't break the apply.
  repository_config_path = "${path.module}/.terraform/helm/repositories.yaml"
  repository_cache       = "${path.module}/.terraform/helm/cache"

  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
    }
  }
}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}
