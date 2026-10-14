#!/bin/sh
# Install Nix if needed, then deploy-rs from mach121 to every Fyre host.
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
hosts="mach121 mach122 mach123 mach124"
domain=dev.fyre.ibm.com
ssh="ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ServerAliveInterval=30"
"$root/scripts/sync-opencode-config.sh"
chmod +x "$root/scripts/bootstrap-nix.sh"

for host in $hosts; do
  fqdn=$host.$domain
  echo "== bootstrap $fqdn =="
  $ssh "root@$fqdn" 'sh -s' < "$root/scripts/bootstrap-nix.sh"
done

echo "== deploy key on mach121 =="
$ssh "root@mach121.$domain" 'sh -s' <<'EOF'
set -eu
mkdir -p /root/.ssh
chmod 700 /root/.ssh
if [ ! -f /root/.ssh/t3ibm_deploy ]; then
  ssh-keygen -t ed25519 -N "" -f /root/.ssh/t3ibm_deploy -C t3ibm-deploy
fi
cat /root/.ssh/t3ibm_deploy.pub
EOF

pub=$($ssh "root@mach121.$domain" 'cat /root/.ssh/t3ibm_deploy.pub')

for host in $hosts; do
  fqdn=$host.$domain
  echo "== authorize deploy key on $fqdn =="
  $ssh "root@$fqdn" "umask 077; mkdir -p /root/.ssh; touch /root/.ssh/authorized_keys; grep -qxF '$pub' /root/.ssh/authorized_keys || echo '$pub' >> /root/.ssh/authorized_keys"
  $ssh "root@$fqdn" 'rm -rf /root/t3ibm-secrets'
done

echo "== copy flake to mach121 =="
# COPYFILE_DISABLE: macOS tar otherwise adds AppleDouble `._*` files, which OpenCode then loads as plugins
COPYFILE_DISABLE=1 tar -C "$root" \
  --exclude .git \
  --exclude notes \
  -czf - . | $ssh "root@mach121.$domain" 'rm -rf /root/t3ibm && mkdir -p /root/t3ibm && tar -C /root/t3ibm -xzf -'

echo "== deploy =="
$ssh "root@mach121.$domain" 'nix run /root/t3ibm#deploy-rs -- --skip-checks /root/t3ibm'
