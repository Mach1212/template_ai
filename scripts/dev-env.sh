#!/bin/sh
# Clone askswsupport, hyparest and WatsonFlow into /home/mach12/projects on a Fyre host,
# each on the first of dev_env → development/dev → main/master that exists on origin,
# drop in the decrypted local.env files, install deps, and rsync the action-recommender models.
# Needs a deploy first (tools, op sign-in, git credential, local.env under ~/.config/t3-dev-env).
#   ./scripts/dev-env.sh mach121
set -eu

host=${1:?usage: dev-env.sh <host>}
fqdn=$host.dev.fyre.ibm.com
user=mach12
projects=${PROJECTS:-$HOME/projects}
ssh="ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ServerAliveInterval=30"

echo "== clone + deps on $fqdn =="
$ssh "root@$fqdn" "su - $user -c 'bash -s'" <<'EOF'
set -euo pipefail
cd ~/projects

clone_org() {
  url=https://github.ibm.com/sw-support-automation/$1.git
  if [ ! -d "$1/.git" ]; then
    git clone "$url" "$1"
  fi
  git -C "$1" fetch origin
  for b in dev_env development dev main master; do
    if git -C "$1" rev-parse -q --verify "refs/remotes/origin/$b" >/dev/null; then
      git -C "$1" checkout -B "$b" "origin/$b"
      git -C "$1" branch --set-upstream-to "origin/$b" "$b"
      echo "$1 -> $b"
      return
    fi
  done
  echo "$1: no dev_env/development/dev/main/master on origin" >&2
  return 1
}
clone_personal() {
  url=https://github.com/Mach1212/$1.git
  if [ ! -d "$1/.git" ]; then
    git clone "$url" "$1"
  fi
  git -C "$1" fetch origin
  if git -C "$1" rev-parse -q --verify "refs/remotes/origin/master" >/dev/null; then
    git -C "$1" checkout -B master "origin/master"
    git -C "$1" branch --set-upstream-to "origin/master" master
    echo "$1 -> master"
    return
  fi
  echo "$1: no master on origin" >&2
  return 1
}
clone_org askswsupport
clone_org hyparest
clone_org WatsonFlow
clone_personal agent-docs

install -m 600 ~/.config/t3-dev-env/askswsupport.local.env askswsupport/nodejs-app01/local.env
install -m 600 ~/.config/t3-dev-env/hyparest.local.env hyparest/local.env
ln -sfn ../agent-docs ~/.agents
host=$(hostname -s)
git -C agent-docs config user.email "agent@$host.dev.fyre.ibm.com"
git -C agent-docs config user.name "Agent ($host)"
sed -i -E \
  -e "s|/Users/mach12/projects|$HOME/projects|g" \
  -e "s/^([A-Z0-9_]*QUEUE[A-Z0-9_]*=)([^ #]+)/\1\2_$host/" \
  askswsupport/nodejs-app01/local.env hyparest/local.env

(cd askswsupport/nodejs-app01 && npm ci --no-audit --no-fund)
(cd hyparest && poetry env use /usr/bin/python3.12 && poetry lock && poetry install --no-interaction)
EOF

echo "== models -> $fqdn =="
models=$projects/askswsupport/fm-action-recommender/models
$ssh "root@$fqdn" "install -d -o $user -g $user /home/$user/projects/askswsupport/fm-action-recommender/models"
rsync -a --info=progress2 --chown=$user:$user \
  -e "$ssh" "$models/" "root@$fqdn:/home/$user/projects/askswsupport/fm-action-recommender/models/"

echo "== op check =="
$ssh "root@$fqdn" "su - $user -c 'op whoami'"
