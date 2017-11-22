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
      targetHost = if true then "10.5.3.1" else "67.246.21.246";
    };

    imports = [
      (import ./router { inherit secrets; })
    ];
  };
}
