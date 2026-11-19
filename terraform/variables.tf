#########################################################################
# AUTENTICAÇÃO NO OLVM
# Injetada pelo Jenkins via TF_VAR_ (credenciais olvm-*). Nunca no tfvars.
#########################################################################

variable "ovirt_url" {
  description = "URL da API do OLVM Engine (ex: https://olvm.mvrc.lan/ovirt-engine/api)"
  type        = string
  sensitive   = true
}

variable "ovirt_username" {
  description = "Usuário do OLVM (ex: jenkins@mvrc.local@internalsso)"
  type        = string
  sensitive   = true
}

variable "ovirt_password" {
  description = "Senha do usuário do OLVM"
  type        = string
  sensitive   = true
}

# Certificado self-signed do Engine (lab). Em produção: false + tls_ca_files.
variable "ovirt_tls_insecure" {
  description = "Desabilita a validação do certificado TLS do OLVM Engine"
  type        = bool
  default     = true
}

#########################################################################
# IDS DO AMBIENTE
# O provider 2.2.0 não tem data source para buscar cluster, vNIC profile
# ou storage domain pelo nome: só aceita UUID. São IDs internos do
# ambiente, então vêm de credenciais do Jenkins, não do repositório.
#########################################################################

variable "cluster_id" {
  description = "UUID do cluster OLVM onde as VMs são criadas"
  type        = string
  sensitive   = true
}

variable "vnic_profile_id" {
  description = "UUID do vNIC profile da rede de provisionamento (ovirtmgmt, DHCP 192.168.31.x). É por ela que o Jenkins fala WinRM com a VM."
  type        = string
  sensitive   = true
}

variable "ad_vnic_profile_id" {
  description = "UUID do vNIC profile da VLAN_AD (rede do controlador de domínio, 172.16.0.x)"
  type        = string
  sensitive   = true
}

variable "data_disk_storage_domain_id" {
  description = "UUID do storage domain do disco D:. NÃO pode ser o hosted_storage (só SuperUser cria disco lá)."
  type        = string
  sensitive   = true
  default     = null
}

#########################################################################
# TEMPLATE
#########################################################################

variable "template_name" {
  description = "Nome do template Windows no OLVM (virtio-win + guest agent, WinRM HTTPS 5986, SEM NIC). Ver README."
  type        = string
}

variable "os_type" {
  description = "Tipo de SO no OLVM (ex: windows_11). null = herda do template. Com 'other', o relógio da VM sobe em UTC e o Windows lê como hora local."
  type        = string
  default     = null
}

#########################################################################
# VM
#########################################################################

variable "vm_name" {
  description = "Nome base da VM no OLVM (vira <vm_name>-01, -02...)"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]+$", var.vm_name))
    error_message = "O OLVM só aceita letras, números, ponto, hífen e underscore no nome da VM."
  }
}

variable "vm_count" {
  description = "Quantidade de VMs"
  type        = number
  default     = 1

  validation {
    condition     = var.vm_count >= 1
    error_message = "vm_count deve ser maior que zero."
  }
}

# O provider exige os três campos de CPU juntos.
variable "cpu_sockets" {
  description = "Sockets de CPU"
  type        = number
  default     = 1
}

variable "cpu_cores" {
  description = "Núcleos por socket"
  type        = number
  default     = 4

  validation {
    condition     = var.cpu_cores >= 1
    error_message = "A VM deve possuir pelo menos um núcleo."
  }
}

variable "cpu_threads" {
  description = "Threads por núcleo"
  type        = number
  default     = 1
}

variable "memory_gb" {
  description = "Memória RAM em GiB (memory = maximum_memory)"
  type        = number
  default     = 4

  validation {
    condition     = var.memory_gb >= 4
    error_message = "O Windows 11 exige pelo menos 4 GiB de RAM."
  }
}

#########################################################################
# DISCO D: (PROGRAMAS)
#########################################################################

variable "data_disk_enabled" {
  description = "Cria e anexa o disco D: (Programas)"
  type        = bool
  default     = true
}

variable "data_disk_size_gb" {
  description = "Tamanho do disco D: em GiB"
  type        = number
  default     = 80

  validation {
    condition     = var.data_disk_size_gb >= 20
    error_message = "O disco D deve possuir pelo menos 20GB."
  }
}

# virtio_scsi exige o driver vioscsi (virtio-win) no template. Template sem
# virtio-win: use sata.
variable "data_disk_interface" {
  description = "Interface do disco D: (virtio_scsi | virtio | sata)"
  type        = string
  default     = "virtio_scsi"

  validation {
    condition     = contains(["virtio_scsi", "virtio", "sata"], var.data_disk_interface)
    error_message = "data_disk_interface precisa ser virtio_scsi, virtio ou sata."
  }
}

#########################################################################
# REDE
#########################################################################

# O guest agent do Windows reporta todas as placas (inclusive 169.254.x.x
# da VLAN_AD antes do IP fixo e 127.0.0.1). Este filtro escolhe o IP da
# rede de provisionamento, que é o que o Jenkins alcança.
variable "provisioning_ip_regex" {
  description = "Regex do IP DHCP da rede de provisionamento (o que o Jenkins usa para o WinRM)"
  type        = string
  default     = "^192\\.168\\.31\\."
}

variable "ad_network_cidr" {
  description = "Rede da VLAN_AD"
  type        = string
  default     = "172.16.0.0/24"
}

variable "static_ip_start" {
  description = "Host do primeiro IP fixo na VLAN_AD (50 -> 172.16.0.50)"
  type        = number
  default     = 50
}
