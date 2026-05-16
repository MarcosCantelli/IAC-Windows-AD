provider "vsphere" {
  user                 = var.vsphere_user          # Username for vSphere authentication
  password             = var.vsphere_password      # Password for vSphere authentication
  vsphere_server       = var.vsphere_server        # vSphere server address
  allow_unverified_ssl = true                      # Allow insecure SSL connections (useful for self-signed certificates)
}

# Fetch the datacenter information
data "vsphere_datacenter" "dc" {
  name = var.datacenter                              # Name of the datacenter to use
}

# Fetch the datastore information for Disk C: (System)
data "vsphere_datastore" "datastore" {
  name          = var.datastore                      # Name of the datastore for OS
  datacenter_id = data.vsphere_datacenter.dc.id     # Datacenter ID fetched from the datacenter data source
}

# Fetch the datastore information for Disk D: (Programs)
data "vsphere_datastore" "datastore_programas" {
  name          = var.datastore_programas            # Name of the datastore for Programs
  datacenter_id = data.vsphere_datacenter.dc.id     # Datacenter ID fetched from the datacenter data source
}

# Fetch the compute cluster information
data "vsphere_compute_cluster" "cluster" {
  name          = var.cluster                        # Name of the compute cluster to use
  datacenter_id = data.vsphere_datacenter.dc.id     # Datacenter ID fetched from the datacenter data source
}

# Fetch the virtual machine template information
data "vsphere_virtual_machine" "template" {
  name          = var.template_name                  # Name of the VM template to use
  datacenter_id = data.vsphere_datacenter.dc.id     # Datacenter ID fetched from the datacenter data source
}

# Fetch the first network information (VM Network - DHCP)
data "vsphere_network" "network_vm" {
  name          = var.network_vm                     # Name of the standard network
  datacenter_id = data.vsphere_datacenter.dc.id     # Datacenter ID fetched from the datacenter data source
}

# Fetch the second network information (Active Directory Network)
data "vsphere_network" "network_ad" {
  name          = var.network_ad                     # Name of the AD network
  datacenter_id = data.vsphere_datacenter.dc.id     # Datacenter ID fetched from the datacenter data source
}

# Define the virtual machine resource
resource "vsphere_virtual_machine" "vm" {
  name             = var.vm_name
  resource_pool_id = data.vsphere_compute_cluster.cluster.resource_pool_id
  datastore_id     = data.vsphere_datastore.datastore.id # Default datastore for VM configuration files

  num_cpus                   = var.num_cpus
  memory                     = var.memory_mb
  guest_id                   = data.vsphere_virtual_machine.template.guest_id
  
  # Timeouts adjusted for Windows boot and network initialization
  wait_for_guest_net_timeout = 5
  wait_for_guest_ip_timeout  = 10

  # Interface 1: VM Network (DHCP for initial Ansible connection)
  network_interface {
    network_id   = data.vsphere_network.network_vm.id
    adapter_type = data.vsphere_virtual_machine.template.network_interface_types[0]
  }

  # Interface 2: AD Network (To be configured with static IP via Ansible)
  network_interface {
    network_id   = data.vsphere_network.network_ad.id
    adapter_type = data.vsphere_virtual_machine.template.network_interface_types[0]
  }

  # Disk 0: OS Drive (C:\) - Placed in the primary OS datastore
  disk {
    label            = "disk0"
    size             = data.vsphere_virtual_machine.template.disks.0.size
    eagerly_scrub    = data.vsphere_virtual_machine.template.disks.0.eagerly_scrub
    thin_provisioned = data.vsphere_virtual_machine.template.disks.0.thin_provisioned
    unit_number      = 0
  }

  # Disk 1: Programs Drive (D:\) - Placed in the dedicated programs datastore
  disk {
    label            = "disk1"
    size             = var.disk_d_size_gb
    datastore_id     = data.vsphere_datastore.datastore_programas.id
    eagerly_scrub    = false
    thin_provisioned = true
    unit_number      = 1 # Ensures it creates as a secondary disk on the controller
  }

  clone {
    template_uuid = data.vsphere_virtual_machine.template.id
  }
}