provider "vsphere" {
  user                 = var.vsphere_user
  password             = var.vsphere_password
  vsphere_server       = var.vsphere_server
  allow_unverified_ssl = true
}

# Fetch the datacenter information
data "vsphere_datacenter" "dc" {
  name = var.datacenter
}

# Fetch the datastore information for Disk C: (System)
data "vsphere_datastore" "datastore" {
  name          = var.datastore
  datacenter_id = data.vsphere_datacenter.dc.id
}

# Fetch the datastore information for Disk D: (Programs)
data "vsphere_datastore" "datastore_programas" {
  name          = var.datastore_programas
  datacenter_id = data.vsphere_datacenter.dc.id
}

# Fetch the compute cluster information
data "vsphere_compute_cluster" "cluster" {
  name          = var.cluster
  datacenter_id = data.vsphere_datacenter.dc.id
}

# Fetch the virtual machine template information
data "vsphere_virtual_machine" "template" {
  name          = var.template_name
  datacenter_id = data.vsphere_datacenter.dc.id
}

# Fetch the first network information (VM Network - DHCP)
data "vsphere_network" "network_vm" {
  name          = var.network_vm
  datacenter_id = data.vsphere_datacenter.dc.id
}

# Fetch the second network information (Active Directory Network)
data "vsphere_network" "network_ad" {
  name          = var.network_ad
  datacenter_id = data.vsphere_datacenter.dc.id
}

# Define the virtual machine resource
resource "vsphere_virtual_machine" "vm" {
  count            = var.vm_count
  name             = "${var.vm_name}-${count.index + 1}" # Ex: Win-Server-AD-DEV-1
  resource_pool_id = data.vsphere_compute_cluster.cluster.resource_pool_id
  datastore_id     = data.vsphere_datastore.datastore.id

  num_cpus                   = var.num_cpus
  memory                     = var.memory_mb
  guest_id                   = data.vsphere_virtual_machine.template.guest_id
  
  # Herda o firmware exato do template (garante compatibilidade BIOS/UEFI)
  firmware                   = data.vsphere_virtual_machine.template.firmware
  
  # Herda o tipo de controladora SCSI exata do template (Evita falhas de I/O do Windows)
  scsi_type                  = data.vsphere_virtual_machine.template.scsi_type

  # Timeouts ajustados para Windows boot e inicialização da rede
  wait_for_guest_net_timeout = 10
  wait_for_guest_ip_timeout  = 10

  # Interface 1: VM Network (DHCP para conexão inicial do Ansible)
  network_interface {
    network_id   = data.vsphere_network.network_vm.id
    adapter_type = data.vsphere_virtual_machine.template.network_interface_types[0]
  }

  # Interface 2: AD Network (Para configuração de IP fixo via Ansible)
  network_interface {
    network_id   = data.vsphere_network.network_ad.id
    adapter_type = data.vsphere_virtual_machine.template.network_interface_types[0]

    # Configuração de IP estático
    ip_address         = var.ad_network_prefix[count.index + var.static_ip_start]
    subnet_mask        = "255.255.255.0"
    default_gateway    = var.ad_gateway
    dns_server_list    = [var.ad_dns_primary]
  }

  # Disk 0: OS Drive (C:\) - Alocado no datastore primário do SO
  disk {
    label            = "disk0"
    size             = data.vsphere_virtual_machine.template.disks.0.size
    eagerly_scrub    = data.vsphere_virtual_machine.template.disks.0.eagerly_scrub
    thin_provisioned = data.vsphere_virtual_machine.template.disks.0.thin_provisioned
    unit_number      = 0 # Fixa na posição mestre de boot
  }

  # Disk 1: Programs Drive (D:\) - Armazenado no datastore de programas
  disk {
    label            = "disk1"
    size             = var.disk_d_size_gb
    datastore_id     = data.vsphere_datastore.datastore_programas.id
    eagerly_scrub    = false
    thin_provisioned = true
    unit_number      = 1 # Posição secundária na controladora
  }

  clone {
    template_uuid = data.vsphere_virtual_machine.template.id
  }
}
