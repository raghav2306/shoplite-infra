# Repositories for the 6 app images: <registry>/dev/<name>, as referenced by
# shoplite-gitops/overlays/eks/kustomization.yaml. CI in shoplite-microservices
# pushes them (github-ci.tf).
locals {
  app_images = [
    "api-gateway",
    "user-service",
    "product-service",
    "order-service",
    "storefront",
    "admin",
  ]
}

resource "aws_ecr_repository" "this" {
  for_each = toset(local.app_images)

  name = "${var.environment}/${each.value}"
  # A tag (CI uses the commit SHA) can never be pushed twice, so a deployed tag
  # always means the same image. Deployments use imagePullPolicy: IfNotPresent,
  # which would otherwise keep running a stale image under a reused tag.
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true # let `terraform destroy` remove repos that still hold images

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the 20 most recent images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 20
      }
      action = { type = "expire" }
    }]
  })
}
