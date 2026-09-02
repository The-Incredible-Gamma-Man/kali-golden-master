// EXPERIMENTAL declarative build of the golden master (see packer/README.md).
// Uses the pinned Kali QEMU base image as a disk, boots it, provisions the toolset,
// and outputs a sealed qcow2. Validate on your host before relying on it.

packer {
  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = ">= 1.1.0"
    }
  }
}

variable "kali_version" { type = string, default = "2026.2" }
variable "base_sha256"  { type = string } // from ../sha.txt
variable "ssh_pubkey"   { type = string } // path to build_key.pub
variable "ram"          { type = string, default = "12288" }
variable "cpus"         { type = string, default = "8" }

locals {
  archive = "kali-linux-${var.kali_version}-qemu-amd64.7z"
  base    = "kali-linux-${var.kali_version}-qemu-amd64.qcow2"
  url     = "https://cdimage.kali.org/kali-${var.kali_version}/kali-linux-${var.kali_version}-qemu-amd64.7z"
}

source "qemu" "kali-golden" {
  // Treat the downloaded Kali qcow2 as the base disk rather than installing from ISO.
  iso_url          = local.url
  iso_checksum     = "sha256:${var.base_sha256}"
  disk_image       = true
  use_backing_file = false
  format           = "qcow2"
  accelerator      = "kvm"
  memory           = var.ram
  cpus             = var.cpus
  headless         = true
  disk_size        = "80G"

  // The base image ships user kali/kali. SSH must be reachable for provisioning —
  // see packer/README.md for the ssh-enable bootstrap (cloud-init or a pre-step).
  ssh_username     = "kali"
  ssh_private_key_file = "../build_key"
  ssh_timeout      = "20m"

  output_directory = "output-kali-golden"
  vm_name          = "kali-golden.qcow2"
  shutdown_command = "echo kali | sudo -S shutdown -P now"
}

build {
  sources = ["source.qemu.kali-golden"]

  provisioner "file" {
    source      = "../provision-golden.sh"
    destination = "/tmp/provision-golden.sh"
  }

  provisioner "shell" {
    inline = [
      "echo kali | sudo -S bash -c 'echo \"kali ALL=(ALL) NOPASSWD:ALL\" >/etc/sudoers.d/99-build; chmod 440 /etc/sudoers.d/99-build'",
      "sudo bash /tmp/provision-golden.sh",
    ]
  }

  // Generalize / seal
  provisioner "file" {
    source      = "../clean-master.sh"
    destination = "/tmp/clean-master.sh"
  }
  provisioner "shell" {
    inline = ["sudo bash /tmp/clean-master.sh"]
  }
}
