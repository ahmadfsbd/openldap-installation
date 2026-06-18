variable "name" {
  description = "Name prefix for OpenLDAP resources."
  type        = string
  default     = "openldap"
}

variable "instance_count" {
  description = "Number of OpenLDAP backend VMs. The first VM is the writable provider; all additional VMs are read replicas."
  type        = number
  default     = 2

  validation {
    condition     = var.instance_count >= 2
    error_message = "The HA OpenLDAP baseline requires at least two backend VMs."
  }
}

variable "network_id" {
  description = "OpenStack network ID for LDAP VMs and load balancer VIP."
  type        = string
}

variable "subnet_id" {
  description = "OpenStack subnet ID for LDAP VMs and load balancer VIP."
  type        = string
}

variable "image_name" {
  description = "OpenStack image name."
  type        = string
}

variable "flavor_name" {
  description = "OpenStack flavor name for LDAP VMs."
  type        = string
}

variable "key_pair" {
  description = "OpenStack key pair for SSH."
  type        = string
}

variable "ssh_allowed_cidrs" {
  description = "CIDRs allowed to SSH to LDAP VMs."
  type        = list(string)
  default     = []
}

variable "ssh_allowed_security_group_ids" {
  description = "Source security group IDs allowed to SSH to LDAP VMs."
  type        = list(string)
  default     = []
}

variable "ldap_allowed_cidrs" {
  description = "CIDRs allowed to reach the LDAP listener."
  type        = list(string)

  validation {
    condition     = length(var.ldap_allowed_cidrs) > 0
    error_message = "LDAP access must allow at least one client CIDR."
  }
}

variable "backend_allowed_cidrs" {
  description = "CIDRs allowed to reach LDAP backends on 389. Usually the tenant subnet or LB subnet."
  type        = list(string)
  default     = []
}

variable "backend_allowed_security_group_ids" {
  description = "Source security group IDs allowed to reach LDAP backends on 389."
  type        = list(string)
  default     = []
}

variable "availability_zone" {
  description = "Optional OpenStack availability zone."
  type        = string
  default     = ""
}

variable "create_floating_ip" {
  description = "Attach a floating IP to the LDAP load balancer."
  type        = bool
  default     = false
}

variable "external_network_name" {
  description = "External network name for optional floating IP."
  type        = string
  default     = ""
}
