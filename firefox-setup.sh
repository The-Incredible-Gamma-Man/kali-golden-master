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
# download to a .part, verify it's a real XPI (a zip) before moving into place, and
# treat any failure as FATAL - a golden master must not ship a policy that references
# add-ons that were never fetched (or an HTML error body cached as an .xpi).
FAIL=0
for id in "${!XPI[@]}"; do
  f="$ADDONS/$id.xpi"
  [ -s "$f" ] && continue
  tmp="$f.part"
  if curl -fsSL -o "$tmp" "${XPI[$id]}" && unzip -tqq "$tmp" >/dev/null 2>&1; then
    mv -f "$tmp" "$f"
  else
    rm -f "$tmp"; echo "  ERROR: could not fetch/validate add-on $id"; FAIL=1
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
