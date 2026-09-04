#!/usr/bin/env bash
# One-command declarative build of the golden master with Packer.
#
# The Kali base image doesn't enable SSH on first boot, so this script prepares an
# SSH-enabled copy (via virt-customize), then hands it to Packer to install the
# toolset and seal the image. Run it from anywhere:  ./packer/build.sh
#
# Requires: packer, libguestfs-tools (virt-customize), qemu-img, curl, p7zip (7z),
# and KVM access (be in the 'kvm'/'libvirt' group, or run with sudo).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
: "${GOLDEN_KEY:=$REPO/build_key}"

# --- preflight: resolve host dependencies in one pass -------------------------
# Install everything the distro provides in a single apt run (instead of failing
# one tool at a time), ensure a working KVM, and give clear guidance for 'packer'
# itself, which ships from HashiCorp rather than the distro repos.
# Set NO_DEPS=1 to only list what's missing instead of installing.
declare -A PKG_FOR=(
  [virt-customize]=libguestfs-tools [qemu-img]=qemu-utils [curl]=curl
  [7z]=p7zip-full [awk]=gawk [ssh-keygen]=openssh-client
  [qemu-system-x86_64]=qemu-system-x86
)
preflight(){
  local b pkgs=()
  for b in "${!PKG_FOR[@]}"; do
    command -v "$b" >/dev/null || pkgs+=("${PKG_FOR[$b]}")
  done
  if [ ${#pkgs[@]} -gt 0 ]; then
    mapfile -t pkgs < <(printf '%s\n' "${pkgs[@]}" | sort -u)
    if [ "${NO_DEPS:-0}" = 1 ] || ! command -v apt-get >/dev/null; then
      echo "Missing host dependencies. Install these and re-run:"; printf '  %s\n' "${pkgs[@]}"
      command -v apt-get >/dev/null && echo "  sudo apt-get install -y ${pkgs[*]}"
      exit 1
    fi
    echo "[preflight] installing host dependencies: ${pkgs[*]}"
    sudo apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkgs[@]}"
  fi

  # packer isn't in the distro repos - point at the official install if absent
  if ! command -v packer >/dev/null; then
    cat <<'EOP'
Packer is required but not installed. Install it from HashiCorp, then re-run:
  wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
  sudo apt-get update && sudo apt-get install -y packer
(See https://developer.hashicorp.com/packer/install for other distros.)
EOP
    exit 1
  fi

  # this script runs qemu/virt-customize without sudo, so the user needs KVM access
  local u="${SUDO_USER:-$USER}" g
  for g in kvm libvirt; do
    getent group "$g" >/dev/null 2>&1 && ! id -nG "$u" 2>/dev/null | grep -qw "$g" \
      && { sudo usermod -aG "$g" "$u" 2>/dev/null \
           && echo "[preflight] added $u to '$g' - log out/in (or run: newgrp $g) before building"; } || true
  done
}
preflight

read -r SHA ARCHIVE < "$REPO/sha.txt"
VER=$(sed -E 's/kali-linux-([0-9.]+)-qemu.*/\1/' <<<"$ARCHIVE")
QCOW="${ARCHIVE%.7z}.qcow2"
URL="https://cdimage.kali.org/kali-${VER}/${ARCHIVE}"
mkdir -p "$HERE/base"

if [ ! -f "$HERE/base/$QCOW" ]; then
  echo "[1/3] downloading + verifying Kali ${VER} base image"
  curl -fSL -o "$HERE/base/$ARCHIVE" "$URL"
  echo "$SHA  $HERE/base/$ARCHIVE" | sha256sum -c -
  7z x -y -o"$HERE/base" "$HERE/base/$ARCHIVE" >/dev/null
else
  echo "[1/3] base image already present, skipping download"
fi

[ -f "$GOLDEN_KEY" ] || ssh-keygen -t ed25519 -N '' -f "$GOLDEN_KEY" -C golden-build
echo "[2/3] preparing base (enable SSH + authorize build key)"
cp -f "$HERE/base/$QCOW" "$HERE/base/prepared.qcow2"
virt-customize -a "$HERE/base/prepared.qcow2" \
  --run-command 'systemctl enable ssh' \
  --ssh-inject "kali:file:${GOLDEN_KEY}.pub" \
  --run-command 'mkdir -p /home/kali/.ssh && chown -R kali:kali /home/kali/.ssh && chmod 700 /home/kali/.ssh'

# choose a password for the 'kali' user (SSH is key-only; this is for console/sudo)
KALI_PW=""
while :; do
  read -rs -p "Set a password for the 'kali' user (blank = keep default 'kali'): " KALI_PW; echo
  [ -z "$KALI_PW" ] && { echo "  (keeping default)"; break; }
  read -rs -p "Confirm: " _pw2; echo
  [ "$KALI_PW" = "$_pw2" ] && break || echo "  didn't match, try again"
done
export PKR_VAR_kali_password="$KALI_PW"

echo "[3/3] packer build (installs the toolset, then seals the image)"
cd "$HERE"
packer init .
packer build -var "base_image=base/prepared.qcow2" -var "ssh_key=$GOLDEN_KEY" kali-golden.pkr.hcl

cat <<EOF

[+] Done. Sealed image: $HERE/output-kali-golden/kali-golden.qcow2
    Move it into your libvirt pool and clone with:  goldenctl new <id>
EOF
