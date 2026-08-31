# kali-golden-master

![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)
![Platform](https://img.shields.io/badge/platform-Kali%20Linux-557C94?logo=kalilinux&logoColor=white)
![Shell](https://img.shields.io/badge/shell-bash-4EAA25?logo=gnubash&logoColor=white)
![Hypervisor](https://img.shields.io/badge/hypervisor-libvirt%2FKVM-CC0000?logo=redhat&logoColor=white)
![Made with Bash](https://img.shields.io/badge/made%20with-bash-1f425f.svg)
![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)

A reproducible, versioned **Kali Linux golden image** for authorized penetration testing —
built as a libvirt/KVM virtual machine and designed to be *cloned per engagement and
destroyed at close*, so nothing ever bleeds between clients.

The image itself is a build artifact. The source of truth is this repository: a set of
scripts and config that rebuild an identical master from the upstream Kali base image plus
the pinned checksum in [`sha.txt`](sha.txt). Ship the recipe, not a 40 GB blob.

## Why

Standing up a fresh, consistent toolbox for every engagement is tedious and error-prone,
and re-using one VM across clients is a cross-contamination finding waiting to happen. This
repo makes the baseline **reproducible** (rebuild from code), **auditable** (tagged versions
answer "what tools were present during testing"), and **disposable** (each engagement gets a
throwaway clone with a fresh identity).

## What's inside

- **Recon / web:** nmap (+ vulners & vulscan NSE), masscan, ffuf, feroxbuster, gobuster, nuclei,
  httpx, subfinder, naabu, dnsx, katana, gowitness, eyewitness, amass, nikto, whatweb, wpscan,
  sqlmap, dalfox.
- **AD / lateral:** the full Impacket suite (psexec/smbexec/wmiexec/atexec/dcomexec, secretsdump,
  ntlmrelayx…), netexec, evil-winrm, kerbrute, certipy, coercer, mitm6, responder, bloodhound.
- **Creds:** hashcat, john, pypykatz, samdump2, mimikatz + PsTools staged for drop.
- **Post-ex / pivot:** chisel, ligolo-ng, sshuttle, proxychains, linpeas/winpeas/pspy.
- **Wordlists & exploits:** SecLists, rockyou, searchsploit/Exploit-DB, PayloadsAllTheThings.
- **Workflow:** AutoRecon, a hardened Firefox profile (Wappalyzer + FoxyProxy, curated bookmarks),
  CherryTree, Flameshot, and an offline HTML cheatsheet bundled into the image.

Full inventory in [`CHANGELOG.md`](CHANGELOG.md).

## Quick start

Prerequisites: a Linux host with libvirt/KVM and `libguestfs-tools`.

```bash
# 1. Fetch the pinned Kali base QEMU image (see sha.txt), import as a VM.
# 2. Provision the toolset inside it:
sudo bash provision-golden.sh
# 3. Snapshot/seal the master. Then, per engagement:
./new-engagement.sh acme-corp     # clone → fresh identity → boot
#    ...work happens only in the clone...
./close-engagement.sh acme-corp   # destroy VM + storage at close
```

See [`RUNBOOK.md`](RUNBOOK.md) for the full lifecycle and hardening notes.

## Repository layout

| File | Purpose |
|------|---------|
| `provision-golden.sh` | Installs the whole toolset into a fresh Kali base VM |
| `new-engagement.sh` / `close-engagement.sh` | Clone-per-engagement lifecycle |
| `update-golden.sh` | Interactive full refresh (apt/pipx/templates/binaries) + changelog |
| `clean-master.sh` | Strips build breadcrumbs before sealing |
| `opt-tools.sh` | Fetches standalone binaries into `/opt` |
| `policies.json` | Firefox enterprise policy (extensions + bookmarks) |
| `pentest-cheatsheet.html` | Self-contained offline reference bundled into the image |
| `RUNBOOK.md` / `CHANGELOG.md` | Operations guide + version history |

## Hardening highlights

Root locked, key-only SSH, UFW default-deny-inbound (no ping), gateway-only DNS, and mDNS/LLMNR/
Bluetooth disabled so a clone never beacons on a client LAN. Each clone is generalized on first
boot (fresh machine-id, SSH host keys, Metasploit DB, empty workspace).

## Contributing

Issues and PRs welcome — new tools, additional NSE scripts, cheatsheet entries, or hardening
improvements. Keep the master lean: engagement-specific or heavyweight tooling belongs on a clone,
not the baseline.

## License

MIT — see [`LICENSE`](LICENSE).

> For authorized security testing only. You are responsible for having permission to test any
> system you point these tools at.
