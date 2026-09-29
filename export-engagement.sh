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
[[ "$ID" =~ ^[a-z0-9][a-z0-9-]{0,30}$ ]] \
  || { echo "ERROR: id must be [a-z0-9][a-z0-9-]{0,30} (lowercase letters, digits, hyphens)"; exit 1; }
DEST="${2:-${GOLDEN_ARCHIVE:-$HOME/engagements-archive}}"
NAME="eng-${ID}"
KEY="${GOLDEN_KEY:-$HOME/.ssh/kali-golden_build_key}"
SSHOPTS=(-i "$KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)
VIRSH="virsh -c qemu:///system"

TS=$(date -u +%Y%m%dT%H%M%SZ)
STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$DEST"
OUT="$DEST/${ID}-${TS}"

ip=$($VIRSH -q domifaddr "$NAME" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1 || true)
# This is the one script where a *silent* failure is unrecoverable (you close the
# VM afterwards), so transfer errors are surfaced loudly and flip COLLECT_OK.
COLLECT_OK=1
if [ -n "$ip" ]; then
  echo "[*] clone running ($ip) - pulling workspace + notes over SSH"
  if scp -r "${SSHOPTS[@]}" "kali@$ip:engagements/$ID" "$STAGE/"; then
    :
  else
    echo "  [!] pull of ~/engagements/$ID failed (rc=$?) - MISSING dir or a PARTIAL/interrupted transfer"
    COLLECT_OK=0
  fi
  # CherryTree notes: enumerate them, distinguishing an SSH TRANSPORT failure (which
  # would silently hide notes) from a genuine "no notes". The trailing remote 'true'
  # makes ssh exit 0 whenever the connection works, so a non-zero rc means transport
  # failed - not that there were no notes. Iterate line-by-line (filenames may contain
  # spaces) rather than word-splitting an unquoted variable.
  set +e
  notes_list=$(ssh "${SSHOPTS[@]}" "kali@$ip" "ls ~/*.ctb ~/Desktop/*.ctb ~/engagements/$ID/*.ctb 2>/dev/null; true")
  ssh_rc=$?
  set -e
  if [ "$ssh_rc" -ne 0 ]; then
    echo "  [!] SSH failed while enumerating notes (rc=$ssh_rc) - notes may be MISSING from this archive"; COLLECT_OK=0
  fi
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if ! scp "${SSHOPTS[@]}" "kali@$ip:$f" "$STAGE/notes-$(basename "$f")"; then
      echo "  [!] failed to pull note: $f"; COLLECT_OK=0
    fi
  done <<< "$notes_list"
  # Sliver C2 server state: loot store, creds/host DB, session + audit logs, certs.
  # Optional - not every engagement uses Sliver, so its ABSENCE is fine and must not
  # flip COLLECT_OK. Exclude the bundled Go + Zig toolchains / traffic-encoders that
  # sliver-server unpacks on first run (~630 MB, not evidence). Build the filtered
  # tar on the clone, pull it, and unpack so each file lands in the manifest.
  set +e
  sliver_have=$(ssh "${SSHOPTS[@]}" "kali@$ip" '[ -d "$HOME/.sliver" ] && echo yes || echo no')
  set -e
  if [ "$sliver_have" = yes ]; then
    mkdir -p "$STAGE/sliver-server-state"
    if ssh "${SSHOPTS[@]}" "kali@$ip" 'tar -C "$HOME" --exclude=.sliver/go --exclude=.sliver/zig --exclude=.sliver/traffic-encoders -czf /tmp/.sliver-evidence.tgz .sliver 2>/dev/null' \
       && scp "${SSHOPTS[@]}" "kali@$ip:/tmp/.sliver-evidence.tgz" "$STAGE/.sv.tgz"; then
      tar -C "$STAGE/sliver-server-state" -xzf "$STAGE/.sv.tgz" && rm -f "$STAGE/.sv.tgz"
      ssh "${SSHOPTS[@]}" "kali@$ip" 'rm -f /tmp/.sliver-evidence.tgz' 2>/dev/null || true
      echo "  [*] captured Sliver server state (loot/creds/logs/certs)"
    else
      echo "  [!] Sliver state present but its capture FAILED"; COLLECT_OK=0
    fi
  else
    echo "  [i] no Sliver server state on clone (~/.sliver absent) - skipping"
  fi
else
  echo "[*] clone not running - extracting from disk offline (virt-copy-out)"
  disk="/var/lib/libvirt/images/engagements/${NAME}.qcow2"
  [ -f "$disk" ] || { echo "ERROR: no running clone and no disk at $disk"; exit 1; }
  if ! sudo virt-copy-out -a "$disk" "/home/kali/engagements/$ID" "$STAGE/"; then
    echo "  [!] virt-copy-out of the workspace failed - archive may be INCOMPLETE"
    COLLECT_OK=0
  fi
  # Sliver C2 server state (optional, see SSH branch). Copy it out, then prune the
  # unpacked Go + Zig toolchains / traffic-encoders. Absence is fine - no COLLECT_OK flip.
  mkdir -p "$STAGE/sliver-server-state"
  if sudo virt-copy-out -a "$disk" "/home/kali/.sliver" "$STAGE/sliver-server-state/" 2>/dev/null; then
    sudo rm -rf "$STAGE/sliver-server-state/.sliver/go" "$STAGE/sliver-server-state/.sliver/zig" "$STAGE/sliver-server-state/.sliver/traffic-encoders" 2>/dev/null || true
    sudo chown -R "$(id -u):$(id -g)" "$STAGE/sliver-server-state" 2>/dev/null || true
    echo "  [*] captured Sliver server state (offline: loot/creds/logs/certs)"
  else
    rmdir "$STAGE/sliver-server-state" 2>/dev/null || true
    echo "  [i] no Sliver server state in image (/home/kali/.sliver absent) - skipping"
  fi
fi

if [ -z "$(ls -A "$STAGE" 2>/dev/null)" ]; then
  echo "WARNING: nothing was collected for '$ID' - is the id correct / did work land in ~/engagements/$ID ?"
  exit 1
fi

echo "[*] hashing + archiving"
( cd "$STAGE" && find . -type f -exec sha256sum {} \; ) > "$OUT.manifest.sha256"
tar -C "$STAGE" -czf "$OUT.tar.gz" .
sha256sum "$OUT.tar.gz" | awk '{print $1}' > "$OUT.tar.gz.sha256"

# --- optional at-rest encryption (BEFORE signing, so the signature covers the
#     final artifact rather than a plaintext we then delete) --------------------
# The archive holds client loot and credentials in plaintext; host FDE only covers
# theft of the powered-off machine. Set GOLDEN_AGE_RECIPIENT=<age pubkey> to encrypt.
ARCHIVE="$OUT.tar.gz"
if [ -n "${GOLDEN_AGE_RECIPIENT:-}" ] && command -v age >/dev/null; then
  if age -r "$GOLDEN_AGE_RECIPIENT" -o "$OUT.tar.gz.age" "$OUT.tar.gz"; then
    rm -f "$OUT.tar.gz"; ARCHIVE="$OUT.tar.gz.age"
    echo "  [*] encrypted at rest -> $(basename "$ARCHIVE") (plaintext removed)"
  else echo "  [!] age encryption FAILED - leaving plaintext archive"; fi
else
  echo "  [!] archive is UNENCRYPTED at rest - it contains loot/creds (set GOLDEN_AGE_RECIPIENT=<age pubkey> to encrypt)"
fi
ARCHIVE_SHA=$(sha256sum "$ARCHIVE" | awk '{print $1}')   # hash of the artifact actually stored

# --- optional chain-of-custody: detach-sign the FINAL archive -----------------
# A bare host-computed hash is not tamper-evident (whoever edits the file recomputes
# it). Signing the artifact-as-stored means a holder of only the ciphertext (e.g. the
# client) can verify it WITHOUT the age key. Set GOLDEN_SIGN_KEY=<gpg key id/email>,
# ideally a key that never lives on the engagement host.
SIG=""
if [ -n "${GOLDEN_SIGN_KEY:-}" ] && command -v gpg >/dev/null; then
  if gpg --local-user "$GOLDEN_SIGN_KEY" --armor --detach-sign --output "$ARCHIVE.asc" "$ARCHIVE"; then
    SIG="$ARCHIVE.asc"
  else echo "  [!] GPG signing FAILED - archive left unsigned"; fi
else
  echo "  [!] archive is UNSIGNED - a bare hash is not tamper-evident (set GOLDEN_SIGN_KEY=<gpg key> to detach-sign)"
fi

cat > "$OUT.meta.txt" <<META
engagement      : $ID
exported        : $TS (UTC)
source_vm       : $NAME
archive         : $(basename "$ARCHIVE")
archive_sha256  : $ARCHIVE_SHA   # over the stored artifact - what the signature covers
plaintext_sha256: $(cat "$OUT.tar.gz.sha256")   # over the pre-encryption .tar.gz
signature       : $( [ -n "$SIG" ] && basename "$SIG" || echo "(none - UNSIGNED)" )
encrypted       : $( [ "$ARCHIVE" != "$OUT.tar.gz" ] && echo yes || echo "no (PLAINTEXT)" )
complete        : $( [ "$COLLECT_OK" = 1 ] && echo yes || echo "NO - some transfers failed" )
sliver_state    : $( [ -n "$(ls -A "$STAGE/sliver-server-state" 2>/dev/null)" ] && echo "captured" || echo "none" )
files           : $(wc -l < "$OUT.manifest.sha256")
META

echo "[+] evidence archive : $ARCHIVE"
echo "    archive sha256   : $OUT.tar.gz.sha256"
echo "    per-file manifest: $OUT.manifest.sha256"
echo "    metadata         : $OUT.meta.txt"
[ -n "$SIG" ] && echo "    signature        : $SIG"
if [ "$COLLECT_OK" = 1 ]; then
  echo "    -> collection OK; safe to close: close-engagement.sh $ID"
else
  echo "    -> WARNING: one or more transfers FAILED above - this archive may be INCOMPLETE."
  echo "       Do NOT close the engagement until you've verified its contents against the clone."
  exit 2
fi
