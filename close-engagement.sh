#!/usr/bin/env bash
# Destroy an engagement clone at close: power off, remove VM + storage + hosts entry.
# Host storage is full-disk LUKS -> deletion = unrecoverable at rest; no shred needed.
set -euo pipefail
ID="${1:?usage: close-engagement <client-id>}"; NAME="eng-${ID}"
read -rp "Destroy $NAME and ALL its storage permanently? type the id to confirm: " C
[ "$C" = "$ID" ] || { echo "aborted"; exit 1; }
sudo virsh destroy "$NAME" 2>/dev/null || true
sudo virsh undefine "$NAME" --remove-all-storage --snapshots-metadata 2>/dev/null \
  || sudo virsh undefine "$NAME" --remove-all-storage
sudo sed -i "/[[:space:]]${NAME}\$/d" /etc/hosts
echo "[+] $NAME destroyed (VM, disk, snapshots, hosts entry). Store is LUKS-encrypted."
