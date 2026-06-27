provider "vsphere" {

  user                 = var.vsphere_user
  password             = var.vsphere_password
  vsphere_server       = var.vsphere_server

  allow_unverified_ssl = true

}

data "vsphere_datacenter" "dc" {

  name = var.datacenter

}


data "vsphere_compute_cluster" "cluster" {

  name          = var.cluster
  datacenter_id = data.vsphere_datacenter.dc.id

}

data "vsphere_datastore" "system" {

  name          = var.datastore
  datacenter_id = data.vsphere_datacenter.dc.id

}


data "vsphere_datastore" "programs" {

  name          = var.datastore_programas
  datacenter_id = data.vsphere_datacenter.dc.id

}

###############################################################
# VM Network (DHCP)
###############################################################

data "vsphere_network" "vm_network" {

  name          = var.network_vm
  datacenter_id = data.vsphere_datacenter.dc.id

}

###############################################################
# VLAN Active Directory
###############################################################

data "vsphere_network" "ad_network" {

  name          = var.network_ad
  datacenter_id = data.vsphere_datacenter.dc.id

}

###############################################################
# Template Windows
###############################################################

data "vsphere_virtual_machine" "template" {

  name          = var.template_name
  datacenter_id = data.vsphere_datacenter.dc.id

}

###############################################################
# Virtual Machine
###############################################################

resource "vsphere_virtual_machine" "vm" {

  count = var.vm_count

  name = format(
    "%s-%02d",
    var.vm_name,
    count.index + 1
  )

  resource_pool_id = data.vsphere_compute_cluster.cluster.resource_pool_id

  datastore_id = data.vsphere_datastore.system.id

  guest_id = data.vsphere_virtual_machine.template.guest_id

  firmware = data.vsphere_virtual_machine.template.firmware

  scsi_type = data.vsphere_virtual_machine.template.scsi_type

  num_cpus = var.num_cpus

  memory = var.memory_mb

  enable_disk_uuid = true

  wait_for_guest_ip_timeout  = 10

  wait_for_guest_net_timeout = 10

  #############################################################
  # NIC 1
  # DHCP
  #############################################################

  network_interface {

    network_id = data.vsphere_network.vm_network.id

    adapter_type = data.vsphere_virtual_machine.template.network_interface_types[0]

  }

  #############################################################
  # NIC 2
  # VLAN AD
  #############################################################

  network_interface {

    network_id = data.vsphere_network.ad_network.id

    adapter_type = data.vsphere_virtual_machine.template.network_interface_types[0]

  }

  #############################################################
  # Disco C
  #############################################################

  disk {

    label = "disk0"

    size = data.vsphere_virtual_machine.template.disks[0].size

    thin_provisioned = data.vsphere_virtual_machine.template.disks[0].thin_provisioned

    eagerly_scrub = data.vsphere_virtual_machine.template.disks[0].eagerly_scrub

    unit_number = 0

  }

  #############################################################
  # Disco D
  #############################################################

  disk {

    label = "disk1"

    datastore_id = data.vsphere_datastore.programs.id

    size = var.disk_d_size_gb

    thin_provisioned = true

    eagerly_scrub = false

    unit_number = 1

  }

  #############################################################
  # Clone
  #############################################################

  clone {

    template_uuid = data.vsphere_virtual_machine.template.id

  }

  #############################################################
  # Lifecycle
  #############################################################

  lifecycle {

    ignore_changes = [

      annotation,

      extra_config

    ]

  }

}