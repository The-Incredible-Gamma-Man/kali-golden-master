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

variable "kali_password" {
  type        = string
  default     = ""
  sensitive   = true
  description = "New password for the 'kali' user; empty keeps the default. Set via PKR_VAR_kali_password."
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
  # password-independent: harden.sh leaves a NOPASSWD power-off rule, so this works
  # even after harden changes the 'kali' password / removes build-time NOPASSWD sudo.
  shutdown_command     = "sudo -n shutdown -P now"
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

  # Firefox policy: bookmarks + Wappalyzer + FoxyProxy (reads /tmp/policies.json)
  provisioner "file" {
    source      = "../firefox-setup.sh"
    destination = "/tmp/firefox-setup.sh"
  }
  provisioner "file" {
    source      = "../policies.json"
    destination = "/tmp/policies.json"
  }
  provisioner "file" {
    source      = "../foxyproxy-import.json"
    destination = "/tmp/foxyproxy-import.json"
  }
  provisioner "file" {
    source      = "../PROXY-SETUP.txt"
    destination = "/tmp/PROXY-SETUP.txt"
  }
  provisioner "shell" {
    inline = ["sudo bash /tmp/firefox-setup.sh"]
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
    # Pass the password via a (sensitive, log-redacted) env var and expand it inside
    # double quotes, instead of interpolating it into a single-quoted shell literal -
    # so a password containing a quote or other metacharacter can't break the command.
    environment_vars = ["GOLDEN_KALI_PW=${var.kali_password}"]
    inline           = ["printf '%s\\n' \"$GOLDEN_KALI_PW\" | sudo bash /tmp/harden.sh"]
  }
}
