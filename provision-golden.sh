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
PGX install --python /usr/bin/python3.13 "git+https://github.com/login-securite/DonPAPI.git" || echo "PIPX_FAIL donpapi">>"$FAILED"

sec "NSE: vulners + vulscan"
[ -d /usr/share/nmap/scripts/nmap-vulners ] || git clone --depth 1 https://github.com/vulnersCom/nmap-vulners /usr/share/nmap/scripts/nmap-vulners || echo "GIT_FAIL vulners">>"$FAILED"
[ -d /usr/share/nmap/scripts/vulscan ]      || git clone --depth 1 https://github.com/scipag/vulscan       /usr/share/nmap/scripts/vulscan      || echo "GIT_FAIL vulscan">>"$FAILED"
nmap --script-updatedb || echo "NSE updatedb failed">>"$FAILED"

sec "EXPLOITDB SYNC + ROCKYOU"
searchsploit -u || echo "searchsploit -u failed">>"$FAILED"
[ -f /usr/share/wordlists/rockyou.txt.gz ] && gzip -df /usr/share/wordlists/rockyou.txt.gz || true

sec "OFFLINE /opt TOOLING"
mkdir -p /opt/tools/bin /opt/peass /opt/pspy
curl -fsSL -o /opt/tools/bin/kerbrute https://github.com/ropnop/kerbrute/releases/latest/download/kerbrute_linux_amd64 && chmod +x /opt/tools/bin/kerbrute
curl -fsSL -o /opt/peass/linpeas.sh https://github.com/peass-ng/PEASS-ng/releases/latest/download/linpeas.sh && chmod +x /opt/peass/linpeas.sh
curl -fsSL -o /opt/peass/winPEASx64.exe https://github.com/peass-ng/PEASS-ng/releases/latest/download/winPEASx64.exe
curl -fsSL -o /opt/peass/winPEASany.exe https://github.com/peass-ng/PEASS-ng/releases/latest/download/winPEASany.exe
curl -fsSL -o /opt/pspy/pspy64 https://github.com/DominicBreuker/pspy/releases/latest/download/pspy64 && chmod +x /opt/pspy/pspy64
# dalfox: fetch newest linux-x86_64 tarball by asset name
DURL=$(curl -fsSL https://api.github.com/repos/hahwul/dalfox/releases/latest | grep -oE 'https://[^"]*linux-x86_64\.tar\.gz' | head -1)
[ -n "$DURL" ] && wget -q --tries=4 -O /tmp/dalfox.tgz "$DURL" && tar -xzf /tmp/dalfox.tgz -C /tmp && cp "$(find /tmp -type f -name dalfox|head -1)" /opt/tools/bin/dalfox && chmod +x /opt/tools/bin/dalfox
[ -d /opt/PayloadsAllTheThings ] || git clone --depth 1 https://github.com/swisskyrepo/PayloadsAllTheThings /opt/PayloadsAllTheThings
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
