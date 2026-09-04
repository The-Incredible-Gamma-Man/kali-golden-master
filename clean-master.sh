#!/usr/bin/env bash
set +e
rm -f /root/.bash_history /root/.zsh_history /home/kali/.bash_history /home/kali/.zsh_history
find /var/log -maxdepth 1 -name 'golden-provision*' -delete
find /tmp -maxdepth 1 \( -name '*.log' -o -name '*.out' -o -name '*.xpi' -o -name 'policies.json' -o -name 'provision-golden.sh' -o -name 'firefox-setup.sh' \) -delete
find /tmp -maxdepth 1 -name 'PROXY-SETUP.txt' -delete; find /tmp -maxdepth 1 -name 'foxyproxy-import.json' -delete
journalctl --rotate >/dev/null 2>&1; journalctl --vacuum-time=1s >/dev/null 2>&1
find /var/log -type f -name '*.log' -exec truncate -s0 {} \; 2>/dev/null
find /var/log -type f -name '*.1' -delete 2>/dev/null
echo "master cleaned"
