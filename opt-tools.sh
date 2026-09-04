#!/usr/bin/env bash
set -uo pipefail
L=/tmp/opttools.log; : > "$L"
exec > >(tee -a "$L") 2>&1
mkdir -p /opt/tools/bin /opt/peass /opt/pspy
# -fsSL (not -sL): -f makes curl FAIL on an HTTP error instead of writing the error
# body to the file and then chmod'ing it +x as if it were the tool.
echo "== kerbrute =="; curl -fsSL -o /opt/tools/bin/kerbrute https://github.com/ropnop/kerbrute/releases/latest/download/kerbrute_linux_amd64 && chmod +x /opt/tools/bin/kerbrute || echo "WARN: kerbrute fetch failed"
echo "== dalfox =="; dtmp=$(mktemp -d)
# the release asset embeds the version (dalfox-<ver>-linux-x86_64.tar.gz) and unpacks
# into a versioned subdir, so resolve the URL from the API and find the binary
DURL=$(curl -fsSL https://api.github.com/repos/hahwul/dalfox/releases/latest | grep -oE 'https://[^"]*-linux-x86_64\.tar\.gz' | head -1 || true)
if [ -n "$DURL" ] && curl -fsSL -o "$dtmp/dalfox.tgz" "$DURL" && tar -xzf "$dtmp/dalfox.tgz" -C "$dtmp"; then
  df=$(find "$dtmp" -type f -name dalfox | head -1 || true)
  { [ -n "$df" ] && cp "$df" /opt/tools/bin/dalfox && chmod +x /opt/tools/bin/dalfox; } || echo "WARN: dalfox install failed"
else echo "WARN: dalfox fetch failed"; fi
rm -rf "$dtmp"
echo "== PEASS =="; curl -fsSL -o /opt/peass/linpeas.sh https://github.com/peass-ng/PEASS-ng/releases/latest/download/linpeas.sh || echo "WARN: linpeas fetch failed"
curl -fsSL -o /opt/peass/winPEASx64.exe https://github.com/peass-ng/PEASS-ng/releases/latest/download/winPEASx64.exe || echo "WARN: winPEASx64 fetch failed"
curl -fsSL -o /opt/peass/winPEASany.exe https://github.com/peass-ng/PEASS-ng/releases/latest/download/winPEASany.exe || echo "WARN: winPEASany fetch failed"
chmod +x /opt/peass/linpeas.sh 2>/dev/null || true
echo "== pspy =="; curl -fsSL -o /opt/pspy/pspy64 https://github.com/DominicBreuker/pspy/releases/latest/download/pspy64 && chmod +x /opt/pspy/pspy64 || echo "WARN: pspy fetch failed"
echo "== PayloadsAllTheThings =="; [ -d /opt/PayloadsAllTheThings ] || git clone --depth 1 https://github.com/swisskyrepo/PayloadsAllTheThings /opt/PayloadsAllTheThings
echo "== nuclei templates =="; nuclei -update-templates 2>&1 | tail -2
# PATH for the extra bin dir
echo 'export PATH=$PATH:/opt/tools/bin' > /etc/profile.d/golden-tools.sh
echo "== sizes =="; du -sh /opt/tools /opt/peass /opt/pspy /opt/PayloadsAllTheThings 2>/dev/null
echo "OPTTOOLS_DONE"
