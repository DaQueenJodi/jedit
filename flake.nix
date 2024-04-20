{
  inputs = rec {
    nixpkgs.url = "github:NixOS/nixpkgs/release-23.11";
    zig-overlay.url = "github:mitchellh/zig-overlay";
  };
  outputs = inputs @ {
    self,
    nixpkgs,
    ...
  }:
  let
    pkgs = nixpkgs.legacyPackages.x86_64-linux;
    zig = inputs.zig-overlay.packages.x86_64-linux.master-2024-04-12;
  in
  {
    devShells.x86_64-linux.default = pkgs.mkShell {
      packages = with pkgs; [
        zig
        pkg-config
        notcurses
      ];
    };
  };
}
