# kali-golden-master

![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)
![Platform](https://img.shields.io/badge/platform-Kali%20Linux-557C94?logo=kalilinux&logoColor=white)
![Shell](https://img.shields.io/badge/shell-bash-4EAA25?logo=gnubash&logoColor=white)
![Hypervisor](https://img.shields.io/badge/hypervisor-libvirt%2FKVM-CC0000?logo=redhat&logoColor=white)
![OPSEC](https://img.shields.io/badge/OPSEC-hardened-blue.svg)
![Airgap](https://img.shields.io/badge/airgap-ready-informational.svg)
![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)

An **OPSEC-hardened, airgap-ready Kali Linux golden image** for authorized penetration testing —
built as a full **libvirt/KVM virtual machine**, cloned per engagement and destroyed at close, so
nothing ever bleeds between clients and your box never beacons on a target's LAN.

Container-based toolkits (Exegol, and friends) already do fast, disposable environments well. This
project deliberately takes the **VM road** and leans into the parts those tools leave on the table:

- **Kernel-level isolation** — a real VM boundary per engagement, not a shared kernel.
- **OPSEC hardening as a first-class feature** — mDNS/LLMNR/Bluetooth off, gateway-only DNS,
  default-deny inbound with no ping, key-only SSH, root locked. A clone stays quiet on a client LAN.
- **Airgap-ready** — an offline cheatsheet, wordlists, exploit DB and a grab-and-go payload kit are
  baked in; once the master is built, engagements run with **no connectivity at all**.
- **Reproducible-as-code** — the image is a build artifact; this repo is the source of truth, so a
  tagged version answers "what tools were present during testing" from a commit.

## Quick start

```bash
# one-time, online: build the master from the pinned Kali base image
./bootstrap.sh

# per engagement (fully offline from here on):
./goldenctl new acme-corp --vpn client.ovpn --resources ./my-resources
./goldenctl ssh acme-corp          # work happens only inside the clone
./goldenctl close acme-corp        # destroy VM + storage at close
```

`goldenctl` is the single entry point:

| Command | Does |
|---|---|
| `goldenctl build` | build the master from scratch (online, once) |
| `goldenctl new <id> [--vpn f.ovpn] [--resources DIR]` | clone a fresh, isolated engagement VM (optionally inject a VPN config and your personal tooling) |
| `goldenctl ssh <id>` | shell into an engagement clone |
| `goldenctl list` / `status` | show the master + clones and their addresses |
| `goldenctl update` | refresh the master's toolset (`update-golden`) |
| `goldenctl export <id>` | archive an engagement's work (hashed + timestamped) — do this before close |
| `goldenctl close <id>` | destroy an engagement (VM + storage) |

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
  CherryTree, Flameshot, OpenVPN, and a self-contained offline HTML cheatsheet.

Full inventory in [`CHANGELOG.md`](CHANGELOG.md).

## `my-resources` — your kit, in every clone

Drop personal scripts, wordlists, aliases or configs into a folder and pass it to
`goldenctl new … --resources DIR`; it lands in `~/my-resources` inside the clone. See
[`my-resources/README.md`](my-resources/README.md). (Inspired by Exegol's my-resources — the one
idea from that world too good not to borrow.)

## Cross-contamination model

The master is a **sealed template**, never a workspace — no client IPs, creds, names or history.
`goldenctl new` clones it and generalizes the copy (fresh machine-id, SSH host keys, Metasploit DB,
wiped BloodHound graph, empty workspace). `goldenctl close` destroys the VM, disk and snapshots.
On an encrypted host, deletion leaves nothing recoverable at rest.

Because close is irreversible, **run `goldenctl export <id>` first** — it pulls the workspace and
CherryTree notes off the clone into a timestamped, SHA-256-hashed archive for evidence retention, and
`close` refuses to destroy an engagement that has no export (unless you explicitly override).

## Repository layout

| Path | Purpose |
|------|---------|
| `goldenctl` | unified CLI for the whole lifecycle |
| `bootstrap.sh` | one-command online build of the master |
| `provision-golden.sh` | installs the toolset into a fresh Kali base VM |
| `new-engagement.sh` / `close-engagement.sh` | low-level clone/destroy primitives |
| `update-golden.sh` | interactive full refresh + changelog rewrite |
| `policies.json` | Firefox enterprise policy (extensions + bookmarks) |
| `pentest-cheatsheet.html` | offline reference bundled into the image |
| `packer/` | one-command declarative build (IaC) — `./packer/build.sh` |
| `RUNBOOK.md` / `CHANGELOG.md` | operations guide + version history |

## Roadmap

- One-command **Packer** build ships in `packer/`; an **Ansible/Nix** path is the next IaC step.
- **Airgapped master**: bundled apt/PyPI/git mirrors so even the *build* runs offline.
- Slim **image profiles** (light / AD / web) alongside the full master.
- Optional **USB passthrough** and **X11** recipes for wireless and GUI-heavy work.

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md). Keep the master lean — engagement-specific or heavyweight
tooling belongs on a clone, not the baseline.

## License

MIT — see [`LICENSE`](LICENSE).

> For authorized security testing only. You are responsible for having permission to test any
> system you point these tools at.

## AI Declaration
This tool was made entirely with Claude Opus 4.8 under strict guidance and instruction. Every tool and feature of the product is deliberate, based on modern offensive cyber methodologies and personal preferences.
Each line of code in the startup and teardown scripts have been manually reviewed.
