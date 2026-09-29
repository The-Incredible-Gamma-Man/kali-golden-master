#!/usr/bin/env bash
set +e
rm -f /root/.bash_history /root/.zsh_history /home/kali/.bash_history /home/kali/.zsh_history
# Seal Sliver: drop any server state (CA/loot/DB) left by a build-time test run and
# per-operator client configs, so the master ships no C2 trust root or creds. The
# offline armory cache (client extensions/aliases) is deliberately kept.
rm -rf /root/.sliver /home/kali/.sliver /root/.sliver-client/configs /home/kali/.sliver-client/configs
find /var/log -maxdepth 1 -name 'golden-provision*' -delete
find /tmp -maxdepth 1 \( -name '*.log' -o -name '*.out' -o -name '*.xpi' -o -name 'policies.json' -o -name 'provision-golden.sh' -o -name 'firefox-setup.sh' \) -delete
find /tmp -maxdepth 1 -name 'PROXY-SETUP.txt' -delete; find /tmp -maxdepth 1 -name 'foxyproxy-import.json' -delete
journalctl --rotate >/dev/null 2>&1; journalctl --vacuum-time=1s >/dev/null 2>&1
find /var/log -type f -name '*.log' -exec truncate -s0 {} \; 2>/dev/null
find /var/log -type f -name '*.1' -delete 2>/dev/null
echo "master cleaned"
