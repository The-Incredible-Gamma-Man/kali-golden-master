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
for id in "${!XPI[@]}"; do
  f="$ADDONS/$id.xpi"
  [ -s "$f" ] || curl -fsSL -o "$f" "${XPI[$id]}" || echo "  WARN: could not fetch $id"
done

echo "[*] deploying policy (Kali reads the distribution dir; also /etc for good measure)"
mkdir -p "$DIST" "$ETC"
install -m0644 "$HERE/policies.json" "$DIST/policies.json"
install -m0644 "$HERE/policies.json" "$ETC/policies.json"

# FoxyProxy proxy list is imported by the operator (extension storage can't be pre-seeded)
if [ -d /home/kali/Desktop ]; then
  [ -f "$HERE/foxyproxy-import.json" ] && install -o kali -g kali -m0644 "$HERE/foxyproxy-import.json" /home/kali/Desktop/ 2>/dev/null || true
  [ -f "$HERE/PROXY-SETUP.txt" ]       && install -o kali -g kali -m0644 "$HERE/PROXY-SETUP.txt"       /home/kali/Desktop/ 2>/dev/null || true
fi

echo "[+] Firefox policy installed: bookmarks + Wappalyzer + FoxyProxy apply on next launch."
echo "    Import the FoxyProxy proxies once: FoxyProxy > Options > Import > foxyproxy-import.json"
