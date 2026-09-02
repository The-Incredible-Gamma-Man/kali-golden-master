#!/usr/bin/env bash
# Destroy an engagement clone at close: power off, remove VM + storage + hosts entry.
# Host storage is full-disk LUKS -> deletion = unrecoverable at rest; no shred needed.
set -euo pipefail
ID="${1:?usage: close-engagement <client-id>}"; NAME="eng-${ID}"

# Evidence guard: refuse to destroy unexported work.
DEST="${GOLDEN_ARCHIVE:-$HOME/engagements-archive}"
if ls "$DEST/${ID}-"*.tar.gz >/dev/null 2>&1; then
  echo "[i] evidence export present: $(ls -1 "$DEST/${ID}-"*.tar.gz | tail -1)"
else
  echo "!! No evidence export found for '$ID' in $DEST"
  echo "   Everything on this clone (CherryTree notes, loot, report) is about to be destroyed"
  echo "   PERMANENTLY. Export it first:   export-engagement.sh $ID"
  read -rp "Destroy anyway WITHOUT an evidence export? type 'destroy-without-export': " G
  [ "$G" = "destroy-without-export" ] || { echo "aborted - export first (good call)."; exit 1; }
fi

read -rp "Destroy $NAME and ALL its storage permanently? type the id to confirm: " C
[ "$C" = "$ID" ] || { echo "aborted"; exit 1; }
sudo virsh destroy "$NAME" 2>/dev/null || true
sudo virsh undefine "$NAME" --remove-all-storage --snapshots-metadata 2>/dev/null \
  || sudo virsh undefine "$NAME" --remove-all-storage
sudo sed -i "/[[:space:]]${NAME}\$/d" /etc/hosts
echo "[+] $NAME destroyed (VM, disk, snapshots, hosts entry). Store is LUKS-encrypted."
