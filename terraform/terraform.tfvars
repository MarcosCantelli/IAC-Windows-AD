# ovirt_url, ovirt_username, ovirt_password, cluster_id, vnic_profile_id,
# ad_vnic_profile_id e data_disk_storage_domain_id são injetados pelo
# Jenkins via TF_VAR_ (credenciais olvm-*). NUNCA preencha aqui.

ovirt_tls_insecure = true

# Template Windows 11 no OLVM (ver "Template Windows" no README)
template_name = "W11_25H2_ANSIBLE"

# null = herda do template. Se o template estiver como "other", troque
# para "windows_11" (o relógio da VM passa a subir na hora local).
# os_type = "windows_11"

vm_name     = "Win11_AD"
vm_count    = 1
cpu_sockets = 1
cpu_cores   = 4
cpu_threads = 1
memory_gb   = 4

data_disk_enabled   = true
data_disk_size_gb   = 80
data_disk_interface = "virtio_scsi"

# Rede de provisionamento (ovirtmgmt, DHCP)
provisioning_ip_regex = "^192\\.168\\.31\\."

# VLAN_AD: VM 1 = 172.16.0.50, VM 2 = .51 ...
ad_network_cidr = "172.16.0.0/24"
static_ip_start = 50
