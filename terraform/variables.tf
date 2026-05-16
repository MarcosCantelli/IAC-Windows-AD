variable "vsphere_user" {
  description = "Usuário para autenticação no vSphere"
  type        = string
  sensitive   = true
}

variable "vsphere_password" {
  description = "Senha para autenticação no vSphere"
  type        = string
  sensitive   = true
}

variable "vsphere_server" {
  description = "Endereço do servidor vSphere (IP ou hostname)"
  type        = string
}

variable "datacenter" {
  description = "Nome do Datacenter"
  type        = string
}

variable "cluster" {
  description = "Nome do Cluster"
  type        = string
}

variable "network_vm" {
  description = "Nome da primeira rede (VM Network / DHCP)"
  type        = string
}

variable "network_ad" {
  description = "Nome da rede do Active Directory"
  type        = string
}

variable "datastore" {
  description = "Nome do Datastore para o disco C:"
  type        = string
}

variable "datastore_programas" {
  description = "Nome do Datastore para o disco D: (Programas)"
  type        = string
}

variable "template_name" {
  description = "Nome do Template (Windows Server)"
  type        = string
}

variable "vm_name" {
  description = "Nome da Máquina Virtual"
  type        = string
}

variable "num_cpus" {
  description = "Número de CPUs"
  type        = number
}

variable "memory_mb" {
  description = "Memória em MB"
  type        = number
}

variable "disk_d_size_gb" {
  description = "Tamanho do disco D: em GB para Programas"
  type        = number
  default     = 50
}