terraform {
  required_providers {
    ovirt = {
      source  = "oVirt/ovirt"
      version = "~> 2.2"
    }
  }
  required_version = ">= 1.5.0"
}
