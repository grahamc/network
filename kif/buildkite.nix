{ pkgs, ... }: {
  services.buildkite-agent = {
    enable = true;
    meta-data = "test=test";
    tokenPath = "/run/keys/buildkite-token";
    openssh.privateKeyPath = "/dev/null";
    openssh.publicKeyPath = "/dev/null";
    runtimePackages = [ pkgs.gzip pkgs.xz pkgs.gnutar pkgs.nix pkgs.bash ];

    hooks.environment = ''
      set -u
      echo "--- :nixos:"
      echo "--- :key: Authenticating with Vault"
      . /etc/vault.sh
      get_token() (
        . /run/keys/buildkite-nixops-vault.env

        login_token=$(${pkgs.vault}/bin/vault write -field token auth/approle/login \
          role_id="$VAULT_ROLE_ID" secret_id="$VAULT_SECRET_ID")
        VAULT_TOKEN=$login_token ${pkgs.vault}/bin/vault token create \
          -field token
      )
      export VAULT_TOKEN=$(get_token)
      set +u
    '';

    hooks.pre-exit = ''
      echo "--- :closed_lock_with_key: Revoking Vault tokens"
      ${pkgs.vault}/bin/vault token revoke -self
    '';
  };
  systemd.services = {
    buildkite-agent.requires = [ "vault.target" ];
    buildkite-bootstrap = {
      requires = [ "vault.target" ];
      wantedBy = [ "buildkite-agent.service" "multi-user.target" ];
      unitConfig.Before = [ "buildkite-agent.service" ];
      path = [ pkgs.vault ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      # Write out the buildkite token
      # Then, allocate an approle / secret ID login token
      script = ''
        . /etc/vault.sh
        export HOME=/root
        secwrite() (
          umask 077
          rm -f /run/keys/"$1"
          touch /run/keys/"$1"
          cat > /run/keys/"$1"
          chmod 0400 /run/keys/"$1"
          chown "$2" /run/keys/"$1"
        )

        vault kv get -field=token secret/buildkite/grahamc/token \
          | secwrite buildkite-token "buildkite-agent:root"

        (
          printf "export VAULT_ROLE_ID=%s\n" "$(vault read -field=role_id auth/approle/role/buildkite-nixops/role-id)"

          # Note: on two lines so we never pass the secret-id as an argument
          printf "export VAULT_SECRET_ID="
          vault write -f -field secret_id auth/approle/role/buildkite-nixops/secret-id
        ) | secwrite buildkite-nixops-vault.env "buildkite-agent:root"
      '';
    };
  };
}
