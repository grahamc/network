{ pkgs, ... }: {
  services.buildkite-agent = {
    enable = true;
    tokenPath = "/run/keys/buildkite-token";
    openssh.privateKeyPath = "/dev/null";
    openssh.publicKeyPath = "/dev/null";
    runtimePackages = [ pkgs.gzip pkgs.gnutar pkgs.nix pkgs.bash ];
  };
  systemd.services = {
    buildkite-bootstrap = {
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
      '';
    };
  };
}
