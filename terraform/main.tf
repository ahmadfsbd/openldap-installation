resource "openstack_networking_secgroup_v2" "ldap" {
  name        = "${var.name}-ldap"
  description = "OpenLDAP backend security group"

  lifecycle {
    precondition {
      condition     = length(var.ssh_allowed_cidrs) + length(var.ssh_allowed_security_group_ids) > 0
      error_message = "SSH access requires at least one management CIDR or source security group ID so Ansible can reach the LDAP VMs."
    }

    precondition {
      condition     = length(var.backend_allowed_cidrs) + length(var.backend_allowed_security_group_ids) > 0
      error_message = "Backend LDAP access requires at least one restricted CIDR or source security group ID."
    }
  }
}

# Neutron creates default egress rules for new security groups in this cloud.
# Managing an identical Terraform rule causes SecurityGroupRuleExists conflicts.
resource "openstack_networking_secgroup_rule_v2" "ssh" {
  for_each          = toset(var.ssh_allowed_cidrs)
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = each.value
  security_group_id = openstack_networking_secgroup_v2.ldap.id
}

# Optional alternative to SSH CIDRs. Leave ssh_allowed_security_group_ids empty
# when management access should be controlled only by ssh_allowed_cidrs.
resource "openstack_networking_secgroup_rule_v2" "ssh_remote_group" {
  for_each          = toset(var.ssh_allowed_security_group_ids)
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_group_id   = each.value
  security_group_id = openstack_networking_secgroup_v2.ldap.id
}

resource "openstack_networking_secgroup_rule_v2" "ldap_backend" {
  for_each          = toset(var.backend_allowed_cidrs)
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 389
  port_range_max    = 389
  remote_ip_prefix  = each.value
  security_group_id = openstack_networking_secgroup_v2.ldap.id
}

resource "openstack_networking_secgroup_rule_v2" "ldap_backend_remote_group" {
  for_each          = toset(var.backend_allowed_security_group_ids)
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 389
  port_range_max    = 389
  remote_group_id   = each.value
  security_group_id = openstack_networking_secgroup_v2.ldap.id
}

resource "openstack_networking_secgroup_rule_v2" "ldap_backend_peers" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 389
  port_range_max    = 389
  remote_group_id   = openstack_networking_secgroup_v2.ldap.id
  security_group_id = openstack_networking_secgroup_v2.ldap.id
}

resource "openstack_networking_port_v2" "ldap" {
  count              = var.instance_count
  name               = "${var.name}-${count.index + 1}"
  network_id         = var.network_id
  security_group_ids = [openstack_networking_secgroup_v2.ldap.id]
}

resource "openstack_compute_instance_v2" "ldap" {
  count             = var.instance_count
  name              = "${var.name}-${count.index + 1}"
  image_name        = var.image_name
  flavor_name       = var.flavor_name
  key_pair          = var.key_pair
  availability_zone = var.availability_zone != "" ? var.availability_zone : null
  user_data         = templatefile("${path.module}/templates/cloud-init.yaml.tftpl", {})

  network {
    port = openstack_networking_port_v2.ldap[count.index].id
  }
}

resource "openstack_lb_loadbalancer_v2" "ldap" {
  name          = "${var.name}-lb"
  vip_subnet_id = var.subnet_id
}

resource "openstack_lb_listener_v2" "ldap" {
  name            = "${var.name}-ldap"
  protocol        = "TCP"
  protocol_port   = 389
  loadbalancer_id = openstack_lb_loadbalancer_v2.ldap.id
  allowed_cidrs   = length(var.ldap_allowed_cidrs) > 0 ? var.ldap_allowed_cidrs : null
}

resource "openstack_lb_pool_v2" "ldap" {
  name        = "${var.name}-ldap"
  protocol    = "TCP"
  lb_method   = "ROUND_ROBIN"
  listener_id = openstack_lb_listener_v2.ldap.id
}

resource "openstack_lb_monitor_v2" "ldap" {
  name        = "${var.name}-ldap"
  pool_id     = openstack_lb_pool_v2.ldap.id
  type        = "TCP"
  delay       = 10
  timeout     = 5
  max_retries = 3
}

resource "openstack_lb_member_v2" "ldap" {
  count         = var.instance_count
  pool_id       = openstack_lb_pool_v2.ldap.id
  subnet_id     = var.subnet_id
  address       = openstack_networking_port_v2.ldap[count.index].all_fixed_ips[0]
  protocol_port = 389
}

resource "openstack_networking_floatingip_v2" "ldap" {
  count = var.create_floating_ip ? 1 : 0
  pool  = var.external_network_name
}

resource "openstack_networking_floatingip_associate_v2" "ldap" {
  count       = var.create_floating_ip ? 1 : 0
  floating_ip = openstack_networking_floatingip_v2.ldap[0].address
  port_id     = openstack_lb_loadbalancer_v2.ldap.vip_port_id
}
