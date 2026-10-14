# Branch Priority Policy

All repos **must** use this branch priority order:

1. **`dev_env`** — personal overlay branch (local-useful only, not shipped)
2. **`dev` or `development`** — integration branch (features land here)
3. **`main` or `master`** — release branch (only after user approval)

## Checkout Logic

When cloning or switching, check for the first branch that exists on origin in this order:
```
dev_env → dev (or development) → main (or master)
```

## Shipping (Feature Branch)

Feature commits are **cherry-picked** from `dev_env` onto a clean branch off `dev`/`development`, then a PR is opened (base = `dev`/`development`).

After ship: `git checkout dev_env` → `git merge <feature-branch>` → stay on `dev_env`.

Never ship the old `dev_env`-only commits. Only feature commits from this work.

## `dev_env` Overlay

`dev_env` may diverge from `dev`/`development`. That is expected and intentional. It holds user-local commits that must not land on any shared branch.
