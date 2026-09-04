#!/usr/bin/env bash
# Destroy an engagement clone at close: power off, remove VM + storage + hosts entry.
# Host storage is full-disk LUKS -> deletion = unrecoverable at rest; no shred needed.
set -euo pipefail
ID="${1:?usage: close-engagement <client-id>}"
[[ "$ID" =~ ^[a-z0-9][a-z0-9-]{0,30}$ ]] \
  || { echo "ERROR: id must be [a-z0-9][a-z0-9-]{0,30} (lowercase letters, digits, hyphens)"; exit 1; }
NAME="eng-${ID}"

# Evidence guard: refuse to destroy unexported work.
# Match BOTH plaintext and age-encrypted exports - export-engagement.sh deletes the
# plaintext .tar.gz when GOLDEN_AGE_RECIPIENT is set, so a *.tar.gz-only glob would
# go blind exactly when encryption is on. (Listed explicitly, not *.tar.gz*, so a
# stray .sha256/.asc/.meta can't satisfy the guard by itself.)
DEST="${GOLDEN_ARCHIVE:-$HOME/engagements-archive}"
shopt -s nullglob
EXPORTS=( "$DEST/${ID}-"*.tar.gz "$DEST/${ID}-"*.tar.gz.age )
shopt -u nullglob
if [ "${#EXPORTS[@]}" -gt 0 ]; then
  echo "[i] evidence export present: ${EXPORTS[-1]}"
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
