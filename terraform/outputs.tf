###############################################################
# DHCP IPs
###############################################################

output "vms_dhcp_ips" {

  description = "Endereços IP obtidos via DHCP utilizados pelo Jenkins e Ansible."

  value = vsphere_virtual_machine.vm[*].default_ip_address

}

###############################################################
# VM Names
###############################################################

output "vms_names" {

  description = "Lista das máquinas virtuais criadas."

  value = vsphere_virtual_machine.vm[*].name

}

###############################################################
# Static IPs
###############################################################

output "vms_calculated_static_ips" {

  description = "Lista dos IPs estáticos esperados para a VLAN AD."

  value = [
    for i in range(var.vm_count) :
    "172.16.0.${var.static_ip_start + i}"
  ]

}