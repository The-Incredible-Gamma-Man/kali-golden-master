#!/usr/bin/env bash
set -uo pipefail
L=/tmp/opttools.log; : > "$L"
exec > >(tee -a "$L") 2>&1
mkdir -p /opt/tools/bin /opt/peass /opt/pspy
echo "== kerbrute =="; curl -sL -o /opt/tools/bin/kerbrute https://github.com/ropnop/kerbrute/releases/latest/download/kerbrute_linux_amd64 && chmod +x /opt/tools/bin/kerbrute
echo "== dalfox =="; curl -sL https://github.com/hahwul/dalfox/releases/latest/download/dalfox_Linux_x86_64.tar.gz -o /tmp/dalfox.tgz && tar -xzf /tmp/dalfox.tgz -C /opt/tools/bin dalfox 2>/dev/null && chmod +x /opt/tools/bin/dalfox
echo "== PEASS =="; curl -sL -o /opt/peass/linpeas.sh https://github.com/peass-ng/PEASS-ng/releases/latest/download/linpeas.sh
curl -sL -o /opt/peass/winPEASx64.exe https://github.com/peass-ng/PEASS-ng/releases/latest/download/winPEASx64.exe
curl -sL -o /opt/peass/winPEASany.exe https://github.com/peass-ng/PEASS-ng/releases/latest/download/winPEASany.exe
chmod +x /opt/peass/linpeas.sh
echo "== pspy =="; curl -sL -o /opt/pspy/pspy64 https://github.com/DominicBreuker/pspy/releases/latest/download/pspy64 && chmod +x /opt/pspy/pspy64
echo "== PayloadsAllTheThings =="; [ -d /opt/PayloadsAllTheThings ] || git clone --depth 1 https://github.com/swisskyrepo/PayloadsAllTheThings /opt/PayloadsAllTheThings
echo "== nuclei templates =="; nuclei -update-templates 2>&1 | tail -2
# PATH for the extra bin dir
echo 'export PATH=$PATH:/opt/tools/bin' > /etc/profile.d/golden-tools.sh
echo "== sizes =="; du -sh /opt/tools /opt/peass /opt/pspy /opt/PayloadsAllTheThings 2>/dev/null
echo "OPTTOOLS_DONE"
