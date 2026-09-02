#!/usr/bin/env bash
# harden.sh - apply the OPSEC/security baseline to the golden master.
# Runs INSIDE the VM as root, LAST in the build (it removes the build-time
# passwordless sudo). Network-disrupting changes are written as config and take
# effect on next boot, so running this over SSH won't cut your own connection.
#
#   GATEWAY_DNS   the libvirt gateway to use for DNS (default 192.168.122.1)
set -uo pipefail
export DEBIAN_FRONTEND=noninteractive
GW="${GATEWAY_DNS:-192.168.122.1}"

# Optional: a new 'kali' password supplied on stdin (first line) by the build wrapper.
# If none is given (interactive tty or empty), the default is kept.
NEWPW=""; if [ ! -t 0 ]; then IFS= read -r NEWPW || true; fi

echo "[*] UFW: default deny in / allow out / SSH / drop inbound ping"
apt-get install -y -q ufw </dev/null >/dev/null 2>&1 || true
ufw --force reset >/dev/null 2>&1 || true
ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null
ufw allow 22/tcp >/dev/null
sed -i 's/^-A ufw-before-input -p icmp --icmp-type echo-request -j ACCEPT/-A ufw-before-input -p icmp --icmp-type echo-request -j DROP/' /etc/ufw/before.rules 2>/dev/null || true
sed -i 's/^-A ufw6-before-input -p ipv6-icmp --icmp-type echo-request -j ACCEPT/-A ufw6-before-input -p ipv6-icmp --icmp-type echo-request -j DROP/' /etc/ufw/before6.rules 2>/dev/null || true
ufw --force enable >/dev/null; systemctl enable ufw >/dev/null 2>&1 || true

echo "[*] quiet services (no mDNS/LLMNR/Bluetooth beaconing on a client LAN)"
for s in bluetooth avahi-daemon avahi-daemon.socket cups cups-browsed cups.socket ModemManager saned; do
  systemctl disable --now "$s" 2>/dev/null || true
done
systemctl --global mask pipewire.service pipewire.socket pipewire-pulse.service pipewire-pulse.socket wireplumber.service 2>/dev/null || true
mkdir -p /etc/systemd/resolved.conf.d
printf '[Resolve]\nLLMNR=no\nMulticastDNS=no\n' > /etc/systemd/resolved.conf.d/99-no-llmnr.conf

echo "[*] gateway-only DNS (applied on next boot)"
printf '[main]\ndns=none\n' > /etc/NetworkManager/conf.d/00-dns-none.conf
rm -f /etc/resolv.conf
printf '# gateway-only DNS -> host -> your resolver\nnameserver %s\noptions edns0\n' "$GW" > /etc/resolv.conf

echo "[*] key-only SSH, no root login (applied on next boot)"
printf 'PasswordAuthentication no\nPermitRootLogin no\nKbdInteractiveAuthentication no\n' > /etc/ssh/sshd_config.d/99-hardening.conf

echo "[*] lock the root account"
passwd -l root >/dev/null 2>&1 || true

if [ -n "$NEWPW" ]; then
  echo "kali:$NEWPW" | chpasswd && echo "[*] 'kali' password set"
else
  echo "[*] 'kali' password left at default - set it after boot with: passwd"
fi

echo "[*] remove the build-time passwordless sudo (default behaviour restored)"
rm -f /etc/sudoers.d/99-build

cat <<'EOF'
[+] Hardening applied: UFW up, root locked, key-only SSH, gateway-only DNS, mDNS/LLMNR/BT off.
    SSH is key-only, so remote access does NOT depend on a password (it is only for console/sudo).
    DNS / SSH / service settings take full effect on the next boot (i.e. on every clone).
EOF
