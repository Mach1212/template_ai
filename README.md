# t3ibm

deploy-rs for four RHEL Fyre hosts. Each host gets multi-user Nix, a `t3code` server on port 3773, and the OpenCode config from `github.ibm.com/Maciej-Pruchnik/bob_code`.

```sh
./scripts/deploy.sh
```

`scripts/sync-opencode-config.sh` fills gitignored `opencode-config/` from the local OpenCode checkout (including its committed `AGENTS.md`) and `payload/agent-docs/` from `~/personal/agent_docs`. On each host, `~/projects/.agents` is a symlink to `~/personal/agent_docs`, which is the path OpenCode's `instructions` reads. `secrets/api.key.env` is a SOPS dotenv of the OpenCode keys only (ICA, Carbon, Jira, Elasticsearch). Hosts decrypt it with their SSH host key. The Playwright skill on the hosts is rewritten to headless Chromium; the workstation copy stays the Edge extension.

The workstation cannot build `x86_64-linux`. `deploy.sh` bootstraps Nix, then runs `nix run .#deploy-rs -- --skip-checks .` on `mach121`. The package is `deploy-rs`, not `deploy`, so `.#deploy` stays the deploy-rs node set.

Dev env: `nix develop -c ./scripts/dev-env-secrets.sh` encrypts the 1Password sign-in (password, Secret Key, TOTP seed), the github.ibm.com token, and both `local.env` files into `secrets/`. After a deploy, `./scripts/dev-env.sh <host>` clones askswsupport and hyparest (`dev_env`) and WatsonFlow into `~/projects`, installs dependencies, and copies the action-recommender models. On the hosts, `op` signs in by itself, so `npm run devEnv` and `./run.sh` work without anyone signing in.
