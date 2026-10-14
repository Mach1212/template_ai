{
  description = "deploy-rs: T3 Code server and OpenCode config on Fyre";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-node18.url = "github:NixOS/nixpkgs/abae504e2aaed4fcf99c401beb4f56811b302082";
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    opencode-config = {
      url = "path:./opencode-config";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-node18,
      deploy-rs,
      opencode-config,
    }:
    let
      system = "x86_64-linux";
      lib = nixpkgs.lib;
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfreePredicate = p: lib.getName p == "1password-cli";
      };
      node18Pkgs = nixpkgs-node18.legacyPackages.${system};
      node18 = node18Pkgs.nodejs_18;
      # ibm_db's prebuilt DB2 clidriver links libcrypt.so.1 / libpam / libxml2; RHEL 10 has
      # libcrypt.so.2 only. Libs come from node18's nixpkgs so their glibc matches node's.
      nodeDev = pkgs.symlinkJoin {
        name = "nodejs-18-dev";
        paths = [ node18 ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/node \
            --prefix LD_LIBRARY_PATH : ${
              lib.makeLibraryPath (
                with node18Pkgs;
                [
                  libxcrypt-legacy
                  pam
                  stdenv.cc.cc.lib
                  zlib
                  libxml2
                ]
              )
            }
        '';
      };
      profile = "/nix/var/nix/profiles/t3";
      t3User = "mach12";
      t3Home = "/home/${t3User}";
      gitName = "Maciej-Pruchnik";
      gitEmail = "maciej.pruchnik@ibm.com";
      agentDocsUrl = "https://github.ibm.com/Maciej-Pruchnik/agent_docs.git";

      t3Unit = pkgs.writeText "t3code.service" ''
        [Unit]
        Description=T3 Code server
        After=network-online.target
        Wants=network-online.target

        [Service]
        Type=simple
        User=${t3User}
        Group=${t3User}
        Environment=HOME=${t3Home}
        Environment=XDG_CONFIG_HOME=${t3Home}/.config
        Environment=PATH=${profile}/bin:/usr/bin:/bin
        # Nix OpenSSL finds no CA bundle on RHEL without these (nix.sh sets them for login shells only)
        Environment=NIX_SSL_CERT_FILE=/etc/pki/tls/certs/ca-bundle.crt
        Environment=SSL_CERT_FILE=/etc/pki/tls/certs/ca-bundle.crt
        # skills' MCP env (`''${JIRA_PERSONAL_TOKEN}`, …) expands from the OpenCode process env
        EnvironmentFile=-${t3Home}/projects/api.key
        EnvironmentFile=-${devEnvDir}/mcp.env
        WorkingDirectory=${t3Home}
        ExecStart=${profile}/bin/t3 serve --host 0.0.0.0 --port 3773 --base-dir ${t3Home}/.t3
        Restart=on-failure
        RestartSec=3

        [Install]
        WantedBy=multi-user.target
      '';

      # OpenCode 1.19.0 (nixpkgs): newest 1.x, inside T3 0.0.45's supported range
      # (>=1.14.19 <2.0.0). Same version as the workstation. The plugins (OMO, openrtk,
      # ibm-ica-auth) use the 1.x plugin API; OpenCode 2.x does not load them.
      opencode = pkgs.opencode;

      t3 = pkgs.t3code.override {
        inherit opencode;
        enableOpencode = true;
        enableCodex = false;
      };

      playwrightMcp = pkgs.writeShellScriptBin "playwright-mcp" ''
        export HOME="''${HOME:-${t3Home}}"
        export PATH="${pkgs.nodejs_22}/bin:${pkgs.chromium}/bin:$PATH"
        exec ${pkgs.nodejs_22}/bin/npx --yes @playwright/mcp@0.0.83 \
          --headless \
          --isolated \
          --executable-path ${pkgs.chromium}/bin/chromium \
          --viewport-size 1440x900 \
          --timeout-navigation 90000 \
          "$@"
      '';

      playwrightSkill = pkgs.writeText "playwright-SKILL.md" ''
        ---
        name: playwright
        description: >-
          MUST USE for any browser-related tasks. Browser automation via Playwright MCP.
          Headless Chromium on this host.
        mcp:
          playwright:
            command: ${profile}/bin/playwright-mcp
        ---

        # Playwright (headless Chromium)

        `skill_mcp(mcp_name="playwright", tool_name=..., arguments={...})`.

        Launches headless Chromium from the Nix profile. No Edge extension and no workstation cookies.

        Tools: `browser_navigate`, `browser_snapshot`, `browser_click`, `browser_type`, `browser_tabs`, `browser_take_screenshot`.
      '';

      opSignin = pkgs.writeShellScriptBin "op" ''
        set -euo pipefail
        real=${pkgs._1password-cli}/bin/op
        export PATH="${
          lib.makeBinPath [
            pkgs.coreutils
            pkgs.findutils
            pkgs.gnused
            pkgs.gnugrep
            pkgs.oath-toolkit
            pkgs.util-linux
          ]
        }:$PATH"
        # hypa1pass evaluates base.env under `env -i`: HOME unset
        export HOME="''${HOME:-$(cd ~ && pwd)}"
        creds="$HOME/.config/op/t3-signin.env"
        tok="$HOME/.config/op/t3-session"

        if [ -n "''${OP_SERVICE_ACCOUNT_TOKEN:-}" ] || [ ! -r "$creds" ]; then
          exec "$real" "$@"
        fi
        case "''${1:-}" in
          account | signin | signout | --version | -v | --help | -h | "") exec "$real" "$@" ;;
        esac

        get() { sed -n "s/^$1=//p" "$creds" | head -n 1; }
        umask 077
        # hypa1pass runs `op read` (base.env) and `op inject` concurrently
        exec 9>"$tok.lock"
        flock 9
        s=$(cat "$tok" 2>/dev/null || true)
        # sessions expire after 30 min idle; skip the whoami round trip while fresh
        if [ -z "$s" ] || { [ -z "$(find "$tok" -mmin -20 2>/dev/null)" ] \
          && ! "$real" whoami --session "$s" >/dev/null 2>&1 9>&-; }; then
          address=$(get OP_ADDRESS)
          # op reads the password, then the 2FA code, from stdin; the code must arrive after the prompt.
          # Generate the code first, early in its 30 s window, so it can't roll over mid sign-in.
          while [ $(( $(date +%s) % 30 )) -gt 22 ]; do sleep 1; done
          code=$(oathtool --totp -b "$(get OP_TOTP_SECRET)")
          answers() {
            get OP_PASSWORD
            sleep 2
            printf '%s\n' "$code"
          }
          # 9>&-: op may spawn a long-lived `op daemon`; it must not inherit the lock fd
          if "$real" account list --format json 9>&- | grep -q "\"$address\""; then
            s=$(answers | "$real" signin --account "$address" --raw 9>&-)
          else
            s=$(answers | "$real" account add --address "$address" \
              --email "$(get OP_EMAIL)" --secret-key "$(get OP_SECRET_KEY)" --signin --raw 9>&-)
          fi
          printf '%s' "$s" > "$tok"
        fi
        touch "$tok"
        exec 9>&-
        exec "$real" --session "$s" "$@"
      '';

      devEnvDir = "${t3Home}/.config/t3-dev-env";

      devEnvSecrets = ''
        dev_out=$(mktemp)
        chmod 600 "$dev_out"
        SOPS_AGE_KEY_FILE="$age_key" ${pkgs.sops}/bin/sops -d --output-type dotenv \
          ${./secrets/dev-env.env} > "$dev_out"
        got=$(awk -F= '/^[A-Za-z0-9_]+=/{print $1}' "$dev_out" | sort)
        want=$(printf '%s\n' GHE_TOKEN GHE_USER OP_ADDRESS OP_EMAIL OP_PASSWORD OP_SECRET_KEY OP_TOTP_SECRET | sort)
        if [ "$got" != "$want" ]; then
          echo "dev-env names do not match the deploy set" >&2
          printf '%s\n' "$got" >&2
          rm -f "$age_key" "$dev_out"
          exit 1
        fi
        dev_get() { sed -n "s/^$1=//p" "$dev_out" | head -n 1; }

        install -d -o ${t3User} -g ${t3User} -m 700 ${t3Home}/.config/op ${devEnvDir}
        grep '^OP_' "$dev_out" > ${t3Home}/.config/op/t3-signin.env
        chown ${t3User}:${t3User} ${t3Home}/.config/op/t3-signin.env
        chmod 600 ${t3Home}/.config/op/t3-signin.env
        rm -f ${t3Home}/.config/op/t3-session
        # an `op daemon` that inherited the wrapper's lock fd holds flock forever; drop it
        pkill -u ${t3User} -x op 2>/dev/null || true
        pkill -u ${t3User} -f '^op daemon' 2>/dev/null || true
        rm -f ${t3Home}/.config/op/t3-session.lock ${t3Home}/.config/op/op-daemon.sock

        printf 'https://%s:%s@github.ibm.com\n' "$(dev_get GHE_USER)" "$(dev_get GHE_TOKEN)" \
          > ${t3Home}/.git-credentials
        chown ${t3User}:${t3User} ${t3Home}/.git-credentials
        chmod 600 ${t3Home}/.git-credentials
        printf 'GITHUB_PERSONAL_ACCESS_TOKEN=%s\n' "$(dev_get GHE_TOKEN)" > ${devEnvDir}/mcp.env
        chown ${t3User}:${t3User} ${devEnvDir}/mcp.env
        chmod 600 ${devEnvDir}/mcp.env
        rm -f "$dev_out"
        su -s /bin/sh ${t3User} -c '
          export HOME=${t3Home}
          g=${pkgs.git}/bin/git
          $g config --global credential.https://github.ibm.com.helper store
          $g config --global user.name ${lib.escapeShellArg gitName}
          $g config --global user.email ${lib.escapeShellArg gitEmail}
        '

        # ~/projects/.agents: live clone of agent_docs; agents pull/push it, so never overwrite a clone
        agents=${t3Home}/projects/.agents
        if [ -L "$agents" ] || { [ -e "$agents" ] && [ ! -d "$agents/.git" ]; }; then
          rm -rf "$agents"
        fi
        rm -rf ${t3Home}/personal/agent_docs
        [ -L ${t3Home}/.agents ] && rm -f ${t3Home}/.agents
        if [ ! -d "$agents/.git" ]; then
          su -s /bin/sh ${t3User} -c '
            export HOME=${t3Home}
            g=${pkgs.git}/bin/git
            $g clone ${agentDocsUrl} ${t3Home}/projects/.agents
          '
        fi
        su -s /bin/sh ${t3User} -c '
          export HOME=${t3Home}
          g=${pkgs.git}/bin/git
          h=$(hostname -s)
          $g -C ${t3Home}/projects/.agents config user.name "Agent ($h)"
          $g -C ${t3Home}/projects/.agents config user.email "agent@$h.dev.fyre.ibm.com"
        '

        for repo in askswsupport hyparest; do
          src=${./secrets}/$repo.local.env.json
          [ -f "$src" ] || continue
          SOPS_AGE_KEY_FILE="$age_key" ${pkgs.sops}/bin/sops -d --input-type json --output-type binary \
            "$src" > ${devEnvDir}/$repo.local.env
          chown ${t3User}:${t3User} ${devEnvDir}/$repo.local.env
          chmod 600 ${devEnvDir}/$repo.local.env
        done
      '';

      tools = pkgs.buildEnv {
        name = "t3-host-tools";
        paths = [
          t3
          opencode
          pkgs.git
          pkgs.zsh
          pkgs.sops
          pkgs.ssh-to-age
          playwrightMcp
          opSignin
          nodeDev
          pkgs.uv
          pkgs.github-mcp-server
          # openrtk plugin: `which rtk` at load, else it disables itself
          pkgs.rtk
          pkgs.nodemon
          pkgs.poetry
        ];
      };

      hosts = [
        "mach121"
        "mach122"
        "mach123"
        "mach124"
      ];

      activate = deploy-rs.lib.${system}.activate.custom tools ''
        set -euo pipefail

        if ! id ${t3User} >/dev/null 2>&1; then
          useradd --create-home --shell /bin/bash --user-group ${t3User}
        fi

        install -d -o ${t3User} -g ${t3User} ${t3Home}/.config
        install -d -o ${t3User} -g ${t3User} ${t3Home}/.t3
        install -d -o ${t3User} -g ${t3User} -m 755 ${t3Home}/personal
        install -d -o ${t3User} -g ${t3User} -m 755 ${t3Home}/projects

        rm -rf ${t3Home}/.config/opencode.new
        mkdir -p ${t3Home}/.config/opencode.new
        cp -a ${opencode-config}/. ${t3Home}/.config/opencode.new/
        find ${t3Home}/.config/opencode.new -name '._*' -delete
        # workstation-only: Edge cookie jar + macOS Keychain; the stock webfetch serves the hosts
        rm -f ${t3Home}/.config/opencode.new/plugins/edge-cookies-webfetch.ts
        # jupyter: VS Code extension on the workstation's localhost:9123
        rm -rf ${t3Home}/.config/opencode.new/skills/jupyter
        chmod -R u+rwX ${t3Home}/.config/opencode.new
        if [ -f ${t3Home}/.config/opencode.new/opencode.jsonc ]; then
          sed -i \
            's|/Users/mach12/projects/.agents/AGENTS.md|${t3Home}/projects/.agents/AGENTS.md|g' \
            ${t3Home}/.config/opencode.new/opencode.jsonc
        fi
        chown -R ${t3User}:${t3User} ${t3Home}/.config/opencode.new
        rm -rf ${t3Home}/.config/opencode
        mv ${t3Home}/.config/opencode.new ${t3Home}/.config/opencode

        # ica auth sentinel: OpenCode calls ibm-ica-auth's loader (custom fetch: store=false,
        # model-not-found retry) only when auth.json has an ica entry. Real key stays in api.key.
        auth=${t3Home}/.local/share/opencode/auth.json
        install -d -o ${t3User} -g ${t3User} ${t3Home}/.local ${t3Home}/.local/share ${t3Home}/.local/share/opencode
        [ -s "$auth" ] || echo '{}' > "$auth"
        if ! ${pkgs.jq}/bin/jq -e '.ica' "$auth" >/dev/null; then
          ${pkgs.jq}/bin/jq '.ica = {"type":"api","key":"ica-key-from-api.key"}' "$auth" > "$auth.new"
          mv "$auth.new" "$auth"
        fi
        chown ${t3User}:${t3User} "$auth"
        chmod 600 "$auth"

        # T3 provider: OpenCode enabled (same as mach121's UI-set config); other settings kept
        t3set=${t3Home}/.t3/userdata/settings.json
        install -d -o ${t3User} -g ${t3User} ${t3Home}/.t3/userdata
        [ -s "$t3set" ] || echo '{}' > "$t3set"
        ${pkgs.jq}/bin/jq '.providerInstances.opencode = {"driver":"opencode","enabled":true,"config":{"binaryPath":"opencode","serverUrl":"","serverPassword":"","customModels":[]}}' "$t3set" > "$t3set.new"
        mv "$t3set.new" "$t3set"
        chown ${t3User}:${t3User} "$t3set"

        install -d -o ${t3User} -g ${t3User} \
          ${t3Home}/.config/opencode/skills/playwright
        install -o ${t3User} -g ${t3User} -m 644 \
          ${playwrightSkill} \
          ${t3Home}/.config/opencode/skills/playwright/SKILL.md
        su -s /bin/bash ${t3User} -c 'HOME=${t3Home} ${playwrightMcp}/bin/playwright-mcp --version'

        age_key=$(mktemp)
        chmod 600 "$age_key"
        ${pkgs.ssh-to-age}/bin/ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key > "$age_key"
        secret_out=$(mktemp)
        chmod 600 "$secret_out"
        SOPS_AGE_KEY_FILE="$age_key" ${pkgs.sops}/bin/sops -d --output-type dotenv \
          ${./secrets/api.key.env} > "$secret_out"
        got=$(awk -F= '/^[A-Za-z0-9_]+=/{print $1}' "$secret_out" | sort)
        want=$(printf '%s\n' \
          CARBON_MCP_SESSION \
          CARBON_MCP_TOKEN \
          ELASTICSEARCH_ADDRESS \
          ELASTICSEARCH_PASSWORD \
          ELASTICSEARCH_PROD_ADDRESS \
          ELASTICSEARCH_PROD_API_KEY \
          ELASTICSEARCH_USERNAME \
          IBM_ICA_DEV_API_KEY \
          JIRA_PERSONAL_TOKEN | sort)
        if [ "$got" != "$want" ]; then
          echo "api.key names do not match the deploy set" >&2
          printf '%s\n' "$got" >&2
          exit 1
        fi
        install -o ${t3User} -g ${t3User} -m 600 "$secret_out" ${t3Home}/projects/api.key
        rm -f "$secret_out"
        ${lib.optionalString (builtins.pathExists ./secrets/dev-env.env) devEnvSecrets}
        rm -f "$age_key"
        rm -rf /root/t3ibm-secrets

        printf '%s\n' 'case ":$PATH:" in *":${profile}/bin:"*) ;; *) PATH="${profile}/bin:$PATH" ;; esac' \
          > /etc/profile.d/t3-tools.sh
        chmod 644 /etc/profile.d/t3-tools.sh
        mkdir -p /usr/local/bin
        ln -sfn ${profile}/bin/op /usr/local/bin/op
        # workstation skills hardcode nix-darwin's per-user profile path
        mkdir -p /etc/profiles/per-user/${t3User}/bin
        for bin in uvx npx github-mcp-server; do
          ln -sfn ${profile}/bin/$bin /etc/profiles/per-user/${t3User}/bin/$bin
        done

        install -m 644 ${t3Unit} /etc/systemd/system/t3code.service
        systemctl daemon-reload
        systemctl enable t3code.service
        if ! systemctl restart t3code.service; then
          journalctl -u t3code.service -n 80 --no-pager || true
          exit 1
        fi
      '';

      mkNode = name: {
        hostname = "${name}.dev.fyre.ibm.com";
        sshUser = "root";
        sshOpts = [
          "-o"
          "BatchMode=yes"
          "-o"
          "StrictHostKeyChecking=accept-new"
          "-i"
          "/root/.ssh/t3ibm_deploy"
          "-o"
          "IdentitiesOnly=yes"
        ];
        profiles.t3 = {
          user = "root";
          sshUser = "root";
          profilePath = profile;
          path = activate;
        };
      };
    in
    {
      deploy.nodes = lib.listToAttrs (
        map (name: {
          name = name;
          value = mkNode name;
        }) hosts
      );

      checks.${system} = deploy-rs.lib.${system}.deployChecks self.deploy;

      packages.${system}.deploy-rs = deploy-rs.packages.${system}.deploy-rs;

      devShells = lib.genAttrs [ "aarch64-darwin" "x86_64-linux" ] (
        s:
        let
          p = nixpkgs.legacyPackages.${s};
        in
        {
          default = p.mkShell {
            packages = [
              p.sops
              p.ssh-to-age
              p.rsync
              p.coreutils
            ];
          };
        }
      );
    };
}
