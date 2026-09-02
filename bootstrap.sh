#!/usr/bin/env bash
# bootstrap.sh - build the Kali golden master from scratch, in one command (online).
#
# Downloads the pinned Kali base QEMU image (verified against sha.txt), imports it
# as a libvirt VM, injects a host SSH key, runs provision-golden.sh inside it, and
# leaves you a master ready to seal (clean-master.sh) and clone.
#
# Requires connectivity (apt/PyPI/GitHub). Config via env:
#   GOLDEN_MASTER  domain name          (kali-golden)
#   GOLDEN_POOL    image directory      (/var/lib/libvirt/images/golden)
#   GOLDEN_KEY     host->guest SSH key  (~/.ssh/kali-golden_build_key)
#   VM_RAM_MB / VM_VCPUS                (12288 / 8)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
: "${GOLDEN_MASTER:=kali-golden}"
: "${GOLDEN_POOL:=/var/lib/libvirt/images/golden}"
: "${GOLDEN_KEY:=$HOME/.ssh/kali-golden_build_key}"
: "${VM_RAM_MB:=12288}"; : "${VM_VCPUS:=8}"
SSHOPTS=(-i "$GOLDEN_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)

need(){ command -v "$1" >/dev/null || { echo "missing dependency: $1"; exit 1; }; }
for b in virsh virt-install virt-customize qemu-img curl 7z awk; do need "$b"; done
[ -f "$HERE/sha.txt" ] || { echo "sha.txt not found next to bootstrap.sh"; exit 1; }

read -r SHA ARCHIVE < "$HERE/sha.txt"          # "<sha256>  kali-...-qemu-amd64.7z"
VER=$(sed -E 's/kali-linux-([0-9.]+)-qemu.*/\1/' <<<"$ARCHIVE")
QCOW="${ARCHIVE%.7z}.qcow2"
URL="https://cdimage.kali.org/kali-${VER}/${ARCHIVE}"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

echo "[1/5] fetching Kali ${VER} base image"
curl -fSL -o "$WORK/$ARCHIVE" "$URL"
echo "$SHA  $WORK/$ARCHIVE" | sha256sum -c - || { echo "CHECKSUM MISMATCH - aborting"; exit 1; }
7z x -y -o"$WORK" "$WORK/$ARCHIVE" >/dev/null

echo "[2/5] placing image in pool + generating build key"
sudo mkdir -p "$GOLDEN_POOL"
sudo cp --sparse=always "$WORK/$QCOW" "$GOLDEN_POOL/${GOLDEN_MASTER}.qcow2"
[ -f "$GOLDEN_KEY" ] || ssh-keygen -t ed25519 -N '' -f "$GOLDEN_KEY" -C golden-build
sudo virt-customize -a "$GOLDEN_POOL/${GOLDEN_MASTER}.qcow2" \
  --hostname "$GOLDEN_MASTER" \
  --run-command 'systemctl enable ssh' \
  --ssh-inject "kali:file:${GOLDEN_KEY}.pub" \
  --run-command 'mkdir -p /home/kali/.ssh && chown -R kali:kali /home/kali/.ssh && chmod 700 /home/kali/.ssh'

echo "[3/5] defining + starting the VM"
sudo virt-install --name "$GOLDEN_MASTER" --memory "$VM_RAM_MB" --vcpus "$VM_VCPUS" \
  --cpu host-passthrough \
  --disk "path=$GOLDEN_POOL/${GOLDEN_MASTER}.qcow2,format=qcow2,bus=virtio" --import \
  --os-variant detect=on,require=off --network network=default,model=virtio \
  --graphics vnc,listen=127.0.0.1 --noautoconsole

echo "[4/5] waiting for the VM to come up"
IP=""; for _ in $(seq 1 40); do IP=$(sudo virsh -q domifaddr "$GOLDEN_MASTER" | awk '{print $4}' | cut -d/ -f1 | head -1); [ -n "$IP" ] && break; sleep 4; done
[ -n "$IP" ] || { echo "VM did not get an address"; exit 1; }
for _ in $(seq 1 15); do ssh "${SSHOPTS[@]}" -o ConnectTimeout=5 "kali@$IP" true 2>/dev/null && break; sleep 4; done

echo "[5/5] provisioning the toolset (this is the long part)"
# passwordless sudo for the build window (default kali password), then provision
ssh "${SSHOPTS[@]}" "kali@$IP" 'echo kali | sudo -S bash -c "echo \"kali ALL=(ALL) NOPASSWD:ALL\" >/etc/sudoers.d/99-build; chmod 440 /etc/sudoers.d/99-build"' || true
scp "${SSHOPTS[@]}" "$HERE/provision-golden.sh" "$HERE/clean-master.sh" "$HERE/harden.sh" "kali@$IP:/tmp/"
ssh "${SSHOPTS[@]}" "kali@$IP" 'sudo bash /tmp/provision-golden.sh'
# choose a password for the 'kali' user (SSH is key-only, so this is for console/sudo)
KALI_PW=""
while :; do
  read -rs -p "Set a password for the 'kali' user (blank = keep default 'kali'): " KALI_PW; echo
  [ -z "$KALI_PW" ] && { echo "  (keeping default)"; break; }
  read -rs -p "Confirm: " _pw2; echo
  [ "$KALI_PW" = "$_pw2" ] && break || echo "  didn't match, try again"
done
echo "[*] sealing + hardening (this removes the build-time passwordless sudo)"
ssh "${SSHOPTS[@]}" "kali@$IP" 'sudo bash /tmp/clean-master.sh'
printf '%s\n' "$KALI_PW" | ssh "${SSHOPTS[@]}" "kali@$IP" 'sudo bash /tmp/harden.sh'
ssh "${SSHOPTS[@]}" "kali@$IP" 'rm -f /tmp/clean-master.sh /tmp/harden.sh' 2>/dev/null || true

cat <<EOF

Master '$GOLDEN_MASTER' built, sealed, and HARDENED (address: $IP).
  root locked | key-only SSH | UFW up (no ping) | gateway-only DNS | mDNS/LLMNR/BT off | passwordless sudo removed.
  The 'kali' user keeps its default password for console/sudo - ssh in and run 'passwd' to change it.
Next: copy policies.json + firefox add-ons if wanted (RUNBOOK.md), shut it down, tag it,
      then start engagements with:  goldenctl new <id>
EOF
