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
      targetHost = "10.5.2.1";
    };

    imports = [
      (import ./router { inherit secrets; })
    ];
  };
}
