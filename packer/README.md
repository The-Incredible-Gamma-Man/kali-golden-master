# Packer build (experimental)

A declarative alternative to `bootstrap.sh` — the direction of travel toward full
infrastructure-as-code. **This is a scaffold, not a turnkey build yet: validate it on your host
before relying on it.** The tested, supported path today is `../bootstrap.sh`.

## Why it's marked experimental

The pinned Kali QEMU base image ships with the `kali/kali` user but **SSH is not enabled on first
boot**, and Packer needs SSH to run provisioners. `bootstrap.sh` solves this by `virt-customize`-ing
the image (enabling SSH + injecting the key) *before* defining the VM. A pure-Packer flow needs one
of:

- a **pre-step** that runs `virt-customize -a <base>.qcow2 --run-command 'systemctl enable ssh'
  --ssh-inject kali:file:../build_key.pub` before `packer build`, or
- a **cloud-init** seed ISO attached at boot to enable SSH and authorize the key, or
- a `boot_command` that logs in on the console and enables `ssh`.

Until one of those is wired in, `packer build` will time out waiting for SSH.

## Usage (once SSH bootstrap is in place)

```bash
# generate the build key if you don't have one
ssh-keygen -t ed25519 -N '' -f ../build_key -C golden-build

packer init .
packer build \
  -var "base_sha256=$(awk '{print $1}' ../sha.txt)" \
  -var "ssh_pubkey=../build_key.pub" \
  kali-golden.pkr.hcl
```

Output lands in `output-kali-golden/kali-golden.qcow2`, ready to move into your libvirt pool and
clone with `goldenctl`.

## Contributions welcome

Wiring in the cloud-init (or virt-customize pre-step) to make this a one-shot `packer build` is the
top open item on the roadmap — PRs appreciated.
