# Operator runbook

How to build, run and maintain the golden master and its per-engagement clones.

## Layout

- **Master image:** `/var/lib/libvirt/images/golden/` (domain `kali-golden`)
- **Clones:** `/var/lib/libvirt/images/engagements/` (domain `eng-<id>`)
- **Build assets:** the scripts in this repo, plus a dedicated SSH keypair used by the host to
  reach the guests (never commit the private key).

## The master is a build artifact, not a workspace

`kali-golden` stays clean: no client IPs, credentials, names, or shell history. It is only ever
cloned. Everything client-specific lives in a clone and is destroyed at close.

## Build

1. Import the pinned Kali base QEMU image (see `sha.txt`) as a libvirt VM on a NAT network.
2. Inject an SSH key and provision:
   ```bash
   sudo bash provision-golden.sh
   ```
3. Strip build breadcrumbs and seal:
   ```bash
   sudo bash clean-master.sh
   ```
4. Tag the image and bump `CHANGELOG.md` (e.g. `kali-baseline-v1.0-2026-08`).

## Start an engagement

```bash
virsh shutdown kali-golden          # master must be off to clone
./new-engagement.sh acme-corp
# -> clones, generalizes (fresh machine-id / SSH host keys / Metasploit DB,
#    wiped neo4j, empty workspace), boots, prints the clone's address.
```

Connect to the clone with the build key over the host's NAT network. Work only inside
`~/engagements/<id>/`.

## Close an engagement

```bash
# export the report first, then:
./close-engagement.sh acme-corp     # destroys VM + disk + snapshots
```

On an encrypted host, deletion leaves nothing recoverable at rest — treat "destroy the clone"
as the deliverable-close checklist item, not an afterthought.

## Update the master

```bash
virsh start kali-golden
./update-golden.sh                  # apt + pipx + templates + NSE db + git repos + binaries
virsh shutdown kali-golden
sudo bash clean-master.sh
# bump CHANGELOG.md + retag
```

## Notes

- Serving droppables from `/opt/deploy` to a target needs a firewall exception, since the
  baseline is default-deny-inbound: `sudo ufw allow 80/tcp` (and remove it afterwards).
- AI-assisted / autonomous tooling and any tool that transmits engagement data off-box should be
  added to a clone per engagement — after confirming the scope permits it — never baked into the
  master.
