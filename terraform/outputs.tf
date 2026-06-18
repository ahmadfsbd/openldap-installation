output "ldap_backend_ips" {
  description = "Private IPs of LDAP backend VMs."
  value       = [for port in openstack_networking_port_v2.ldap : port.all_fixed_ips[0]]
}

output "ldap_provider_backend_ip" {
  description = "Private IP of the first LDAP backend VM, used as the initial writable provider."
  value       = openstack_networking_port_v2.ldap[0].all_fixed_ips[0]
}

output "ldap_replica_backend_ips" {
  description = "Private IPs of LDAP read replica VMs."
  value       = slice([for port in openstack_networking_port_v2.ldap : port.all_fixed_ips[0]], 1, length(openstack_networking_port_v2.ldap))
}

output "ldap_lb_vip_address" {
  description = "Private VIP address of the LDAP load balancer."
  value       = openstack_lb_loadbalancer_v2.ldap.vip_address
}

output "ldap_lb_floating_ip" {
  description = "Optional floating IP attached to the LDAP load balancer."
  value       = var.create_floating_ip ? openstack_networking_floatingip_v2.ldap[0].address : null
}

output "ldap_url" {
  description = "LDAP URL to use after DNS is created."
  value       = "ldap://<ldap-dns-name>:389"
}

output "security_group_id" {
  description = "Security group ID for LDAP backends."
  value       = openstack_networking_secgroup_v2.ldap.id
}
