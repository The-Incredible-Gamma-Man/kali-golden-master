#!/usr/bin/env bash
# Destroy an engagement clone at close: power off, remove VM + storage + hosts entry.
# Host storage is full-disk LUKS -> deletion = unrecoverable at rest; no shred needed.
set -euo pipefail
ID="${1:?usage: close-engagement <client-id>}"
[[ "$ID" =~ ^[a-z0-9][a-z0-9-]{0,30}$ ]] \
  || { echo "ERROR: id must be [a-z0-9][a-z0-9-]{0,30} (lowercase letters, digits, hyphens)"; exit 1; }
NAME="eng-${ID}"

# Evidence guard: refuse to destroy unexported work.
# Match BOTH plaintext and age-encrypted exports, and ANCHOR the id to the export
# timestamp (<id>-YYYYMMDDTHHMMSSZ...) so a longer sibling id can't satisfy it -
# e.g. closing 'acme' must not be fooled by an 'acme-corp-<ts>' archive. The
# '.age' variant is listed because encryption deletes the plaintext .tar.gz.
DEST="${GOLDEN_ARCHIVE:-$HOME/engagements-archive}"
TS='20[0-9][0-9][0-1][0-9][0-3][0-9]T[0-2][0-9][0-5][0-9][0-5][0-9]Z'
shopt -s nullglob
EXPORTS=( "$DEST/${ID}-"$TS.tar.gz "$DEST/${ID}-"$TS.tar.gz.age )
shopt -u nullglob
if [ "${#EXPORTS[@]}" -gt 0 ]; then
  latest="${EXPORTS[-1]}"
  # honour export-engagement.sh's own completeness verdict: it still writes an
  # archive on a partial pull but records 'complete: NO' and exits 2 - don't let
  # that satisfy the guard silently.
  meta="${latest%.tar.gz*}.meta.txt"
  if [ -f "$meta" ] && grep -qiE '^complete[[:space:]]*:[[:space:]]*NO' "$meta"; then
    echo "!! Latest export for '$ID' is marked INCOMPLETE: $latest"
    echo "   (transfers failed during export - see $(basename "$meta"))"
    read -rp "Destroy anyway against an INCOMPLETE export? type 'destroy-without-export': " G
    [ "$G" = "destroy-without-export" ] || { echo "aborted - re-export first (good call)."; exit 1; }
  else
    echo "[i] evidence export present: $latest"
  fi
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
