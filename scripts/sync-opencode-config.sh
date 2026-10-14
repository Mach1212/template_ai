#!/bin/sh
# Export the OpenCode config worktree into ./opencode-config and agent_docs
# into ./payload/agent-docs. Both directories are gitignored.
# OpenCode source: github.ibm.com bob_code. agent_docs: ~/personal/agent_docs.
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
src=${OPENCODE_CONFIG:-/Users/mach12/.config/opencode}
agent_docs=${AGENT_DOCS:-/Users/mach12/personal/agent_docs}
dest=$root/opencode-config
docs=$root/payload/agent-docs

if [ ! -d "$src/.git" ]; then
  echo "not a git checkout: $src" >&2
  exit 1
fi
if [ ! -f "$agent_docs/AGENTS.md" ]; then
  echo "missing agent docs: $agent_docs" >&2
  exit 1
fi

rm -rf "$dest" "$docs" "$root/payload/projects-agents.md"
mkdir -p "$dest" "$docs"

git -C "$src" ls-files -z | while IFS= read -r -d '' file; do
  mkdir -p "$dest/$(dirname "$file")"
  cp -a "$src/$file" "$dest/$file"
done

tar -C "$agent_docs" \
  --exclude .git \
  --exclude .omo \
  --exclude .codegraph \
  --exclude .DS_Store \
  -cf - . | tar -C "$docs" -xf -

git -C "$src" rev-parse HEAD > "$dest/.rev"
echo "exported $(git -C "$src" rev-parse --short HEAD) -> $dest"
echo "exported $agent_docs -> $docs"
