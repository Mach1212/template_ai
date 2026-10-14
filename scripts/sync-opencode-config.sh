#!/bin/sh
# Export the OpenCode config worktree into ./opencode-config and ./payload.
# Those directories are gitignored. Source repo: github.ibm.com bob_code.
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
src=${OPENCODE_CONFIG:-/Users/mach12/.config/opencode}
agents_src=${OPENCODE_AGENTS:-/Users/mach12/.grok/rules/AGENTS.md}
projects_agents=${PROJECTS_AGENTS:-/Users/mach12/projects/.agents/AGENTS.md}
dest=$root/opencode-config

if [ ! -d "$src/.git" ]; then
  echo "not a git checkout: $src" >&2
  exit 1
fi

rm -rf "$dest"
mkdir -p "$dest" "$root/payload"

git -C "$src" ls-files -z | while IFS= read -r -d '' file; do
  case $file in
    AGENTS.md) continue ;;
  esac
  mkdir -p "$dest/$(dirname "$file")"
  cp -a "$src/$file" "$dest/$file"
done

cp -a "$agents_src" "$dest/AGENTS.md"
cp -a "$projects_agents" "$root/payload/projects-agents.md"
git -C "$src" rev-parse HEAD > "$dest/.rev"
echo "exported $(git -C "$src" rev-parse --short HEAD) -> $dest"
