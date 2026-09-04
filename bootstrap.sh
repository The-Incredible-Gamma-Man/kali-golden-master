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

# --- preflight: resolve host dependencies and bring libvirt up ----------------
# A fresh Debian/Ubuntu host is missing more than a few binaries, and installing
# only the *clients* still leaves virsh/virt-install talking to a libvirt socket
# that was never created. Resolve everything in one pass: map each required
# command to its apt package, add the daemon + KVM emulator (which have no handy
# 'command' to probe), install the lot, then start libvirtd + the default net.
# Set NO_DEPS=1 to skip auto-install and just be told what's missing.
declare -A PKG_FOR=(
  [virsh]=libvirt-clients [virt-install]=virtinst [virt-customize]=libguestfs-tools
  [qemu-img]=qemu-utils [curl]=curl [7z]=p7zip-full [awk]=gawk
)
preflight(){
  local b pkgs=() missing=()
  for b in "${!PKG_FOR[@]}"; do
    command -v "$b" >/dev/null || { missing+=("$b"); pkgs+=("${PKG_FOR[$b]}"); }
  done
  # daemon + emulator: absence shows up only as the "libvirt-sock: No such file" error
  systemctl list-unit-files libvirtd.service >/dev/null 2>&1 || pkgs+=(libvirt-daemon-system)
  command -v qemu-system-x86_64 >/dev/null || pkgs+=(qemu-system-x86)

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

  # start the daemon (monolithic or modular) and wait for it to actually answer
  sudo systemctl enable --now libvirtd 2>/dev/null \
    || sudo systemctl enable --now virtqemud virtnetworkd 2>/dev/null || true
  local up=0; for _ in $(seq 1 10); do
    sudo virsh -c qemu:///system uri >/dev/null 2>&1 && { up=1; break; }; sleep 1
  done
  [ "$up" = 1 ] || { echo "libvirt daemon did not come up - check 'systemctl status libvirtd'"; exit 1; }

  # ensure the default NAT network exists, runs, and autostarts (VM needs it)
  sudo virsh net-info default >/dev/null 2>&1 \
    || sudo virsh net-define /usr/share/libvirt/networks/default.xml 2>/dev/null || true
  sudo virsh net-start default 2>/dev/null || true
  sudo virsh net-autostart default 2>/dev/null || true

  # let the invoking user drive virsh without sudo next time (takes effect on relogin)
  local u="${SUDO_USER:-$USER}" g
  for g in libvirt kvm; do
    getent group "$g" >/dev/null 2>&1 && ! id -nG "$u" 2>/dev/null | grep -qw "$g" \
      && sudo usermod -aG "$g" "$u" 2>/dev/null || true
  done
}
preflight
[ -f "$HERE/sha.txt" ] || { echo "sha.txt not found next to bootstrap.sh"; exit 1; }

read -r SHA ARCHIVE < "$HERE/sha.txt"          # "<sha256>  kali-...-qemu-amd64.7z"
VER=$(sed -E 's/kali-linux-([0-9.]+)-qemu.*/\1/' <<<"$ARCHIVE")
QCOW="${ARCHIVE%.7z}.qcow2"
URL="https://cdimage.kali.org/kali-${VER}/${ARCHIVE}"
# The base archive (~4GB) plus its extracted qcow2 need ~15GB of scratch space.
# The default /tmp is often a small tmpfs (typical on WSL/systemd hosts), so pick
# the first of $TMPDIR, /var/tmp, /tmp that actually has room. Override with TMPDIR.
pick_scratch(){
  local need_kb=$((15*1024*1024)) d avail
  for d in "${TMPDIR:-}" /var/tmp /tmp; do
    [ -n "$d" ] && [ -d "$d" ] && [ -w "$d" ] || continue
    avail=$(df -Pk "$d" 2>/dev/null | awk 'NR==2{print $4}')
    [ "${avail:-0}" -ge "$need_kb" ] && { echo "$d"; return 0; }
  done
  echo "no scratch dir with ~15GB free (checked ${TMPDIR:+$TMPDIR, }/var/tmp, /tmp)" >&2
  echo "free up space or point TMPDIR at a roomier filesystem, then re-run" >&2
  exit 1
}
SCRATCH="$(pick_scratch)"    # set -e aborts here if none has room
WORK="$(mktemp -d -p "$SCRATCH")"; trap 'rm -rf "$WORK"' EXIT

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
scp "${SSHOPTS[@]}" "$HERE/provision-golden.sh" "$HERE/clean-master.sh" "$HERE/harden.sh" \
    "$HERE/firefox-setup.sh" "$HERE/policies.json" "$HERE/foxyproxy-import.json" "$HERE/PROXY-SETUP.txt" \
    "kali@$IP:/tmp/"
ssh "${SSHOPTS[@]}" "kali@$IP" 'sudo bash /tmp/provision-golden.sh'
echo "[*] installing Firefox policy (bookmarks + extensions)"
ssh "${SSHOPTS[@]}" "kali@$IP" 'sudo bash /tmp/firefox-setup.sh'
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
