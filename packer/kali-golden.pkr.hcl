// One-command declarative build of the golden master.
// Driven by build.sh, which prepares an SSH-enabled base image (via virt-customize)
// and passes it in as var.base_image. Packer then provisions the toolset and seals it.

packer {
  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = ">= 1.1.0"
    }
  }
}

variable "base_image" {
  type        = string
  description = "Path to the SSH-enabled Kali base qcow2 (prepared by build.sh)."
}

variable "ssh_key" {
  type        = string
  description = "Private SSH key whose public half is authorized in the base image."
}

variable "ram" {
  type    = string
  default = "12288"
}

variable "cpus" {
  type    = string
  default = "8"
}

source "qemu" "kali-golden" {
  iso_url              = var.base_image
  iso_checksum         = "none"
  disk_image           = true
  format               = "qcow2"
  accelerator          = "kvm"
  memory               = var.ram
  cpus                 = var.cpus
  headless             = true
  disk_size            = "80G"
  ssh_username         = "kali"
  ssh_private_key_file = var.ssh_key
  ssh_timeout          = "20m"
  output_directory     = "output-kali-golden"
  vm_name              = "kali-golden.qcow2"
  shutdown_command     = "echo kali | sudo -S shutdown -P now"
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

  provisioner "file" {
    source      = "../clean-master.sh"
    destination = "/tmp/clean-master.sh"
  }

  provisioner "shell" {
    inline = ["sudo bash /tmp/clean-master.sh"]
  }

  # Harden LAST — this removes the build-time passwordless sudo.
  provisioner "file" {
    source      = "../harden.sh"
    destination = "/tmp/harden.sh"
  }

  provisioner "shell" {
    inline = ["sudo bash /tmp/harden.sh"]
  }
}
