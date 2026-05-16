# Infraestrutura vSphere
vsphere_server = "192.168.31.13"
datacenter     = "MVRC-DC"
cluster        = "Xeon"
datastore      = "VS1_SSD2TB"
datastore_programas = "VS1_HD500GB"

# Ajuste das duas redes
network_vm     = "VM Network"
network_ad     = "VLAN_AD" # 

# Template e VM Windows
template_name  = "W11_25H2_ANSIBLE" # <-- Mudar para o seu template Windows
vm_name        = "Win11_AD"
num_cpus       = 4
memory_mb      = 4096

# Tamanho do Disco D:\
disk_d_size_gb = 80