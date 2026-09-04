# Packer build (declarative / IaC path)

A declarative, one-command way to build the golden master — an alternative to `../bootstrap.sh`
aimed at reproducible/CI builds. The result is a portable, sealed `kali-golden.qcow2`.

```bash
./packer/build.sh
```

That's it. The script:

1. Downloads and checksum-verifies the pinned Kali base image (from `../sha.txt`).
2. Prepares an SSH-enabled copy with `virt-customize` (the Kali base doesn't enable SSH on first
   boot, and Packer needs SSH to run its provisioners).
3. Runs `packer build`, which installs the toolset (`provision-golden.sh`) and seals the image
   (`clean-master.sh`).

Output lands in `packer/output-kali-golden/kali-golden.qcow2`, ready to drop into your libvirt pool
and clone with `goldenctl new <id>`.

## Requirements

Just a Linux host with KVM. `build.sh` installs everything it can on first run and adds you to the
`kvm` group if needed. The only thing it can't fetch for you is **Packer** itself (it comes from
HashiCorp, not the distro) — if it's missing, the script prints the exact install commands and exits.

## Notes

- The `.pkr.hcl` uses the standard qemu `disk_image` pattern; `build.sh` supplies the prepared base
  and the SSH key as variables, so no secrets live in the HCL.
- This path is validated for HCL correctness; give it a dry run on your host before relying on it in
  CI, since Packer/qemu behaviour varies a little by version and host.
- Prefer `../bootstrap.sh` if you just want the master built directly into libvirt without producing
  a separate image artifact.
