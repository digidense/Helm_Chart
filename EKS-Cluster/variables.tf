variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.28"
}

variable "subnet_ids" {
  description = "List of subnet IDs"
  type        = list(string)
}

variable "endpoint_private_access" {
  description = "Enable private API server endpoint"
  type        = bool
  default     = true
}

variable "endpoint_public_access" {
  description = "Enable public API server endpoint"
  type        = bool
  default     = false
}

variable "cluster_role_arn" {
  description = "ARN of the EKS cluster IAM role"
  type        = string
}

variable "node_role_arn" {
  description = "ARN of the EKS node group IAM role"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where EKS cluster will be created"
  type        = string
}

variable "node_security_group_ids" {
  description = "List of security group IDs for node groups"
  type        = list(string)
}

variable "additional_security_group_ids" {
  description = "Additional security group IDs"
  type        = list(string)
  default     = []
}

variable "cluster_encryption_config" {
  type = list(object({
    provider_key_arn = string
    resources        = list(string)
  }))
  default     = []
  description = "Cluster encryption configuration"
}

variable "node_groups" {
  type = map(object({
    instance_types = list(string)
    capacity_type  = string
    min_size      = number
    max_size      = number
    desired_size  = number
    disk_size     = number
    ubuntu_ami_id = optional(string)
    os_type       = optional(string)
    ami_type      = optional(string)
    user_data     = optional(string)
    use_bootstrap = optional(bool)
    launch_template_name = string
    launch_template_version = optional(string, "$Latest")
    capacity_reservation_id = optional(string)
    availability_zone = optional(list(string),[])
  }))
  default     = {}
  description = "EKS node groups configuration"
}

variable "cluster_addons" {
  type = map(object({
    version = string
    service_account_role_arn = optional(string)
    configuration_values = optional(string)
  }))
  default     = {}
  description = "EKS cluster add-ons"
}

variable "create_oidc_provider" {
  description = "Whether to create OIDC provider"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "tags_all" {
  type = map(any)
  description = "Specify all object tags key and value. This applies to all resources."
}

variable "eks_access_entries" {
  description = "EKS access entries for this cluster"
  type = map(object({
    principal_arn = string
    type          = string # STANDARD or SESSION
    policies      = list(object({
      policy_arn   = string
      access_scope = object({
        type       = string          # cluster or namespace
        namespaces = list(string)    # [] if type = cluster
      })
    }))
  }))
  default = {}
}
