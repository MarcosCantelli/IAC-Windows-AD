provider "vsphere" {
  user                 = var.vsphere_user
  password             = var.vsphere_password
  vsphere_server       = var.vsphere_server
  allow_unverified_ssl = true
}

data "vsphere_datacenter" "dc" {
  name = var.datacenter
}

data "vsphere_datastore" "datastore" {
  name          = var.datastore
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_datastore" "datastore_programas" {
  name          = var.datastore_programas
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_compute_cluster" "cluster" {
  name          = var.cluster
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_virtual_machine" "template" {
  name          = var.template_name
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_network" "network_vm" {
  name          = var.network_vm
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_network" "network_ad" {
  name          = var.network_ad
  datacenter_id = data.vsphere_datacenter.dc.id
}

resource "vsphere_virtual_machine" "vm" {
  count            = var.vm_count
  name             = "${var.vm_name}-${count.index + 1}" # Ex: Win-Server-AD-DEV-1
  resource_pool_id = data.vsphere_compute_cluster.cluster.resource_pool_id
  datastore_id     = data.vsphere_datastore.datastore.id

  num_cpus                   = var.num_cpus
  memory                     = var.memory_mb
  guest_id                   = data.vsphere_virtual_machine.template.guest_id
  
  # Aumentado para dar tempo do Windows subir o sysprep/WinRM no primeiro boot
  wait_for_guest_net_timeout = 10
  wait_for_guest_ip_timeout  = 10

  network_interface {
    network_id   = data.vsphere_network.network_vm.id
    adapter_type = data.vsphere_virtual_machine.template.network_interface_types[0]
  }

  network_interface {
    network_id   = data.vsphere_network.network_ad.id
    adapter_type = data.vsphere_virtual_machine.template.network_interface_types[0]
  }

  disk {
    label            = "disk0"
    size             = data.vsphere_virtual_machine.template.disks.0.size
    eagerly_scrub    = data.vsphere_virtual_machine.template.disks.0.eagerly_scrub
    thin_provisioned = data.vsphere_virtual_machine.template.disks.0.thin_provisioned
    unit_number      = 0
  }

  disk {
    label            = "disk1"
    size             = var.disk_d_size_gb
    datastore_id     = data.vsphere_datastore.datastore_programas.id
    eagerly_scrub    = false
    thin_provisioned = true
    unit_number      = 1
  }

  clone {
    template_uuid = data.vsphere_virtual_machine.template.id
  }
}