# Changelog

All notable changes to this project are documented here. Version tags follow the
`kali-baseline-vMAJOR.MINOR-YYYY-MM` scheme so a tag answers "what tools were present
during testing" at a glance.

## [v1.4-2026-09] — Sliver C2 integrated

### Added
- **Sliver (Bishop Fox) C2** — the `sliver-server` and `sliver-client` linux-amd64 binaries are staged
  under `/opt/sliver` and symlinked onto `PATH` via `/opt/tools/bin`, alongside the existing
  post-exploitation kit (Metasploit, nishang, webshells).
  - **`provision-golden.sh`** pins **v1.7.7** with SHA-256 verification through the existing
    `fetch_pinned` path (server `10c78c3b…2b55`, client `4289cd1d…052b`), so a moved or tampered
    upstream binary fails the build loudly instead of baking an unverified C2 into the image.
    Upstream also minisign-signs every asset (Bishop Fox key noted in the script).
  - **`opt-tools.sh`** / **`update-golden.sh`** fetch the latest release on the non-pinned/refresh
    paths, and `update-golden.sh` records the installed Sliver version in the CHANGELOG manifest.
  - Like the pre-staged Nessus, the server is **staged but not started or activated** — an operator
    runs `sliver-server` per engagement, which then generates its own certs and config on first run.
- **Offline Sliver armory** — `provision-golden.sh` (and `update-golden.sh` on refresh) best-effort
  caches the armory **extensions/aliases** (BOFs, .NET post-ex, situational-awareness) into
  `/home/kali/.sliver-client/{aliases,extensions}`, so a locked-down engagement box needs no
  internet — same rationale as the offline nuclei-templates / PayloadsAllTheThings staging. `armory`
  is a Sliver *console* command (no `sliver-client armory` subcommand exists), so it's driven
  headlessly through `sliver-server --rc` as the `kali` user. Failures are logged, never fatal.
- **Sliver loot in evidence exports** — `export-engagement.sh` now also captures the Sliver server
  state (`~/.sliver`: loot store, creds/host DB, session + audit logs, certs; the unpacked Go
  toolchains (Go + Zig) are excluded) on both the SSH and offline (`virt-copy-out`) paths, folded into the same
  hashed/signed archive and recorded as `sliver_state:` in the `.meta.txt`. Sliver is optional, so
  its absence never marks an archive incomplete.

### Changed / OPSEC
- **Clone generalize + master seal reset Sliver state.** `new-engagement.sh` (per clone) and
  `clean-master.sh` (master) now wipe `~/.sliver` (server CA/loot/DB) and the per-operator
  `~/.sliver-client/configs`, alongside the existing Metasploit-DB reinit and neo4j wipe. This closes
  a cross-contamination hazard: baking one Sliver **CA** into the template would give every clone a
  shared implant trust root. The generic armory extensions/aliases are deliberately preserved.

## [v1.3-2026-09] — hardening baked into the build + fixes

### Added
- **`harden.sh`** — applies the full OPSEC/security baseline (root locked, key-only SSH, UFW
  default-deny-in with no ping, gateway-only DNS, mDNS/LLMNR/Bluetooth/CUPS off) and removes the
  build-time passwordless sudo. Now wired into **both** `bootstrap.sh` and the Packer build, so a
  fresh build produces a hardened master automatically — no manual steps.
- **Password prompt on build** — `bootstrap.sh` and `packer/build.sh` prompt for a `kali` password
  (fed to `harden.sh` on stdin / via `PKR_VAR_kali_password`); leaving it blank keeps the default.
  SSH stays key-only regardless, so this only governs console/sudo access.

### Fixed
- **`goldenctl new --vpn` / `--resources`** race: the injection ran before the clone's first-boot
  finished creating the workspace, so the copy could fail with "No such file or directory". It now
  waits for SSH and creates the target directory first.

## [v1.2-2026-09] — evidence retention

### Added
- **`export-engagement.sh`** / **`goldenctl export <id>`** — pull an engagement's workspace and
  CherryTree notes off the clone into a **timestamped, SHA-256-hashed** archive (per-file manifest +
  archive hash + metadata) for evidence retention. Works whether the clone is running (SSH) or shut
  off (offline via `virt-copy-out`).
- **Close guard** — `close-engagement.sh` now refuses to destroy an engagement that has no export,
  unless you explicitly type an override. No more nuking un-exported evidence by reflex.

## [v1.1-2026-09] — CLI, VPN/my-resources, IaC scaffold

### Added
- **`goldenctl`** — one unified CLI for the whole lifecycle: `build`, `new`, `ssh`, `list`,
  `status`, `update`, `close`.
- **`bootstrap.sh`** — one-command online build of the master from the pinned Kali base image.
- **VPN injection** — `goldenctl new <id> --vpn client.ovpn` drops a VPN config into the clone.
- **`my-resources`** — `goldenctl new <id> --resources DIR` injects your personal tooling into
  `~/my-resources` on the clone (Exegol-style), keeping the master generic.
- **`packer/`** — one-command declarative (Packer) build path (`./packer/build.sh`) that prepares an
  SSH-enabled base and builds a portable, sealed image artifact.
- **`CONTRIBUTING.md`**; README repositioned around the OPSEC-hardened / airgap-ready / VM-isolated
  differentiator.

### Notes
- Building the master needs connectivity; once built, launching engagements is **fully offline**.

## [v1.0-2026-08] — Kali 2026.2 base

Initial golden-master recipe. Built as a libvirt/KVM VM on a full-disk-encrypted host.

### Toolset
- **Kali metapackages:** web, database, passwords, vulnerability, post-exploitation,
  windows-resources.
- **Recon / web:** nmap, masscan, gobuster, ffuf, feroxbuster, nikto, whatweb, wpscan, sqlmap,
  nuclei (+ templates), httpx, subfinder, naabu, dnsx, katana, gowitness, eyewitness, amass,
  dalfox, wfuzz, dirsearch.
- **AD / lateral movement:** Impacket suite (psexec, smbexec, wmiexec, atexec, dcomexec,
  secretsdump, ntlmrelayx, GetUserSPNs, GetNPUsers), netexec, evil-winrm, kerbrute, certipy-ad,
  coercer, pywerview, mitm6, responder, bloodhound (+ neo4j).
- **Credentials:** hashcat, john, pypykatz, samdump2, mimikatz, donpapi, manspider; rockyou
  gunzipped.
- **Post-exploitation / pivot:** chisel, ligolo-ng, sshuttle, proxychains4, linpeas, winpeas,
  pspy — droppables staged under `/opt/deploy`.
- **Exploits / references:** searchsploit (Exploit-DB), SecLists, PayloadsAllTheThings; vulners
  and vulscan NSE scripts; NSE script DB rebuilt.
- **Workflow:** AutoRecon, Metasploit, CherryTree, Flameshot, OpenVPN, and a self-contained
  offline HTML cheatsheet.
- **pipx (global):** certipy-ad, coercer, pywerview, man-spider, bloodhound-ce, autorecon, donpapi.

### Firefox
- Enterprise policy force-installs Wappalyzer + FoxyProxy from local copies.
- Curated bookmarks bar (revshells, GTFOBins, LOLBAS, HackTricks, PayloadsAllTheThings, CyberChef,
  crt.sh, Exploit-DB, MITRE ATT&CK, …); telemetry and Pocket disabled.
- FoxyProxy import file for Burp (127.0.0.1:8080) and a SOCKS5 pivot (127.0.0.1:1080).

### Hardening
- root account locked; SSH key-only (no password auth, no root login).
- UFW: default deny incoming, allow outgoing, allow SSH; inbound ICMP echo dropped.
- Gateway-only DNS (no external resolvers baked in).
- mDNS/avahi, LLMNR, Bluetooth, CUPS and ModemManager disabled — no beaconing on a target LAN.

### Cross-contamination controls
- Master is a sealed template; work happens only on clones.
- `new-engagement.sh` clones the master and generalizes it (fresh machine-id, SSH host keys,
  Metasploit DB, wiped BloodHound graph, empty workspace).
- `close-engagement.sh` destroys the VM, its disk and snapshots at engagement close.

### Airgapped
- Cheatsheet, wordlists and offline references bundled so an engagement clone needs no internet.
- `update-golden.sh` refreshes everything and regenerates a version manifest when connectivity
  is available.
