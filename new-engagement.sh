#!/usr/bin/env bash
# Spin up an isolated engagement clone from the golden master.
# Contamination controls: fresh machine-id, fresh SSH host keys, wiped logs/
# history, fresh Metasploit DB, wiped BloodHound/neo4j graph, empty workspace.
# Inherits from master: UFW (deny-in/allow-out/SSH/no-ping), key-only SSH,
# root locked, gateway-only DNS, slimmed services, full toolset.
set -euo pipefail
ID="${1:?usage: new-engagement <client-id>}"
# The id reaches a guest firstboot *shell* command, a root sed over /etc/hosts,
# and filesystem paths - so constrain it to safe characters (no spaces, quotes,
# ';', or regex/shell metacharacters).
[[ "$ID" =~ ^[a-z0-9][a-z0-9-]{0,30}$ ]] \
  || { echo "ERROR: id must be [a-z0-9][a-z0-9-]{0,30} (lowercase letters, digits, hyphens)"; exit 1; }
MASTER=kali-golden; POOL=/var/lib/libvirt/images/engagements
NAME="eng-${ID}"; DISK="${POOL}/${NAME}.qcow2"
KEY="${GOLDEN_KEY:-$HOME/.ssh/kali-golden_build_key}"
GWDNS="${GATEWAY_DNS:-192.168.122.1}"   # DNS gateway pushed into the clone (override for bridged/on-net modes)

[ -e "$DISK" ] && { echo "ERROR: clone $NAME already exists"; exit 1; }
sudo virsh domstate "$MASTER" 2>/dev/null | grep -q 'shut off' \
  || { echo "ERROR: shut off the master first:  sudo virsh shutdown $MASTER"; exit 1; }

echo "[*] Cloning $MASTER -> $NAME"
# create the engagements pool if it doesn't exist yet (mirrors bootstrap.sh's
# mkdir -p of the master pool) so the very first clone doesn't fail on a fresh host
sudo mkdir -p "$POOL"
sudo virt-clone --original "$MASTER" --name "$NAME" --file "$DISK"

echo "[*] Generalising (fresh identity; keep authorized_keys; reassert gateway DNS)"
sudo virt-sysprep -d "$NAME" --hostname "$NAME" --operations defaults,-ssh-userdir \
  --firstboot-command "printf 'nameserver ${GWDNS}\noptions edns0\n' > /etc/resolv.conf" \
  --firstboot-command 'msfdb reinit || true' \
  --firstboot-command 'systemctl stop neo4j 2>/dev/null; rm -rf /var/lib/neo4j/data/databases/* /var/lib/neo4j/data/transactions/* 2>/dev/null; true' \
  --firstboot-command "runuser -l kali -c 'mkdir -p ~/engagements/${ID}/{recon,loot,creds,screenshots,report}'" \
  --firstboot-command 'nmap --script-updatedb || true'

echo "[*] Starting $NAME"
# the default NAT network can be down after a host/WSL restart (libvirt's
# autostart flag isn't always honoured), which makes domain start fail with
# "network 'default' is not active" - ensure it's up first.
sudo virsh net-info default 2>/dev/null | grep -qiE '^Active: +yes' \
  || sudo virsh net-start default 2>/dev/null || true
sudo virsh start "$NAME"
IP=""
for _ in $(seq 1 30); do
  # '|| true' keeps a slow lease (or a SIGPIPE from 'head' under pipefail) from
  # tripping 'set -e' and killing the wait before the clone has finished booting.
  IP=$(sudo virsh -q domifaddr "$NAME" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1 || true)
  [ -n "$IP" ] && break
  sleep 4
done
# register clone in /etc/hosts as eng-<id> (if/then so an empty IP can't abort us)
sudo sed -i "/[[:space:]]${NAME}\$/d" /etc/hosts
if [ -n "$IP" ]; then
  echo "$IP   ${NAME}" | sudo tee -a /etc/hosts >/dev/null
fi
echo "[+] $NAME running at ${IP:-<pending, slow boot - re-check with: virsh -c qemu:///system domifaddr $NAME>}  (hosts: ${NAME})"
echo "    ssh -i $KEY kali@${NAME}      workspace: ~/engagements/${ID}"
