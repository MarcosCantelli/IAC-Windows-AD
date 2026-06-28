variable "vsphere_user" {
  description = "Usuário para autenticação no vSphere"
  type = string
  sensitive = true
  nullable = false
}

variable "vsphere_password" {
  description = "Senha para autenticação no vSphere"
  type = string
  sensitive = true
  nullable = false
}

variable "vsphere_server" {
  description = "Endereço do servidor vSphere"
  type = string
  nullable = false
}

variable "datacenter" {
  description = "Nome do Datacenter"
  type = string
  nullable = false
}

variable "cluster" {
  description = "Nome do Cluster"
  type = string
  nullable = false
}

variable "datastore" {
  description = "Datastore do disco do sistema"
  type = string
  nullable = false
}

variable "datastore_programas" {
  description = "Datastore do disco de programas"
  type = string
  nullable = false
}

variable "network_vm" {
  description = "Rede DHCP utilizada durante o provisionamento"
  type = string
  nullable = false
}

variable "network_ad" {
  description = "Rede do Active Directory"
  type = string
  nullable = false
}

variable "ad_prefix_length" {
  type    = number
  default = 24
}

variable "template_name" {
  description = "Nome do template Windows"
  type = string
  nullable = false
}

variable "vm_name" {
  description = "Nome base da VM"
  type = string
  nullable = false
}

variable "vm_count" {
  description = "Quantidade de VMs"
  type = number
  default = 1
  validation {
    condition = var.vm_count >= 1
    error_message = "vm_count deve ser maior que zero."
  }
}

variable "num_cpus" {
  description = "Quantidade de CPUs"
  type = number
  validation {
    condition = var.num_cpus >= 1
    error_message = "A VM deve possuir pelo menos uma CPU."
  }
}

variable "memory_mb" {
  description = "Memória RAM em MB"
  type = number
  validation {
    condition = var.memory_mb >= 2048
    error_message = "A memória mínima recomendada é 2048 MB."
  }
}

variable "disk_d_size_gb" {
  description = "Tamanho do disco D"
  type = number
  default = 80
  validation {
    condition = var.disk_d_size_gb >= 20
    error_message = "O disco D deve possuir pelo menos 20GB."
  }
}

variable "static_ip_start" {
  description = "Primeiro IP da sequência utilizada pelo Ansible"
  type = number
  default = 50
}

variable "ad_gateway" {
  description = "Gateway da VLAN AD"
  type = string
  default = "172.16.0.254"
}

variable "ad_dns_primary" {
  description = "DNS primário"
  type = string
  default = "172.16.0.254"
}

variable "ad_network_cidr" {
  description = "Rede AD"
  type = string
  default = "172.16.0.0/24"
}