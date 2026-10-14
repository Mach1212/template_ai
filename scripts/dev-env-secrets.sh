#!/bin/sh
# Encrypt the dev-env secrets for the Fyre hosts (run on the workstation, via `nix develop -c`).
#   secrets/dev-env.env                     1Password sign-in + github.ibm.com token
#   secrets/<repo>.local.env.json           ~/projects/<repo> local.env (binary, byte-exact)
# OP_PASSWORD / OP_SECRET_KEY / OP_TOTP_SECRET / GHE_TOKEN come from the env, else prompt (GHE_TOKEN falls back to gh).
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
projects=${PROJECTS:-$HOME/projects}
OP_ADDRESS=${OP_ADDRESS:-ibm.ent.1password.com}
OP_EMAIL=${OP_EMAIL:-maciej.pruchnik@ibm.com}
GHE_USER=${GHE_USER:-Maciej-Pruchnik}

ask() {
  eval "v=\${$1:-}"
  if [ -z "$v" ]; then
    printf '%s: ' "$2" >&2
    stty -echo
    IFS= read -r v
    stty echo
    echo >&2
  fi
  [ -n "$v" ] || { echo "$1 is empty" >&2; exit 1; }
  eval "$1=\$v"
}

ask OP_PASSWORD "1Password password for $OP_EMAIL"
ask OP_SECRET_KEY "1Password Secret Key (A3-...)"
ask OP_TOTP_SECRET "1Password 2FA TOTP seed (base32)"
if [ -z "${GHE_TOKEN:-}" ]; then
  GHE_TOKEN=$(gh auth token --hostname github.ibm.com 2>/dev/null || true)
fi
ask GHE_TOKEN "github.ibm.com token for $GHE_USER"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
chmod 700 "$tmp"

cat > "$tmp/dev-env.env" <<EOF
OP_ADDRESS=$OP_ADDRESS
OP_EMAIL=$OP_EMAIL
OP_PASSWORD=$OP_PASSWORD
OP_SECRET_KEY=$OP_SECRET_KEY
OP_TOTP_SECRET=$OP_TOTP_SECRET
GHE_USER=$GHE_USER
GHE_TOKEN=$GHE_TOKEN
EOF

cd "$root"
sops -e --input-type dotenv --output-type dotenv \
  --filename-override secrets/dev-env.env "$tmp/dev-env.env" > secrets/dev-env.env.new
mv secrets/dev-env.env.new secrets/dev-env.env

for pair in askswsupport:askswsupport/nodejs-app01/local.env hyparest:hyparest/local.env; do
  name=${pair%%:*}
  src=$projects/${pair#*:}
  out=secrets/$name.local.env.json
  sops -e --input-type binary --output-type json \
    --filename-override "$out" "$src" > "$out.new"
  mv "$out.new" "$out"
done

echo "encrypted: secrets/dev-env.env secrets/askswsupport.local.env.json secrets/hyparest.local.env.json"
