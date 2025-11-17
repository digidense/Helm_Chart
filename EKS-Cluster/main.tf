##############################################################
# EKS Cluster Resources
##############################################################

# EKS Cluster
resource "aws_eks_cluster" "cluster" {
  name                          = var.cluster_name
  version                       = var.cluster_version
  role_arn                      = var.cluster_role_arn
  bootstrap_self_managed_addons = false

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = var.endpoint_private_access
    endpoint_public_access  = var.endpoint_public_access
    security_group_ids      = var.additional_security_group_ids
  }

  dynamic "encryption_config" {
    for_each = var.cluster_encryption_config
    content {
      provider {
        key_arn = encryption_config.value.provider_key_arn
      }
      resources = encryption_config.value.resources
    }
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  tags     = var.tags
  tags_all = var.tags_all
  lifecycle {
    ignore_changes = [role_arn]
  }
}

# Launch Templates for custom OS nodes
resource "aws_launch_template" "custom_nodes" {
  for_each = { for k, v in var.node_groups : k => v if !contains(["bottlerocket", "amazon_linux"], lookup(v, "os_type", "ubuntu")) }

  name = each.value.launch_template_name

  image_id      = each.value.ubuntu_ami_id
  instance_type = each.value.instance_types[0]

  vpc_security_group_ids = var.node_security_group_ids

  user_data = lookup(each.value, "user_data", null) != null ? base64encode(each.value.user_data) : (
    coalesce(lookup(each.value, "use_bootstrap", null), true) ? base64encode(templatefile("${path.module}/userdata/cloud-config.yaml", {
      cluster_name = var.cluster_name
      endpoint     = aws_eks_cluster.cluster.endpoint
      ca_data      = aws_eks_cluster.cluster.certificate_authority[0].data
    })) : null
  )

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size = each.value.disk_size
      volume_type = "gp3"
      encrypted   = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
      Name = "${var.cluster_name}-${each.key}-node"
    })
  }
  dynamic "capacity_reservation_specification" {
    for_each = each.value.capacity_reservation_id != null ? [each.value.capacity_reservation_id] : []
    content {
      capacity_reservation_target {
        capacity_reservation_id = each.value.capacity_reservation_id
      }
    }
  }

  # dynamic "placement" {
  #   for_each = each.value.availability_zone != null ? [each.value.availability_zone] : []
  #   content {
  #     availability_zone = each.value.availability_zone
  #   }
  # }

  tags     = var.tags
  tags_all = var.tags_all
}



# EKS Node Groups
resource "aws_eks_node_group" "node_groups" {
  for_each = var.node_groups

  cluster_name    = aws_eks_cluster.cluster.name
  node_group_name = each.key
  node_role_arn   = var.node_role_arn
  subnet_ids      = length(each.value.availability_zone) == 0 ? var.subnet_ids : each.value.availability_zone

  capacity_type = each.value.capacity_type

  scaling_config {
    desired_size = each.value.desired_size
    max_size     = each.value.max_size
    min_size     = each.value.min_size
  }

  update_config {
    max_unavailable = 1
  }



  # Use launch template for custom OS types
  dynamic "launch_template" {
    for_each = contains(["bottlerocket", "amazon_linux"], lookup(each.value, "os_type", "ubuntu")) ? [] : [1]
    content {
      id      = aws_launch_template.custom_nodes[each.key].id
      version = each.value.launch_template_version
    }
  }

  # Use managed AMI for bottlerocket and amazon_linux
  ami_type       = lookup(each.value, "ami_type", null)
  disk_size      = contains(["bottlerocket", "amazon_linux"], lookup(each.value, "os_type", "ubuntu")) ? each.value.disk_size : null
  instance_types = contains(["bottlerocket", "amazon_linux"], lookup(each.value, "os_type", "ubuntu")) ? each.value.instance_types : null

  tags = merge(var.tags, {
    "kubernetes.io/cluster/${aws_eks_cluster.cluster.name}"     = "owned"
    "k8s.io/cluster-autoscaler/enabled"                         = "true"
    "k8s.io/cluster-autoscaler/${aws_eks_cluster.cluster.name}" = "owned"
  })

  lifecycle {
    ignore_changes = [node_role_arn]
  }
  depends_on = [aws_launch_template.custom_nodes]
}

# OIDC Provider (conditional)
data "tls_certificate" "eks" {
  count = var.create_oidc_provider ? 1 : 0
  url   = aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  count = var.create_oidc_provider ? 1 : 0

  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks[0].certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.cluster.identity[0].oidc[0].issuer

  tags     = var.tags
  tags_all = var.tags_all
}


# data "aws_iam_openid_connect_provider" "eks" {
#   count = var.create_oidc_provider ? 1 : 0
#   url = aws_eks_cluster.cluster.identity[0].oidc[0].issuer
# }

# EKS Add-ons
resource "aws_eks_addon" "addons" {
  for_each = var.cluster_addons

  cluster_name                = aws_eks_cluster.cluster.name
  addon_name                  = each.key
  addon_version               = each.value.version
  service_account_role_arn    = each.value.service_account_role_arn
  configuration_values        = each.value.configuration_values
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.node_groups]
}

resource "aws_eks_access_entry" "admin" {
  cluster_name  = aws_eks_cluster.cluster.name
  principal_arn = "arn:aws:iam::123456789012:role/EKSAdminRole"
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "admin_policy" {
  cluster_name  = aws_eks_cluster.cluster.name
  principal_arn = aws_eks_access_entry.admin.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type       = "cluster"
    namespaces = []
  }

  depends_on = [aws_eks_access_entry.admin]
}

##############################################################
# LOCALS: FLATTEN ACCESS POLICIES
##############################################################
locals {
  # Build list of associations
  eks_access_policy_associations_list = flatten([
    for access_key, entry in var.eks_access_entries : [
      for idx, pol in entry.policies : {
        key           = "${access_key}-${idx}"
        principal_arn = entry.principal_arn
        policy_arn    = pol.policy_arn
        access_scope  = pol.access_scope
      }
    ]
  ])

  # Convert list to map for for_each
  eks_access_policy_associations = {
    for assoc in local.eks_access_policy_associations_list :
    assoc.key => assoc
  }
}

##############################################################
# EKS ACCESS ENTRIES
##############################################################
resource "aws_eks_access_entry" "this" {
  for_each = var.eks_access_entries

  cluster_name  = aws_eks_cluster.cluster.name
  principal_arn = each.value.principal_arn
  type          = each.value.type
}

##############################################################
# EKS ACCESS POLICY ASSOCIATIONS
##############################################################
resource "aws_eks_access_policy_association" "this" {
  for_each = local.eks_access_policy_associations

  cluster_name  = aws_eks_cluster.cluster.name
  principal_arn = each.value.principal_arn
  policy_arn    = each.value.policy_arn

  access_scope {
    type       = each.value.access_scope.type
    namespaces = each.value.access_scope.namespaces
  }

  depends_on = [
    aws_eks_access_entry.this
  ]
}
