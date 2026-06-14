vsphere_user = "your_vsphere_username"
vsphere_password = "your_vsphere_password"
vsphere_server = "your_vsphere_server"
datacenter = "your_datacenter_name"
cluster = "your_cluster_name"
network_vm = "VM Network - DHCP"
network_ad = "Active Directory Network"
datastore = "Datastore_C"
datastore_programas = "Datastore_D"
template_name = "Windows Server Template"
vm_name = "Win-Server-AD"
num_cpus = 4
memory_mb = 8192
disk_d_size_gb = 50
vm_count = 1
static_ip_start = 50
ad_gateway = "172.16.0.254"
ad_dns_primary = "172.16.0.254"
ad_network_prefix = {
  "50" : "172.16.0.50",
  "51" : "172.16.0.51"
}