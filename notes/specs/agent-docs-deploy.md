# Live Agent Docs Deployment: Complete

## Summary

✅ **1. Private GitHub repo created**: https://github.com/Mach1212/agent-docs (personal, not org)

✅ **2. Agent instructions added** to `AGENTS.md`:
- **Chat start check**: Fetch origin, ensure no local changes, merge if behind
- **Discovery protocol**: When you find new architecture, update the relevant doc, commit with `[Discover]` prefix, and push
- Only checked on first message of a chat session (not continuously)

✅ **3. Deploy automation**: `dev-env.sh` updated to:
- Clone `agent-docs` to `~/personal/agent-docs` on each machine
- Configure git author as `agent@<hostname>.dev.fyre.ibm.com`
- Symlink `~/.agents → ~/personal/agent-docs`
- OpenCode reads from `~/.agents/AGENTS.md` (hardcoded in `opencode.jsonc`)

## Agent Workflow

1. **Chat starts** → agent pulls latest `git fetch origin`, checks for conflicts
2. **Analysis runs** → discovers pattern not in docs
3. **Updates docs** → `git commit -m "[Discover] pattern in repo"` + `git push origin master`
4. **Next agent** → pulls the discovery, inherits the knowledge

## Access & Auth

- SSH key on each machine (`/root/.ssh/t3ibm_deploy`) has write access to the repo
- No manual intervention needed—agents commit & push directly
- Workstation can pull to stay in sync
