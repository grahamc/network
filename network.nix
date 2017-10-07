let
  secrets = import ./secrets.nix;
in {
  zoidberg = { ... }: {
    imports = [
      (import ./zoidberg { inherit secrets; })
    ];
  };

  router = { ... }: {
    deployment = {
      targetHost = "67.246.21.246"; # "10.5.3.1";
    };

    imports = [
      (import ./router { inherit secrets; })
    ];
  };
}
