#!/usr/bin/env bash
###############################################################################
# Kali golden-master provisioning script  (v2, as-built 2026-08-31)
# Runs INSIDE the Kali VM as root. Fault-tolerant: a failing item is logged to
# golden-provision.failed and skipped, never aborts. Reproducible rebuild source.
###############################################################################
set -uo pipefail
export DEBIAN_FRONTEND=noninteractive
LOG=/var/log/golden-provision.log; FAILED=/var/log/golden-provision.failed
: > "$FAILED"; exec > >(tee -a "$LOG") 2>&1
echo "===== GOLDEN PROVISION v2 START $(date -u +%FT%TZ) ====="
sec(){ echo; echo "########## $* ##########"; }
try_apt(){ for p in "$@"; do apt-get install -y -q "$p" </dev/null || echo "APT_FAIL $p" >> "$FAILED"; done; }
PGX(){ PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin pipx "$@"; }

# --- PINNED third-party artifacts (reproducibility + supply chain) ------------
# Exact versions + SHA-256, verified before use, so a moved/tampered/updated
# upstream release fails the build LOUDLY instead of baking an unverified binary
# into a golden image that runs on client networks. Update these deliberately;
# update-golden.sh is the separate "pull latest" path. (Regenerate with the repo's
# gather-pins helper.) Git repos are pinned to exact commits further below.
declare -A P_URL P_SHA
P_URL[kerbrute]="https://github.com/ropnop/kerbrute/releases/download/v1.0.3/kerbrute_linux_amd64"
P_SHA[kerbrute]="710a9d2653c8bd3689e451778dab9daec0de4c4c75f900788ccf23ef254b122a"
P_URL[linpeas.sh]="https://github.com/peass-ng/PEASS-ng/releases/download/20260901-a029e205/linpeas.sh"
P_SHA[linpeas.sh]="8f5f81b0f1b6293f9da63817b55872263d60bf4a0dff65ff2911badf2d53c88f"
P_URL[winPEASx64.exe]="https://github.com/peass-ng/PEASS-ng/releases/download/20260901-a029e205/winPEASx64.exe"
P_SHA[winPEASx64.exe]="369352c50dca44e661e620d3fe1775671d09ce3e6ad761aa05f018e5a4c7bbc8"
P_URL[winPEASany.exe]="https://github.com/peass-ng/PEASS-ng/releases/download/20260901-a029e205/winPEASany.exe"
P_SHA[winPEASany.exe]="ba09852ba2051d6b6041a87fe8f29df5de5aaffe8683c854f2966e3a7221c210"
P_URL[pspy64]="https://github.com/DominicBreuker/pspy/releases/download/v1.2.1/pspy64"
P_SHA[pspy64]="c93f29a5cc1347bdb90e14a12424e6469c8cfea9a20b800bc249755f0043a3bb"
# dalfox ships a tarball; the single binary is extracted after verification.
P_URL[dalfox.tgz]="https://github.com/hahwul/dalfox/releases/download/v3.2.2/dalfox-v3.2.2-linux-x86_64.tar.gz"
P_SHA[dalfox.tgz]="7f9621090ab2c5ef48dbab3e2d7a9de81a54390efee2aaa0b431130df629715e"

# fetch_pinned <name> <dest> [x] : download to temp, verify SHA-256, then install.
fetch_pinned(){
  local n="$1" d="$2" t; t=$(mktemp)
  if ! curl -fsSL -o "$t" "${P_URL[$n]}"; then echo "DL_FAIL $n">>"$FAILED"; rm -f "$t"; return 0; fi
  if ! echo "${P_SHA[$n]}  $t" | sha256sum -c - >/dev/null 2>&1; then
    echo "HASH_FAIL $n (want ${P_SHA[$n]}, got $(sha256sum "$t"|awk '{print $1}'))">>"$FAILED"; rm -f "$t"; return 0
  fi
  mv "$t" "$d"; [ "${3:-}" = x ] && chmod +x "$d"
}
# pin_git <url> <sha> <dir> : shallow-fetch and check out an exact commit.
pin_git(){
  [ -d "$3/.git" ] && return 0
  mkdir -p "$3"; git -C "$3" init -q; git -C "$3" remote add origin "$1"
  if git -C "$3" fetch -q --depth 1 origin "$2" && git -C "$3" checkout -q FETCH_HEAD; then :; \
  else echo "GIT_FAIL $1@$2">>"$FAILED"; fi
}

sec "APT UPDATE + FULL UPGRADE"; apt-get update -q; apt-get full-upgrade -y -q </dev/null || echo "APT_FAIL upgrade">>"$FAILED"

sec "BUILD DEPS (for pipx source builds e.g. lxml on py3.14)"
try_apt build-essential python3-dev libxml2-dev libxslt1-dev libffi-dev zlib1g-dev pipx

sec "KALI METAPACKAGES"
try_apt kali-tools-web kali-tools-database kali-tools-passwords \
        kali-tools-vulnerability kali-tools-post-exploitation kali-tools-windows-resources

sec "CORE NAMED TOOLS"
try_apt nmap masscan gobuster ffuf feroxbuster nikto whatweb wpscan sqlmap hydra john \
        hashcat netexec impacket-scripts bloodhound neo4j responder enum4linux-ng \
        smbclient ldap-utils chisel proxychains4 gdb radare2 binwalk exploitdb \
        seclists wordlists cewl metasploit-framework git curl wget jq p7zip-full

sec "EXTRA RECON/EXPLOIT TOOLS"
try_apt nuclei httpx-toolkit subfinder naabu dnsx katana gowitness eyewitness amass \
        evil-winrm mitm6 wfuzz dirsearch sshuttle ligolo-ng nishang webshells laudanum \
        libimage-exiftool-perl

sec "NOTES / SCREENSHOTS / VPN"
try_apt cherrytree flameshot ksnip openvpn openvpn-systemd-resolved

sec "SECURITY BASELINE (ufw is enabled + configured later by harden.sh)"
try_apt ufw

sec "PIPX GLOBAL TOOLS (nxc supplied by apt netexec)"
for p in certipy-ad coercer pywerview man-spider bloodhound-ce autorecon; do PGX install "$p" || echo "PIPX_FAIL $p">>"$FAILED"; done
PGX install --python python3 "git+https://github.com/login-securite/DonPAPI.git" || echo "PIPX_FAIL donpapi">>"$FAILED"

sec "NSE: vulners + vulscan"
pin_git https://github.com/vulnersCom/nmap-vulners 7607b14327b41c74d5d869899ff9a4218a441a8d /usr/share/nmap/scripts/nmap-vulners
pin_git https://github.com/scipag/vulscan          bd642ed1bc9d96795a91cdf1acd8c93ceef2d07e /usr/share/nmap/scripts/vulscan
nmap --script-updatedb || echo "NSE updatedb failed">>"$FAILED"

sec "EXPLOITDB SYNC + ROCKYOU"
searchsploit -u || echo "searchsploit -u failed">>"$FAILED"
[ -f /usr/share/wordlists/rockyou.txt.gz ] && gzip -df /usr/share/wordlists/rockyou.txt.gz || true

sec "OFFLINE /opt TOOLING (pinned versions, SHA-256 verified)"
mkdir -p /opt/tools/bin /opt/peass /opt/pspy
fetch_pinned kerbrute       /opt/tools/bin/kerbrute   x
fetch_pinned linpeas.sh     /opt/peass/linpeas.sh     x
fetch_pinned winPEASx64.exe /opt/peass/winPEASx64.exe
fetch_pinned winPEASany.exe /opt/peass/winPEASany.exe
fetch_pinned pspy64         /opt/pspy/pspy64          x
# dalfox: verify the pinned tarball, then extract its single binary from a mktemp dir
dtmp=$(mktemp -d)
fetch_pinned dalfox.tgz "$dtmp/dalfox.tgz"
if [ -s "$dtmp/dalfox.tgz" ] && tar -xzf "$dtmp/dalfox.tgz" -C "$dtmp" 2>/dev/null; then
  df=$(find "$dtmp" -type f -name dalfox | head -1 || true)
  { [ -n "$df" ] && cp "$df" /opt/tools/bin/dalfox && chmod +x /opt/tools/bin/dalfox; } || echo "DL_FAIL dalfox (extract)">>"$FAILED"
fi
rm -rf "$dtmp"
pin_git https://github.com/swisskyrepo/PayloadsAllTheThings 3ac27901c711bdf3f5b65a7b1d1820a1f65bd09a /opt/PayloadsAllTheThings
echo 'export PATH=$PATH:/opt/tools/bin' > /etc/profile.d/golden-tools.sh
runuser -l kali -c 'nuclei -update-templates' || echo "nuclei templates(kali) failed">>"$FAILED"

sec "NESSUS (pre-staged, NOT installed/activated - per-engagement licensing)"
mkdir -p /opt/installers
# .deb is pre-staged out of band; install-nessus.sh runs it on a clone with your own license code.

sec "FIREFOX POLICY + ADDONS"  # policies.json + XPIs are placed out of band (see build assets)
mkdir -p /opt/firefox-addons /etc/firefox-esr/policies

sec "ENGAGEMENT WORKSPACE + TOOL DEFAULTS"
install -d -o kali -g kali /home/kali/engagements
cat > /usr/local/bin/newengagement <<'NE'
#!/usr/bin/env bash
id="${1:?usage: newengagement <client-id>}"; base="$HOME/engagements/$id"
mkdir -p "$base"/{recon,loot,creds,screenshots,report}; echo "created $base"
NE
chmod +x /usr/local/bin/newengagement
mkdir -p /opt/wordlists-extra /opt/nvd-feeds
systemctl disable neo4j 2>/dev/null || true

sec "MANIFEST"
{ echo "# golden-master manifest $(date -u +%FT%TZ)"; grep VERSION /etc/os-release;
  echo "## key tools"; for t in nmap nuclei netexec bloodhound-python impacket-getST sqlmap ffuf feroxbuster gowitness subfinder katana amass evil-winrm mitm6 kerbrute dalfox flameshot cherrytree openvpn msfconsole; do printf "%-18s %s\n" "$t" "$(command -v $t 2>/dev/null||echo MISSING)"; done
  echo "## pipx"; PIPX_HOME=/opt/pipx pipx list --short 2>/dev/null; } > /opt/golden-manifest.txt
echo "===== PROVISION v2 COMPLETE $(date -u +%FT%TZ) ====="; echo "FAILURES:"; cat "$FAILED" || echo none
