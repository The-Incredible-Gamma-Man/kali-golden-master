#!/usr/bin/env bash
# firefox-setup.sh - install the Firefox enterprise policy (pentest bookmarks +
# Wappalyzer + FoxyProxy) into the location Kali's Firefox actually reads. Runs
# inside the VM as root, during the build.
#
# Gotcha this fixes: Kali ships its OWN policies.json in the distribution dir, which
# takes precedence over /etc/firefox-esr/policies. So we deploy to BOTH (distribution
# is the one that wins on Kali). Reads policies.json from this script's directory.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ADDONS=/opt/firefox-addons
DIST=/usr/lib/firefox-esr/distribution
ETC=/etc/firefox-esr/policies

echo "[*] fetching add-on XPIs (Wappalyzer, FoxyProxy)"
mkdir -p "$ADDONS"
declare -A XPI=(
  ["wappalyzer@crunchlabz.com"]="https://addons.mozilla.org/firefox/downloads/latest/wappalyzer/latest.xpi"
  ["foxyproxy@eric.h.jung"]="https://addons.mozilla.org/firefox/downloads/latest/foxyproxy-standard/latest.xpi"
)
# Pinned SHA-256 per add-on. AMO's 'latest' URL has no version lock, so we pin by
# hash: if Mozilla ships a new build the hash won't match and the build fails loudly
# (prompting a deliberate re-pin) instead of silently baking in a changed extension.
declare -A XPI_SHA=(
  ["wappalyzer@crunchlabz.com"]="3a369e5580a1b4864001c021e0f5b524a7f08968b438fb7d5d7cbe887e8cee89"
  ["foxyproxy@eric.h.jung"]="3ab91ca2a6cac925bc7097c46948573fefe4e3fddcbc27dda755401419c4e5d7"
)
# download to a .part, verify it's a real XPI (a zip) before moving into place, and
# treat any failure as FATAL - a golden master must not ship a policy that references
# add-ons that were never fetched (or an HTML error body cached as an .xpi).
FAIL=0
for id in "${!XPI[@]}"; do
  f="$ADDONS/$id.xpi"
  [ -s "$f" ] && continue
  tmp="$f.part"
  if curl -fsSL -o "$tmp" "${XPI[$id]}" \
     && unzip -tqq "$tmp" >/dev/null 2>&1 \
     && echo "${XPI_SHA[$id]}  $tmp" | sha256sum -c - >/dev/null 2>&1; then
    mv -f "$tmp" "$f"
  else
    rm -f "$tmp"; echo "  ERROR: fetch/validate/verify failed for add-on $id (download error or SHA-256 mismatch - re-pin if the add-on was updated)"; FAIL=1
  fi
done
[ "$FAIL" = 0 ] || { echo "[!] add-on fetch failed - refusing to ship a half-configured policy"; exit 1; }

echo "[*] deploying policy (Kali reads the distribution dir; also /etc for good measure)"
mkdir -p "$DIST" "$ETC"
install -m0644 "$HERE/policies.json" "$DIST/policies.json" || { echo "ERROR: failed to install policies.json to $DIST"; exit 1; }
install -m0644 "$HERE/policies.json" "$ETC/policies.json"  || { echo "ERROR: failed to install policies.json to $ETC"; exit 1; }

# FoxyProxy proxy list is imported by the operator (extension storage can't be pre-seeded)
if [ -d /home/kali/Desktop ]; then
  [ -f "$HERE/foxyproxy-import.json" ] && install -o kali -g kali -m0644 "$HERE/foxyproxy-import.json" /home/kali/Desktop/ 2>/dev/null || true
  [ -f "$HERE/PROXY-SETUP.txt" ]       && install -o kali -g kali -m0644 "$HERE/PROXY-SETUP.txt"       /home/kali/Desktop/ 2>/dev/null || true
fi

echo "[+] Firefox policy installed: bookmarks + Wappalyzer + FoxyProxy apply on next launch."
echo "    Import the FoxyProxy proxies once: FoxyProxy > Options > Import > foxyproxy-import.json"
