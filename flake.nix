{
  description = "r2-image-worker development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    moonbit-overlay.url = "github:moonbit-community/moonbit-overlay";
  };

  outputs =
    {
      nixpkgs,
      moonbit-overlay,
      ...
    }:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
        "x86_64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          overlays = [ moonbit-overlay.overlays.default ];
        };
    in
    {
      devShells = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              moonbit-bin.moonbit.latest
              nodejs_22
            ];
          };
        }
      );
    };
}
