output "vms_names" {
  description = "Nomes das VMs criadas no OLVM"
  value       = ovirt_vm.vm[*].name
}

output "vms_dhcp_ips" {
  description = "IPs DHCP da rede de provisionamento (usados pelo Jenkins/Ansible via WinRM). null = ainda sem IP."
  value       = local.dhcp_ips
}

output "vms_static_ips" {
  description = "IPs fixos de cada VM na VLAN_AD"
  value       = local.static_ips
}

# Inventário pronto para o Ansible: o Jenkins grava este JSON em
# ansible/inventory/generated.json (o plugin yaml do Ansible lê JSON).
output "ansible_inventory" {
  description = "Inventário Ansible (grupo windows) com IP de conexão e IP fixo de cada VM"
  value = {
    all = {
      children = {
        windows = {
          hosts = {
            for i, name in local.vm_names : name => {
              ansible_host     = local.dhcp_ips[i]
              static_ip        = local.static_ips[i]
              ad_prefix_length = local.ad_prefix_length
            }
          }
        }
      }
    }
  }
}
