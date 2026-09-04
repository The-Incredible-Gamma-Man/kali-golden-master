#!/usr/bin/env bash
###############################################################################
# update-golden.sh
# Refresh the ENTIRE golden toolset (apt, pipx, nuclei templates, NSE db,
# exploitdb, git repos, standalone binaries) and rewrite the CHANGELOG with a
# full current-version manifest.  Run on the master before cloning, or on a
# clone at engagement start.
#   update-golden        interactive (asks before upgrading)
#   update-golden --yes  non-interactive
###############################################################################
set -uo pipefail

CHANGELOG="/opt/golden-build/CHANGELOG.md"
BIN="/opt/tools/bin"; PEASS="/opt/peass"; DEPLOY="/opt/deploy"
ASSUME_YES=0; [ "${1:-}" = "--yes" ] && ASSUME_YES=1

c(){    printf '\033[1;36m%s\033[0m\n' "$*"; }
ok(){   printf '  \033[32m\xe2\x9c\x93\033[0m %s\n' "$*"; }
warn(){ printf '  \033[33m!\033[0m %s\n' "$*"; }

command -v sudo >/dev/null || { echo "sudo required"; exit 1; }
c "[*] Caching sudo credentials (asked once)…"; sudo -v || exit 1
( while true; do sudo -n true; sleep 50; done ) 2>/dev/null & KEEP=$!
trap 'kill $KEEP 2>/dev/null' EXIT

# ---------- changelog writer ----------
write_changelog(){
  sudo mkdir -p "$(dirname "$CHANGELOG")"
  [ -f "$CHANGELOG" ] || echo "# Kali Golden Master — CHANGELOG" | sudo tee "$CHANGELOG" >/dev/null
  local D; D=$(date -u +%FT%TZ)
  {
    echo; echo "## auto-update $D"; echo '```'
    grep -m1 'VERSION=' /etc/os-release | sed 's/^/kali /'
    echo "-- apt (security tools) --"
    dpkg -l 2>/dev/null | awk '/^ii/{print $2"="$3}' | grep -Ei \
      '^(nmap|masscan|gobuster|ffuf|feroxbuster|nikto|whatweb|wpscan|sqlmap|hydra|john|hashcat|netexec|impacket-scripts|bloodhound|neo4j|responder|enum4linux-ng|smbclient|ldap-utils|chisel|proxychains4|radare2|binwalk|exploitdb|seclists|nuclei|httpx-toolkit|subfinder|naabu|dnsx|katana|gowitness|eyewitness|amass|evil-winrm|mitm6|dirsearch|ligolo-ng|cherrytree|flameshot|ksnip|openvpn|metasploit-framework|ufw)='
    echo "-- pipx --"; PIPX_HOME=/opt/pipx pipx list --short 2>/dev/null
    echo "-- standalone binaries --"
    for b in "$BIN/kerbrute" "$BIN/dalfox" "$DEPLOY/pspy64"; do
      [ -e "$b" ] && echo "$(basename "$b") ($(stat -c %y "$b" | cut -d. -f1))"; done
    grep -m1 -oE 'LinPEAS version [0-9.]+' "$PEASS/linpeas.sh" 2>/dev/null || echo "linpeas: present"
    echo "PayloadsAllTheThings: $(git -C /opt/PayloadsAllTheThings rev-parse --short HEAD 2>/dev/null || echo n/a)"
    echo "nuclei-templates: $(find "$HOME/.local/nuclei-templates" -name '*.yaml' 2>/dev/null | wc -l) templates"
    echo '```'
  } | sudo tee -a "$CHANGELOG" >/dev/null
}

# ---------- 1. metadata ----------
c "[1/2] Refreshing package metadata…"
sudo apt-get update -q
N=$(apt list --upgradable 2>/dev/null | grep -c '/')
echo "     apt upgradable: $N   |   nuclei/templates + git repos will also be checked"
echo
if [ "$ASSUME_YES" -ne 1 ]; then
  read -rp "Proceed with FULL upgrade (apt + pipx + tools + templates + git + binaries)? [y/N] " a
  case "$a" in y|Y|yes|YES) ;; *) echo "Aborted — metadata refreshed only, nothing upgraded."; exit 0;; esac
fi

# ---------- 2. upgrade ----------
c "[2/2] Upgrading…"
sudo DEBIAN_FRONTEND=noninteractive apt-get -y full-upgrade && ok "apt full-upgrade"
sudo apt-get -y autoremove >/dev/null 2>&1
sudo PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin pipx upgrade-all >/dev/null 2>&1 && ok "pipx upgrade-all"
nuclei -update-templates >/dev/null 2>&1 && ok "nuclei templates"
sudo nmap --script-updatedb >/dev/null 2>&1 && ok "nmap NSE db"
searchsploit -u >/dev/null 2>&1 && ok "exploitdb (searchsploit)"
for r in /opt/PayloadsAllTheThings /usr/share/nmap/scripts/nmap-vulners /usr/share/nmap/scripts/vulscan; do
  [ -d "$r/.git" ] && sudo git -C "$r" pull --ff-only >/dev/null 2>&1 && ok "git: $(basename "$r")"
done

sudo mkdir -p "$BIN" "$PEASS" "$DEPLOY"
# download to a temp then move on success+non-empty, so a failed/partial fetch
# never overwrites a previously-good binary with a 0-byte or truncated file
dl(){
  if sudo wget -q --tries=3 --timeout=30 -O "$1.tmp" "$2" && [ -s "$1.tmp" ]; then
    sudo mv "$1.tmp" "$1"; ok "bin: $(basename "$1")"
  else
    sudo rm -f "$1.tmp"; warn "bin FAILED (kept previous): $(basename "$1")"
  fi
}
dl "$BIN/kerbrute"        https://github.com/ropnop/kerbrute/releases/latest/download/kerbrute_linux_amd64
dl "$PEASS/linpeas.sh"    https://github.com/peass-ng/PEASS-ng/releases/latest/download/linpeas.sh
dl "$PEASS/winPEASx64.exe" https://github.com/peass-ng/PEASS-ng/releases/latest/download/winPEASx64.exe
dl "$PEASS/winPEASany.exe" https://github.com/peass-ng/PEASS-ng/releases/latest/download/winPEASany.exe
dl "$DEPLOY/pspy64"       https://github.com/DominicBreuker/pspy/releases/latest/download/pspy64
# match the real asset name (dalfox_Linux_x86_64.tar.gz) and extract in a private
# mktemp dir so a predictable /tmp path / stray 'dalfox' can't be picked up
DURL=$(curl -fsSL https://api.github.com/repos/hahwul/dalfox/releases/latest 2>/dev/null | grep -oiE 'https://[^"]*dalfox_[Ll]inux_x86_64\.tar\.gz' | head -1 || true)
if [ -n "$DURL" ]; then
  dtmp=$(mktemp -d)
  if wget -q --tries=3 -O "$dtmp/dalfox.tgz" "$DURL" && tar -xzf "$dtmp/dalfox.tgz" -C "$dtmp" 2>/dev/null; then
    df=$(find "$dtmp" -type f -name dalfox | head -1 || true)
    { [ -n "$df" ] && sudo cp "$df" "$BIN/dalfox" && ok "bin: dalfox"; } || warn "bin FAILED: dalfox"
  else warn "bin FAILED: dalfox"; fi
  rm -rf "$dtmp"
else warn "bin FAILED: dalfox (no asset URL)"; fi
sudo chmod +x "$BIN"/* "$PEASS/linpeas.sh" "$DEPLOY/pspy64" 2>/dev/null
# keep the deploy folder in sync
sudo cp -f "$PEASS/linpeas.sh" "$PEASS/winPEASx64.exe" "$PEASS/winPEASany.exe" "$DEPLOY/" 2>/dev/null

c "[*] Rewriting CHANGELOG manifest…"; write_changelog; ok "CHANGELOG: $CHANGELOG"
echo; c "Done. Review:  tail -n 40 $CHANGELOG"
