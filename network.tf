locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

# Public subnets only, no NAT gateway: nodes get public IPs and reach ECR, EKS
# and the internet through the internet gateway. Inbound traffic to the nodes
# is still limited by the EKS security groups (cluster and ALB only).
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = var.cluster_name
  cidr = var.vpc_cidr
  azs  = local.azs

  public_subnets = [for i in range(length(local.azs)) : cidrsubnet(var.vpc_cidr, 8, i)]

  # Nodes in these subnets need a public IP to pull images and join the cluster
  map_public_ip_on_launch = true

  enable_nat_gateway   = false
  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags = {
    # The AWS Load Balancer Controller puts internet-facing ALBs in subnets with this tag
    "kubernetes.io/role/elb" = "1"
  }
}
