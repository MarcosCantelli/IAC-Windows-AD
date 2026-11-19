provider "ovirt" {
  url          = var.ovirt_url
  username     = var.ovirt_username
  password     = var.ovirt_password
  tls_insecure = var.ovirt_tls_insecure
}

# Template Windows preparado manualmente no OLVM (ver README): virtio-win
# com o guest agent, WinRM HTTPS na 5986, usuário admin local e SEM placa
# de rede. O disco dele NÃO pode ficar no hosted_storage.
data "ovirt_templates" "windows" {
  name          = var.template_name
  fail_on_empty = true
}

locals {
  vm_names = [for i in range(var.vm_count) : format("%s-%02d", var.vm_name, i + 1)]

  # 172.16.0.50, .51... na VLAN_AD. Aplicados pelo Ansible (role network).
  static_ips = [for i in range(var.vm_count) : cidrhost(var.ad_network_cidr, var.static_ip_start + i)]

  ad_prefix_length = tonumber(split("/", var.ad_network_cidr)[1])
}

resource "ovirt_vm" "vm" {
  count = var.vm_count

  name        = local.vm_names[count.index]
  comment     = "Windows ingressado no AD - provisionado via Terraform/Jenkins"
  cluster_id  = var.cluster_id
  template_id = tolist(data.ovirt_templates.windows.templates)[0].id
  clone       = true
  os_type     = var.os_type

  cpu_sockets = var.cpu_sockets
  cpu_cores   = var.cpu_cores
  cpu_threads = var.cpu_threads

  # memory = maximum_memory: sem isso o OLVM reserva 4x para hotplug.
  # Ballooning desligado: o driver de balloon do Windows é opcional no
  # virtio-win e, sem ele, o host não devolve a memória direito.
  memory            = var.memory_gb * 1024 * 1024 * 1024
  maximum_memory    = var.memory_gb * 1024 * 1024 * 1024
  memory_ballooning = false

  # Sem initialization_* de propósito: no Windows o OLVM usaria sysprep, e
  # isso depende do os_type do template. O hostname, o IP fixo e o domínio
  # são aplicados pelo Ansible via WinRM, igual ao fluxo do vCenter.

  lifecycle {
    precondition {
      condition     = cidrhost(var.ad_network_cidr, var.static_ip_start + var.vm_count - 1) != cidrhost(var.ad_network_cidr, -1)
      error_message = "static_ip_start + vm_count passa do fim da rede ad_network_cidr."
    }
  }
}

#########################################################################
# PLACAS DE REDE
# O provider 2.2.0 não deixa escolher o modelo da placa: ela é sempre
# VirtIO. Por isso o template precisa do driver NetKVM (virtio-win).
#########################################################################

# nic1 - provisionamento (ovirtmgmt, DHCP). Desativada no Windows no fim
# da pipeline (role finalize).
resource "ovirt_nic" "provisioning" {
  count = var.vm_count

  vm_id           = ovirt_vm.vm[count.index].id
  name            = "nic1"
  vnic_profile_id = var.vnic_profile_id
}

# nic2 - VLAN_AD (IP fixo aplicado pelo Ansible). Criada depois da nic1
# para manter a ordem das placas no barramento.
resource "ovirt_nic" "ad" {
  count = var.vm_count

  vm_id           = ovirt_vm.vm[count.index].id
  name            = "nic2"
  vnic_profile_id = var.ad_vnic_profile_id

  depends_on = [ovirt_nic.provisioning]
}

#########################################################################
# DISCO D: (PROGRAMAS)
#########################################################################

resource "ovirt_disk" "data" {
  count = var.data_disk_enabled ? var.vm_count : 0

  alias             = "${local.vm_names[count.index]}-D"
  storage_domain_id = var.data_disk_storage_domain_id
  format            = "cow"
  sparse            = true
  size              = var.data_disk_size_gb * 1024 * 1024 * 1024

  lifecycle {
    precondition {
      condition     = var.data_disk_storage_domain_id != null && var.data_disk_storage_domain_id != ""
      error_message = "data_disk_enabled = true exige data_disk_storage_domain_id (credencial olvm-storage-domain-id)."
    }
  }
}

resource "ovirt_disk_attachment" "data" {
  count = var.data_disk_enabled ? var.vm_count : 0

  vm_id          = ovirt_vm.vm[count.index].id
  disk_id        = ovirt_disk.data[count.index].id
  disk_interface = var.data_disk_interface
  bootable       = false
  active         = true
}

#########################################################################
# LIGAR A VM
# Criar a VM no OLVM não a liga. Só liga depois das placas e do disco D:
# existirem, para o Windows já enxergar tudo no primeiro boot.
#########################################################################

resource "ovirt_vm_start" "vm" {
  count = var.vm_count

  vm_id = ovirt_vm.vm[count.index].id

  # "stop" desliga direto no destroy. O "shutdown" (ACPI) pode ser ignorado
  # pelo Windows na tela de login e deixar o destroy pendurado.
  stop_behavior = "stop"

  depends_on = [
    ovirt_nic.provisioning,
    ovirt_nic.ad,
    ovirt_disk_attachment.data,
  ]
}

# Espera o guest agent (QEMU Guest Agent, do virtio-win) reportar os IPs.
# Sem o guest agent no template, este data source espera para sempre.
data "ovirt_wait_for_ip" "vm" {
  count = var.vm_count

  vm_id = ovirt_vm_start.vm[count.index].vm_id
}

locals {
  # Primeiro IPv4 que casa com provisioning_ip_regex, em qualquer placa.
  # null quando o DHCP ainda não respondeu: o Jenkins refaz a leitura
  # (terraform apply -refresh-only) até aparecer.
  dhcp_ips = [
    for w in data.ovirt_wait_for_ip.vm : try(
      [
        for ip in flatten([for iface in w.interfaces : tolist(iface.ipv4_addresses)]) :
        ip if can(regex(var.provisioning_ip_regex, ip))
      ][0],
      null
    )
  ]
}
