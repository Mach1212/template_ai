#!/bin/sh
# Export the OpenCode config worktree into ./opencode-config (gitignored).
# Source: github.ibm.com bob_code. agent_docs is cloned on the hosts, not exported.
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
src=${OPENCODE_CONFIG:-/Users/mach12/.config/opencode}
dest=$root/opencode-config

if [ ! -d "$src/.git" ]; then
  echo "not a git checkout: $src" >&2
  exit 1
fi

rm -rf "$dest" "$root/payload"
mkdir -p "$dest"

git -C "$src" ls-files -z | while IFS= read -r -d '' file; do
  mkdir -p "$dest/$(dirname "$file")"
  cp -a "$src/$file" "$dest/$file"
done

git -C "$src" rev-parse HEAD > "$dest/.rev"
echo "exported $(git -C "$src" rev-parse --short HEAD) -> $dest"
