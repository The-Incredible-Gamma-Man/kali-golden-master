# my-resources

Your **personal kit**, injected into every engagement clone at spin-up.

Drop anything you want available on a fresh clone into this folder — custom scripts, wordlists,
aliases, tmux/zsh configs, note templates — then launch with:

```bash
goldenctl new <id> --resources ./my-resources
```

Everything here lands in `~/my-resources` inside the clone. The idea is borrowed from Exegol's
`my-resources`: keep the golden master lean and generic, and layer *your* preferences on per
engagement rather than baking them into the shared baseline.

## Notes

- The **contents of this folder are git-ignored** (only this README is tracked). It's meant for your
  local, possibly sensitive customizations — never commit client-specific material here.
- Keep it lightweight; large or engagement-specific data belongs in the clone's workspace, not here.
- A simple `setup.sh` in here (if present) is a handy convention to run your own post-clone tweaks.
