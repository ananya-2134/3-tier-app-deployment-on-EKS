# Fetch default VPC
data "aws_vpc" "default" {
  default = true
}

# Fetch default subnets
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# --------------------
# EKS Cluster
# --------------------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.8.5"

  cluster_name    = var.cluster_name
  cluster_version = "1.29"
  
  cluster_endpoint_private_access = false
  cluster_endpoint_public_access = true

  subnet_ids = data.aws_subnets.default.ids
  vpc_id     = data.aws_vpc.default.id

  enable_irsa = true
  cluster_encryption_config = [ ]
  create_kms_key  = false
  create_cloudwatch_log_group = false
  eks_managed_node_groups = {
    default = {
      instance_types = ["t3.medium"]
      desired_size   = 2
    }
  }
}

# --------------------
# EBS CSI Driver IRSA
# --------------------
module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version = "5.34.0"

  create_role = true
  role_name   = "${var.cluster_name}-ebs-csi-role"

  provider_url = module.eks.oidc_provider

  role_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  ]

  oidc_fully_qualified_subjects = [
    "system:serviceaccount:kube-system:ebs-csi-controller-sa"
  ]
}

# Install EBS CSI addon
resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = module.eks.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = module.ebs_csi_irsa.iam_role_arn
}

# --------------------
# AWS Load Balancer Controller IRSA
# --------------------
module "alb_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version = "5.34.0"

  create_role = true
  role_name   = "${var.cluster_name}-alb-role"

  provider_url = module.eks.oidc_provider

  oidc_fully_qualified_subjects = [
    "system:serviceaccount:kube-system:aws-load-balancer-controller"
  ]
}

resource "aws_iam_role_policy" "alb_policy" {
  role   = module.alb_irsa.iam_role_name
  policy = file("${path.module}/alb-policy.json")
}

# --------------------
# Outputs
# --------------------
output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}
