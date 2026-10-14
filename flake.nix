{
  description = "deploy-rs: T3 Code server and OpenCode config on Fyre";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
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
      deploy-rs,
      opencode-config,
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      lib = pkgs.lib;
      profile = "/nix/var/nix/profiles/t3";
      t3User = "mach12";
      t3Home = "/home/${t3User}";

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
        WorkingDirectory=${t3Home}
        ExecStart=${profile}/bin/t3 serve --host 0.0.0.0 --port 3773 --base-dir ${t3Home}/.t3
        Restart=on-failure
        RestartSec=3

        [Install]
        WantedBy=multi-user.target
      '';

      t3 = pkgs.t3code.override {
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

      tools = pkgs.buildEnv {
        name = "t3-host-tools";
        paths = [
          t3
          pkgs.opencode
          pkgs.git
          pkgs.zsh
          pkgs.sops
          pkgs.ssh-to-age
          playwrightMcp
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
        install -d -o ${t3User} -g ${t3User} -m 755 ${t3Home}/projects/.agents

        rm -rf ${t3Home}/.config/opencode.new
        mkdir -p ${t3Home}/.config/opencode.new
        cp -a ${opencode-config}/. ${t3Home}/.config/opencode.new/
        chmod -R u+rwX ${t3Home}/.config/opencode.new
        if [ -f ${t3Home}/.config/opencode.new/opencode.jsonc ]; then
          sed -i \
            's|/Users/mach12/projects/.agents/AGENTS.md|${t3Home}/projects/.agents/AGENTS.md|g' \
            ${t3Home}/.config/opencode.new/opencode.jsonc
        fi
        chown -R ${t3User}:${t3User} ${t3Home}/.config/opencode.new
        rm -rf ${t3Home}/.config/opencode
        mv ${t3Home}/.config/opencode.new ${t3Home}/.config/opencode

        install -o ${t3User} -g ${t3User} -m 644 \
          ${./payload/projects-agents.md} \
          ${t3Home}/projects/.agents/AGENTS.md
        install -d -o ${t3User} -g ${t3User} \
          ${t3Home}/.config/opencode/skills/playwright
        install -o ${t3User} -g ${t3User} -m 644 \
          ${playwrightSkill} \
          ${t3Home}/.config/opencode/skills/playwright/SKILL.md
        su -s /bin/bash ${t3User} -c 'HOME=${t3Home} ${playwrightMcp}/bin/playwright-mcp --version'

        install -d -o ${t3User} -g ${t3User} -m 700 ${t3Home}/projects
        age_key=$(mktemp)
        chmod 600 "$age_key"
        ${pkgs.ssh-to-age}/bin/ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key > "$age_key"
        secret_out=$(mktemp)
        chmod 600 "$secret_out"
        SOPS_AGE_KEY_FILE="$age_key" ${pkgs.sops}/bin/sops -d --output-type dotenv \
          ${./secrets/api.key.env} > "$secret_out"
        rm -f "$age_key"
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
        rm -rf /root/t3ibm-secrets

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
    };
}
