# Dev env on mach121

Demo: copy the workstation dev env (`~/projects`) to `mach121` (`/home/mach12/projects`).

- Clone `askswsupport` and `hyparest` (both on `dev_env`) and `WatsonFlow` (next to them) into `/home/mach12/projects`.
- `npm run devEnv` (`askswsupport/nodejs-app01`) and `./run.sh` (`hyparest`) work on the host.
- Both resolve secrets through 1Password (`curl -sL https://ibm.biz/mach12_1pass | sh` → `op inject` of `base.env` + `local.env` → `.env`).

## How

- Tools come from the flake deploy profile, for all hosts: 1Password CLI, node 18, nodemon, poetry. `scripts/dev-env.sh <host>` does the clones, env files, and models (run for `mach121` now).
- 1Password: no service account. `op` signs in by itself on the host with the user's email, password, Secret Key, and two-factor TOTP seed (codes generated on the host) from SOPS, so it works without the user.
- `local.env` (plaintext secrets that aren't in 1Password) is SOPS-encrypted in this repo and decrypted on the host.
- Each host gets its own queues: every queue name in its `local.env` has `_<host>` appended (`ask_input_maciej_dev` → `ask_input_maciej_dev_mach121` on mach121, `_mach122` on mach122, …).
- Git: a github.ibm.com token on the host (SOPS), so the host can fetch and push.
- WatsonFlow: hyparest `dev_env` commits the new path to WatsonFlow (the sibling clone) in place of `/Users/mach12/projects/WatsonFlow`.
- `askswsupport/fm-action-recommender/models` (1.4 GB) is rsynced to the host.
