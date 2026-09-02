# Contributing

Thanks for your interest. This project is a reproducible, OPSEC-hardened Kali golden image; the goal
is a baseline that's identical on every engagement and safe to run on a client's network.

## Ground rules

- **Keep the master lean.** Anything used on *every* engagement can go in the baseline. Engagement-
  specific, heavyweight, or noisy tooling belongs on a clone (via `my-resources` or a per-engagement
  install), not the shared master.
- **Don't weaken the OPSEC posture.** New tools must not re-enable network beaconing (mDNS/LLMNR/
  Bluetooth), open inbound ports on the baseline, or bake in credentials/keys. If a tool needs a
  listening service, document turning it on per-engagement.
- **No secrets, ever.** No private keys, VPN configs, client names, IPs, or hostnames in commits.
  The `.gitignore` guards the obvious cases — keep it that way.
- **Fault-tolerant provisioning.** `provision-golden.sh` logs and skips a failing item rather than
  aborting. Preserve that; add new installs through the existing helpers.

## Making changes

1. Test on a throwaway clone, never the master.
2. If you add a tool, add it to `provision-golden.sh` **and** note it in `CHANGELOG.md`.
3. Run `bash -n` on any script you touch; keep scripts POSIX-bash and shellcheck-clean where practical.
4. Keep line endings LF (`.gitattributes` enforces this).

## Good first issues

- Wire up the cloud-init / virt-customize bootstrap so `packer/` becomes a one-shot build.
- Add slim image profiles (light / AD / web).
- USB-passthrough and X11 recipes for wireless and GUI-heavy engagements.
- Airgapped-master mirroring (apt / PyPI / git) so the build itself can run offline.
