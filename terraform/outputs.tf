output "vm_ip_address" {
  description = "IP temporario DHCP (VM Network) para conexao inicial do Ansible"
  value       = vsphere_virtual_machine.vm.default_ip_address
}

output "vm_name" {
  description = "Nome da VM criada"
  value       = vsphere_virtual_machine.vm.name
}

output "all_guest_ips" {
  description = "Todos os IPs detectados na VM"
  value       = vsphere_virtual_machine.vm.guest_ip_addresses
}