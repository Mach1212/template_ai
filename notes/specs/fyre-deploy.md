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

- Package: nixpkgs `t3code` (stable 0.0.45), Codex not wrapped in. OpenCode is the latest 1.x T3 supports (1.19.0, nixpkgs), the same version on the hosts and the workstation. No OpenCode 2.x, no T3 nightly.
- Workstation (`mach12book`): OpenCode 1.19.0 from Nix (`~/nix_config`, not brew) and the stable `t3-code` cask.
- Every OpenCode plugin loads on 1.x: `ibm-ica-auth` (1.x plugin API, works with or without a stored `ica` auth entry), `oh-my-openagent`, `openrtk`, and on the workstation `edge-cookies-webfetch`.
- Hosts do not get workstation-only pieces: no `edge-cookies-webfetch` plugin, no `jupyter` skill.
- systemd unit `t3code.service`, enabled at boot.
- `t3 serve --host 0.0.0.0 --port 3773 --base-dir /home/mach12/.t3`
- User `mach12`.
- Service env sets `NIX_SSL_CERT_FILE` and `SSL_CERT_FILE` to `/etc/pki/tls/certs/ca-bundle.crt`, so Nix tools (npx MCP servers, git) verify TLS.

## OpenCode config

Source: working tree of `https://github.ibm.com/Maciej-Pruchnik/bob_code.git` (`/Users/mach12/.config/opencode`). Installed to `/home/mach12/.config/opencode`.

That repo stays the config’s GitHub. Do not commit it into this repo (this repo’s current GitHub remote is the public template).

- Install the repo’s committed `AGENTS.md` with the rest of the config. OpenCode loads `/home/mach12/.config/opencode/AGENTS.md` as the global agent doc. Do not overlay `~/.grok/rules/AGENTS.md`. Do not list that file in `instructions`.
- Sisyphus reasoning is `max`. The lead model `ica/claude-opus-5-5` pins its low, medium, and high variants to `reasoningEffort: max`, because T3 always sends one of those variants and that variant overrides the model option.
- `shell` stays `zsh`. `zsh` and `git` are on the service `PATH`.

## agent_docs

Source: `https://github.ibm.com/Maciej-Pruchnik/agent_docs` (private, `master`), the cross-repo knowledge repo. Not committed into this repo and not copied in by the deploy.

- `/home/mach12/projects/.agents` is a git clone of that repo, owned by `mach12`. The deploy clones it when it is missing and leaves an existing clone alone (agents commit and push there).
- Clone git author: `Agent (<host>)` / `agent@<host>.dev.fyre.ibm.com`.
- Rewrite the OpenCode `instructions` path to `/home/mach12/projects/.agents/AGENTS.md`. Sibling docs (`analyze/`, `askswsupport/`) stay beside it.
- Agents check the clone is up to date once, on the user's first message of a conversation (rule lives in the repo's `AGENTS.md`).
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
- The OpenCode skills' MCP servers (Jira, GitHub, Elasticsearch) work on the hosts like on the workstation: their commands (`uvx`, `npx`, `github-mcp-server`) are at the workstation's paths, and their tokens are in the `t3code` service env (`api.key`, plus the github.ibm.com token as `GITHUB_PERSONAL_ACCESS_TOKEN`).
- `rtk` is on the host `PATH` so the `openrtk` plugin works there too.
- Deployed config and agent docs have no macOS AppleDouble (`._*`) files.
- Recipients: the existing mach12 age key (`age1m40j2a34zls3en9nng35asknxwvf7yttrdskr4sjn5w9a4jltyjqepmsvr`) and each host’s SSH host key (`/etc/ssh/ssh_host_ed25519_key`, converted with `ssh-to-age`). No extra private key is copied onto the hosts.

Profile path: `/nix/var/nix/profiles/t3`.
