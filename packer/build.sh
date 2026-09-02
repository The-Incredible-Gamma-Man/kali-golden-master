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

need(){ command -v "$1" >/dev/null || { echo "missing dependency: $1"; exit 1; }; }
for b in packer virt-customize qemu-img curl 7z sha256sum awk sed ssh-keygen; do need "$b"; done

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
