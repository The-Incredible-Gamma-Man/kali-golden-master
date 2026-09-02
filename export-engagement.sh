#!/usr/bin/env bash
# Export an engagement's workspace + notes off the clone into a timestamped,
# SHA-256-hashed archive for evidence retention. RUN THIS BEFORE close-engagement.
#
#   export-engagement.sh <client-id> [dest-dir]
#
# Pulls ~/engagements/<id> and any CherryTree (*.ctb) notes from the clone, writes
# a per-file hash manifest, tars it, and hashes the archive. Works whether the
# clone is running (over SSH) or shut off (offline via virt-copy-out).
set -euo pipefail
ID="${1:?usage: export-engagement.sh <client-id> [dest-dir]}"
DEST="${2:-${GOLDEN_ARCHIVE:-$HOME/engagements-archive}}"
NAME="eng-${ID}"
KEY="${GOLDEN_KEY:-$HOME/.ssh/kali-golden_build_key}"
SSHOPTS=(-i "$KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)
VIRSH="virsh -c qemu:///system"

TS=$(date -u +%Y%m%dT%H%M%SZ)
STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$DEST"
OUT="$DEST/${ID}-${TS}"

ip=$($VIRSH -q domifaddr "$NAME" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1)
if [ -n "$ip" ]; then
  echo "[*] clone running ($ip) - pulling workspace + notes over SSH"
  scp -r "${SSHOPTS[@]}" "kali@$ip:engagements/$ID" "$STAGE/" 2>/dev/null || echo "  (no workspace dir ~/engagements/$ID)"
  notes=$(ssh "${SSHOPTS[@]}" "kali@$ip" "ls ~/*.ctb ~/Desktop/*.ctb ~/engagements/$ID/*.ctb 2>/dev/null" || true)
  for f in $notes; do scp "${SSHOPTS[@]}" "kali@$ip:$f" "$STAGE/notes-$(basename "$f")" 2>/dev/null || true; done
else
  echo "[*] clone not running - extracting from disk offline (virt-copy-out)"
  disk="/var/lib/libvirt/images/engagements/${NAME}.qcow2"
  [ -f "$disk" ] || { echo "ERROR: no running clone and no disk at $disk"; exit 1; }
  sudo virt-copy-out -a "$disk" "/home/kali/engagements/$ID" "$STAGE/" 2>/dev/null || echo "  (workspace not found on disk)"
fi

if [ -z "$(ls -A "$STAGE" 2>/dev/null)" ]; then
  echo "WARNING: nothing was collected for '$ID' - is the id correct / did work land in ~/engagements/$ID ?"
  exit 1
fi

echo "[*] hashing + archiving"
( cd "$STAGE" && find . -type f -exec sha256sum {} \; ) > "$OUT.manifest.sha256"
tar -C "$STAGE" -czf "$OUT.tar.gz" .
sha256sum "$OUT.tar.gz" | awk '{print $1}' > "$OUT.tar.gz.sha256"
cat > "$OUT.meta.txt" <<META
engagement : $ID
exported   : $TS (UTC)
source_vm  : $NAME
archive    : $(basename "$OUT.tar.gz")
sha256     : $(cat "$OUT.tar.gz.sha256")
files      : $(wc -l < "$OUT.manifest.sha256")
META

echo "[+] evidence archive : $OUT.tar.gz"
echo "    archive sha256   : $OUT.tar.gz.sha256"
echo "    per-file manifest: $OUT.manifest.sha256"
echo "    metadata         : $OUT.meta.txt"
echo "    -> safe to close the engagement now: close-engagement.sh $ID"
