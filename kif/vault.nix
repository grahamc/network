/*

Bootstrap steps:

0. vault operator init -recovery-shares=1 -key-shares=1 -recovery-threshold=1 -key-threshold=1
1. vault write aws-personal/config/root access_key=... secret_key=... region=us-east-1
2. vault write -force aws-personal/config/rotate-root
3. vault kv put packet/config api_token=-
*/

{ secrets }:
{ lib, pkgs, config, ... }:
let
  address = (if config.services.vault.tlsKeyFile == null
    then "http://"
    else "https://") + config.services.vault.address;

  plugin_args = (if config.services.vault.tlsKeyFile == null
    then ""
    else "-ca-cert=/run/vault/certificate.pem");

  pluginPkgs = pkgs.callPackage ./plugins.nix {};

  plugins = {
    pki = {
      type = "secret";
    };

    aws = {
      type = "secret";
    };

    packet = {
      type = "secret";
      package = pluginPkgs.vault-plugin-secrets-packet;
      command = "vault-plugin-secrets-packet";

      # vault kv put packet/config api_token=-
      # vault kv put packet/role/nixos-foundation type=project ttl=3600 max_ttl=3600 project_id=86d5d066-b891-4608-af55-a481aa2c0094 read_only=false
    };
    #oauthapp = {
      # wl-paste | vault write oauth2/github/config -provider=github client_id=theclientid client_secret=- provider=github

      # scopes: https://developer.github.com/apps/building-oauth-apps/understanding-scopes-for-oauth-apps/
      # vault write oauth2/bitbucket/config/auth_code_url state=foo scopes=bar,baz

      # vault write oauth2/github/config/auth_code_url state=$(uuidgen) scopes=repo,gist
      # now it is broken ... https://github.com/puppetlabs/vault-plugin-secrets-oauthapp/issues/4
    #  type = "secret";
    #  package = pkgs.vault-plugin-secrets-oauthapp;
    #  command = "vault-plugin-secrets-oauthapp";
    #};
  };
  mounts = {
    "approle/" = {
      type = "auth";
      plugin = "approle";
    };
    "aws-personal/" = {
      type = "secrets";
      plugin = "aws";
    };
    "pki_ca/" = {
      type = "secrets";
      plugin = "pki";
    };
    "pki_intermediate/" = {
      type = "secrets";
      plugin = "pki";
    };
    "secret/" = {
      type = "secrets";
      plugin = "kv";
    };

    "packet/" = {
      type = "secrets";
      plugin = "packet";
    };
    #"oauth2/github/" = {
    #  type = "secrets";
    #  plugin = "oauthapp";
    #};
  };

  writes = [
    {
      path = "auth/approle/role/buildkite-nixops";
      args = {
        token_policies = "buildkite-nixops";
        token_ttl = "720h";
        token_max_ttl = "720h";
      };
    }
    {
      path = "packet/role/nixos-foundation";
      args = {
        type = "project";
        ttl = "3600";
        max_ttl = "3600";
        project_id = "86d5d066-b891-4608-af55-a481aa2c0094";
        read_only = "false";
      };
    }
    {
      path = "aws-personal/roles/nixops-deploy";
      args = {
        credential_type = "iam_user";
        policy_document = builtins.toJSON {
          Version = "2012-10-17";
          Statement = [
            {
              Effect = "Allow";
              Action = "s3:ListBucket";
              Resource = "arn:aws:s3:::mybucket";
            }
            {
              Effect = "Allow";
              Action = [ "s3:GetObject" "s3:PutObject" ];
              Resource = "arn:aws:s3:::grahamc-nixops-state/*.nixops";
            }
            {
              Effect = "Allow";
              Action = [
                "dynamodb:GetItem"
                "dynamodb:PutItem"
                "dynamodb:DeleteItem"
              ];
              Resource = "arn:aws:dynamodb:*:*:table/grahamc-nixops-lock";
            }
          ];
        };
      };
    }
  ];



  policies = {
    "buildkite-nixops" = {
      document = ''
        path "auth/token/create" {
          capabilities = [ "create", "update" ]
        }

        path "auth/token/revoke-self" {
          capabilities = [ "update" ]
        }

        path "packet/creds/nixos-foundation" {
          capabilities = [ "read" ]
        }

        path "aws-personal/creds/nixops-deploy" {
          capabilities = [ "read" ]
        }
      '';
    };
  };

  pluginsBin = pkgs.runCommand "vault-env" {}
  ''
    mkdir -p $out/bin

    ${builtins.concatStringsSep "\n" (lib.attrsets.mapAttrsToList (name: info:
    if info ? package then
    ''
      (
        echo "#!/bin/sh"
        echo 'exec ${info.package}/bin/${info.command} "$@"'
      ) > $out/bin/${info.command}
      chmod +x $out/bin/${info.command}
    '' else ""
    ) plugins)}
  '';

  writeCheckedBash = pkgs.writers.makeScriptWriter {
    interpreter = "${pkgs.bash}/bin/bash";
    check = "${pkgs.shellcheck}/bin/shellcheck";
  };

  vault-setup = writeCheckedBash "/bin/vault-setup" ''
    PATH="${pkgs.glibc}/bin:${pkgs.curl}/bin:${pkgs.procps}/bin:${pkgs.vault}/bin:${pkgs.jq}/bin:${pkgs.coreutils}/bin"

    set -eux

    scratch=$(mktemp -d -t tmp.XXXXXXXXXX)
    function finish {
      rm -rf "$scratch"
    }
    trap finish EXIT
    chmod 0700 "$scratch"

    export VAULT_ADDR=${address}
    export VAULT_CACERT=/run/vault/certificate.pem
    export HOME=/root

    if [ -f /run/keys/vault-unseal-json ]; then
      curl \
        --request PUT \
        --data @/run/keys/vault-unseal-json \
        --cacert /run/vault/certificate.pem \
        "${address}/v1/sys/unseal"
    fi

    if [ -f /run/keys/vault-login ]; then
      vault login - < /run/keys/vault-login > /dev/null
    fi

    rm /run/keys/vault*

    vault secrets disable pki_ca || true
    vault secrets disable pki_intermediate || true

    ${builtins.concatStringsSep "\n" (lib.attrsets.mapAttrsToList (name: value:
      if value ? package then
      ''
        expected_sha_256="$(sha256sum ${pluginsBin}/bin/${value.command} | cut -d " " -f1)"

        echo "Re-registering ${name}"
        vault plugin register -command "${value.command}" -args="${plugin_args}" -sha256 "$expected_sha_256" ${value.type} ${name}
        vault write sys/plugins/reload/backend plugin=${name}
      '' else ""
    ) plugins)}

    ${builtins.concatStringsSep "\n" (lib.attrsets.mapAttrsToList (path: info:
      ''
        if ! vault ${info.type} list -format json | jq -e '."${path}"?'; then
          vault ${info.type} enable -path=${path} ${info.plugin}
        fi
      ''
    ) mounts)}

    ${builtins.concatStringsSep "\n" (lib.attrsets.mapAttrsToList (name: policy:
      ''
        echo ${lib.escapeShellArg policy.document} | vault policy write ${name} -
      ''
    ) policies)}

    ${builtins.concatStringsSep "\n" (builtins.map ({ path, args }: ''
      vault write ${lib.escapeShellArg path} \
      ${builtins.concatStringsSep " \\\n" (lib.attrsets.mapAttrsToList (name: value:
        "  ${lib.escapeShellArg name}=${lib.escapeShellArg value}"
      ) args)}
      ''
    ) writes)}

    #vault write auth/approle/role/buildkite-nixops token_policies="buildkite-nixops" \
    #    token_ttl=720h token_max_ttl=720h

    # Replace our selfsigned cert  with a vault-made key.
    # 720h: the laptop can only run for 30 days without a reboot.
    # Note: pki backends are obliterated a section or so above.
    vault secrets tune -max-lease-ttl=720h pki_ca
    sleep 1

    echo "Generating root certificate"
    vault write -field=certificate pki_ca/root/generate/internal \
      common_name="localhost" \
      ttl=719h > "$scratch/root-certificate.pem"

    vault write pki_ca/config/urls \
        issuing_certificates="${address}/v1/pki/ca" \
        crl_distribution_points="${address}/v1/pki/crl"
    sleep 1

    echo "Generating intermediate certificate"
    vault secrets tune -max-lease-ttl=718h pki_intermediate
    vault write -format=json pki_intermediate/intermediate/generate/internal \
        common_name="localhost Intermediate Authority" \
        | jq -r '.data.csr' > "$scratch/pki_intermediate.csr"

    vault write -format=json pki_ca/root/sign-intermediate csr=@"$scratch/pki_intermediate.csr" \
        format=pem_bundle ttl="717h" \
        | jq -r '.data.certificate' > "$scratch/intermediate.cert.pem"
    vault write pki_intermediate/intermediate/set-signed certificate=@"$scratch/intermediate.cert.pem"
    sleep 1

    echo "Generating Vault's certificate"
    vault write pki_intermediate/roles/localhost \
        allowed_domains="localhost" \
        allow_subdomains=false \
        max_ttl="716h"

    vault write -format json pki_intermediate/issue/localhost \
      common_name="localhost" ttl="715h" > "$scratch/short.pem"

    jq -r '.data.certificate' < "$scratch/short.pem" > "$scratch/certificate.server.pem"
    jq -r '.data.ca_chain[]' < "$scratch/short.pem" >> "$scratch/certificate.server.pem"
    jq -r '.data.private_key' < "$scratch/short.pem" > "$scratch/vault.key"

    mv "$scratch/root-certificate.pem" /run/vault/certificate.pem
    mv "$scratch/vault.key" /run/vault/vault.key
    mv "$scratch/certificate.server.pem" /run/vault/certificate.server.pem

    pkill --signal HUP --exact vault
  '';


in {
  deployment.keys = {
    "vault-unseal-json".keyFile = secrets.kif.vault-unseal-json;
    "vault-login".keyFile = secrets.kif.vault-login;
  };

  environment = {
    systemPackages = [ pkgs.vault vault-setup ];
    variables = {
      VAULT_ADDR = address;
      VAULT_CACERT = "/run/vault/certificate.pem";
    };
    etc."vault.sh".text = ''
      export VAULT_ADDR=${address}
      export VAULT_CACERT=/run/vault/certificate.pem
    '';
  };

  services.vault = {
    enable = true;
    address = "localhost:8200";
    storageBackend = "file";
    storagePath = "/rpool/persist/vault/";
    extraConfig = ''
      api_addr = "${address}"
      plugin_directory = "${pluginsBin}/bin"
      log_level = "trace"
    '';
    tlsCertFile = "/run/vault/certificate.server.pem";
    tlsKeyFile = "/run/vault/vault.key";
  };

  systemd.services.vault-tls-bootstrap = {
    wantedBy = [ "vault.service" ];
    path = with pkgs; [ openssl ];
    unitConfig.Before = [ "vault.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''

      rm -rf /run/vault
      mkdir /run/vault

      touch /run/vault/vault.key
      chmod 0600 /run/vault/vault.key

      touch /run/vault/certificate.pem
      chmod 0644 /run/vault/certificate.pem

      openssl req -x509 -subj /CN=localhost -nodes -newkey rsa:4096 -days 1 \
        -keyout /run/vault/vault.key \
        -out /run/vault/certificate.pem

      cp  /run/vault/certificate.pem  /run/vault/certificate.server.pem

      chown ${config.systemd.services.vault.serviceConfig.User}:${config.systemd.services.vault.serviceConfig.Group} /run/vault/{vault.key,certificate.pem}
      ${pkgs.procps}/bin/pkill --signal HUP vault
    '';
  };
  systemd.services.vault-unlock = {
    wantedBy = [ "vault.service" "multi-user.target" ];
    wants = [ "vault-unseal-json-key.service" "vault-login-key.service" ];
    unitConfig.After = [ "vault.service" "vault-unseal-json-key.service" "vault-login-key.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      ${vault-setup}/bin/vault-setup
    '';
  };
}
