# Fyre deploy

Manage these RHEL 10.2 x86_64 hosts with Nix + deploy-rs:

- mach121.dev.fyre.ibm.com
- mach122.dev.fyre.ibm.com
- mach123.dev.fyre.ibm.com
- mach124.dev.fyre.ibm.com

SSH and the deploy-rs profile user are `root`. A login user `mach12` (`/home/mach12`) owns the T3 Code server and the OpenCode config. Do not run T3 Code as root.

## Nix

Multi-user Nix (upstream installer, daemon, flakes) on each host. Nix binaries are on the non-interactive SSH `PATH` via `/usr/local/bin`.

This flake is the desired state. Apply it with deploy-rs from a host that can build `x86_64-linux` (the Fyre machines). The workstation is `aarch64-darwin` and is not a Linux builder.

## T3 Code server

- Package: nixpkgs `t3code`, OpenCode on its `PATH`, Codex not wrapped in.
- systemd unit `t3code.service`, enabled at boot.
- `t3 serve --host 0.0.0.0 --port 3773 --base-dir /home/mach12/.t3`
- User `mach12`.

## OpenCode config

Source: working tree of `https://github.ibm.com/Maciej-Pruchnik/bob_code.git` (`/Users/mach12/.config/opencode`). Installed to `/home/mach12/.config/opencode`.

That repo stays the config’s GitHub. Do not commit it into this repo (this repo’s current GitHub remote is the public template).

- Materialize `AGENTS.md` from `/Users/mach12/.grok/rules/AGENTS.md` (the git link points at that Mac path).
- Rewrite the instructions path to `/home/mach12/projects/.agents/AGENTS.md` and install that file from `/Users/mach12/projects/.agents/AGENTS.md`.
- `shell` stays `zsh`. `zsh` and `git` are on the service `PATH`.
- Do not vendor `oh-my-openagent/` or `node_modules`. OpenCode loads `oh-my-openagent` itself.
- Playwright on these hosts is headless Chromium from the Nix profile (`playwright-mcp --headless`). The deployed `skills/playwright/SKILL.md` is replaced at activation. The workstation skill stays the Edge extension. No Edge session and no `PLAYWRIGHT_MCP_EXTENSION_TOKEN` on the hosts. Headless Chromium does not have the workstation's Edge cookies.
- Secrets are SOPS (age). `secrets/api.key.env` is only these names, taken from the workstation `~/projects/api.key`:
  - `IBM_ICA_DEV_API_KEY`
  - `CARBON_MCP_TOKEN`
  - `CARBON_MCP_SESSION`
  - `JIRA_PERSONAL_TOKEN`
  - `ELASTICSEARCH_ADDRESS`
  - `ELASTICSEARCH_USERNAME`
  - `ELASTICSEARCH_PASSWORD`
  - `ELASTICSEARCH_PROD_ADDRESS`
  - `ELASTICSEARCH_PROD_API_KEY`
- Activation decrypts that file to `/home/mach12/projects/api.key` (mode 600). The plaintext is not in git and not in the Nix store. Other names in `~/projects/api.key` stay off the hosts.
- Recipients: the existing mach12 age key (`age1m40j2a34zls3en9nng35asknxwvf7yttrdskr4sjn5w9a4jltyjqepmsvr`) and each host’s SSH host key (`/etc/ssh/ssh_host_ed25519_key`, converted with `ssh-to-age`). No extra private key is copied onto the hosts.

Profile path: `/nix/var/nix/profiles/t3`.
