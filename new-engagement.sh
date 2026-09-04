#!/usr/bin/env bash
# Spin up an isolated engagement clone from the golden master.
# Contamination controls: fresh machine-id, fresh SSH host keys, wiped logs/
# history, fresh Metasploit DB, wiped BloodHound/neo4j graph, empty workspace.
# Inherits from master: UFW (deny-in/allow-out/SSH/no-ping), key-only SSH,
# root locked, gateway-only DNS, slimmed services, full toolset.
set -euo pipefail
ID="${1:?usage: new-engagement <client-id>}"
MASTER=kali-golden; POOL=/var/lib/libvirt/images/engagements
NAME="eng-${ID}"; DISK="${POOL}/${NAME}.qcow2"
KEY="${GOLDEN_KEY:-$HOME/.ssh/kali-golden_build_key}"
OPTS="-i $KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

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
  --firstboot-command 'printf "nameserver 192.168.122.1\noptions edns0\n" > /etc/resolv.conf' \
  --firstboot-command 'msfdb reinit || true' \
  --firstboot-command 'systemctl stop neo4j 2>/dev/null; rm -rf /var/lib/neo4j/data/databases/* /var/lib/neo4j/data/transactions/* 2>/dev/null; true' \
  --firstboot-command "runuser -l kali -c 'mkdir -p ~/engagements/${ID}/{recon,loot,creds,screenshots,report}'" \
  --firstboot-command 'nmap --script-updatedb || true'

echo "[*] Starting $NAME"
sudo virsh start "$NAME"
IP=""
for i in $(seq 1 30); do
  IP=$(sudo virsh -q domifaddr "$NAME" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1)
  [ -n "$IP" ] && break; sleep 4
done
# register clone in /etc/hosts as eng-<id>
sudo sed -i "/[[:space:]]${NAME}\$/d" /etc/hosts
[ -n "$IP" ] && echo "$IP   ${NAME}" | sudo tee -a /etc/hosts >/dev/null
echo "[+] $NAME running at ${IP:-<pending>}  (hosts: ${NAME})"
echo "    ssh -i $KEY kali@${NAME}      workspace: ~/engagements/${ID}"
