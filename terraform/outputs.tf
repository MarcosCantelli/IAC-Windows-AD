output "vms_dhcp_ips" {
  description = "Lista de IPs temporários DHCP (VM Network) para conexão inicial do Ansible"
  value       = vsphere_virtual_machine.vm[*].default_ip_address
}

output "vms_names" {
  description = "Lista de nomes das VMs criadas"
  value       = vsphere_virtual_machine.vm[*].name
}

output "vms_calculated_static_ips" {
  description = "Lista dos IPs estáticos calculados para a rede do AD (pulando o .9 do SQL)"
  value       = [for i in range(var.vm_count) : i >= 8 ? "172.16.0.${i + 2}" : "172.16.0.${i + 1}"]
}