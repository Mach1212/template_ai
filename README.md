# t3ibm

deploy-rs for four RHEL Fyre hosts. Each host gets multi-user Nix, a `t3code` server on port 3773, and the OpenCode config from `github.ibm.com/Maciej-Pruchnik/bob_code`.

```sh
./scripts/deploy.sh
```

`scripts/sync-opencode-config.sh` fills gitignored `opencode-config/` and `payload/` from the local checkout before deploy. `secrets/api.key.env` is a SOPS dotenv of the OpenCode keys only (ICA, Carbon, Jira, Elasticsearch). Hosts decrypt it with their SSH host key. The Playwright skill on the hosts is rewritten to headless Chromium; the workstation copy stays the Edge extension.

The workstation cannot build `x86_64-linux`. `deploy.sh` bootstraps Nix, then runs `nix run .#deploy-rs -- --skip-checks .` on `mach121`. The package is `deploy-rs`, not `deploy`, so `.#deploy` stays the deploy-rs node set.
