#!/bin/sh
# Multi-user Nix on RHEL. Run as root on the target.
set -eu

conf_snippet=$(mktemp)
cat > "$conf_snippet" <<'EOF'
experimental-features = nix-command flakes
trusted-users = root
EOF

if [ ! -x /nix/var/nix/profiles/default/bin/nix ]; then
  curl -fsSL https://nixos.org/nix/install | sh -s -- \
    --daemon \
    --yes \
    --no-channel-add \
    --nix-extra-conf-file "$conf_snippet"
fi
rm -f "$conf_snippet"

nix_conf=/etc/nix/nix.conf
touch "$nix_conf"
grep -q '^experimental-features' "$nix_conf" || echo 'experimental-features = nix-command flakes' >> "$nix_conf"
grep -q '^trusted-users' "$nix_conf" || echo 'trusted-users = root' >> "$nix_conf"

if systemctl is-active --quiet nix-daemon; then
  systemctl restart nix-daemon
else
  systemctl enable --now nix-daemon
fi

mkdir -p /usr/local/bin
for bin in nix nix-env nix-store nix-copy-closure nix-instantiate nix-build nix-channel; do
  src=/nix/var/nix/profiles/default/bin/$bin
  if [ -e "$src" ]; then
    ln -sfn "$src" "/usr/local/bin/$bin"
  fi
done

nix --version
ok=0
i=0
while [ "$i" -lt 15 ]; do
  if nix store ping --extra-experimental-features 'nix-command flakes'; then
    ok=1
    break
  fi
  i=$((i + 1))
  sleep 1
done
[ "$ok" = 1 ]
